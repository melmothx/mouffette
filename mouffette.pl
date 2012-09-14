#!/usr/bin/env perl

=head1 AUTHOR

Marco Pessotto, marco@theanarchistlibrary.org

=head1 COPYRIGHT AND LICENSE

No Copyright

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut


use utf8;
use strict;
use warnings;
$| = 1;
binmode STDOUT, ":encoding(utf-8)";
binmode STDERR, ":encoding(utf-8)";

use AnyEvent;
use AnyEvent::XMPP::IM::Connection;
use AnyEvent::HTTPD;
# use AnyEvent::Strict; # not in production
use DBI;
use YAML::Any qw/LoadFile Dump/;
use lib './lib';
use Mouffette::Utils qw/debug_print ts_print roster_check_max_client/;
use Mouffette::Commands qw/parse_cmd/;
use Mouffette::Feeds qw(
			 fetch_feeds
			 dispatch_feeds
			 flush_queue
		       );
use Mouffette::WebUI qw/wi_report_status/;
use Data::Dumper;
use Try::Tiny;


die "The first parameter must be the configuration file\n" unless $ARGV[0];
die "Missing configuration file\n" unless -f $ARGV[0];

my $conf = LoadFile($ARGV[0]);

# INITIALIZATION
pid_print("bot.pid");

# the DB
my $db = $conf->{bot}->{db};

# ok, little hack until I don't understand how to do it better:
unless (-f $db) {
  system("sqlite3 $db < schema.sql") == 0 or die "Cannot init the db\n";
  print "DB not existent, initialized\n";
}

my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "",
		       { AutoCommit => 1, 
			 'sqlite_unicode' => 1
		       })
  or die "Can't open connection to the db\n";
$dbh->do('PRAGMA foreign_keys = ON;');


my $reconnect_at_recv = 1;
# connection loop
my $loop = AE::cv;
my $cl = AnyEvent::XMPP::IM::Connection->new (%{$conf->{connection}});
my ($fetchloop, $dispatchloop); # the timers
my $interval = $conf->{bot}->{loopinterval} || 600;
my $maxclients = $conf->{bot}->{maxclients} || 100;


# Callback functions. The first argument to each callback is always
# the AnyEvent::XMPP::IM::Connection object itself.
$cl->reg_cb (
	     # placeholders
	     session_ready => sub {
	       my ($con) = @_;
	       ts_print("session ready, starting watcher!");
	       $fetchloop = AE::timer 1, $interval, sub {
		 fetch_feeds($dbh);
	       };
	       # after 10 seconds we start the dispatcher
	       $dispatchloop = AE::timer 30, $interval, sub {
		 dispatch_feeds($dbh, $con);
	       }
	     },
	     connect => sub {
	       ts_print("Connected");
	     },
	     stream_pre_authentication => sub {
	       ts_print("Pre-authentication");
	     },
	     disconnect => sub {
	       my ($con, $h, $p, $reason) = @_;
	       warn "Disconnected from $h:$p: $reason";
	       undef $fetchloop;
	       undef $dispatchloop;
	       $loop->send;
	     },
	     roster_update => sub {
	       ts_print("Roster update");
	     },
	     error => sub {
	       my ($con, $err) = @_;
	       ts_print("ERROR: " . $err->string);
	     },
	     message_error => sub {
	       my ($con, $err) = @_;
	       ts_print("message error ", $err->type, $err->text);
	       ts_print("Appending dump to errors.log");
	       open (my $fh, ">>", "errors.log") or
		 return warn "!!!! Couldn't open error log $!\n";
	       print $fh "======" . localtime() . "======\n",
		                    Dumper($err), 
		         "===============================\n";
	       close $fh;
	       try_to_recover_message_error($con, $err->xml_node);
	     },

	     # CONTACT MANAGING
	     presence_update => sub {
	       my ($con, $roster, $contact, $oldpres, $newpres) = @_;
	       # print "presence update from " . $contact->jid . "\n";
	       flush_queue($con, $contact, $dbh) if defined $newpres;
	     },
	     contact_request_subscribe => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       ts_print ($contact->jid, " required subscription");
	       unless (roster_check_max_client($con, $maxclients)) {
		 ts_print ("Max client reached!");
		 my $msg = $contact->make_message(
						  body => 
						  "sorry, max client reached!");
		 $msg->send($con);
		 $contact->send_unsubscribed;
		 return;
	       }
	       $contact->send_subscribed;
	       # mutual subscription
	       $contact->send_subscribe;
	       ts_print($contact->jid, " mutual subscription");
	     },
	     contact_subscribed => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       my $reply = 
		 $contact->make_message( body => "I'll keep you updated, pal");
	       $reply->send($con);
	       ts_print($contact->jid, " is in the roster now");
	     },
	     contact_did_unsubscribe => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       $contact->send_unsubscribe;
	       ts_print($contact->jid, " is gone now");
	     },
	     contact_unsubscribed => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       $contact->send_unsubscribed;
	       ts_print($contact->jid, " unsubscribed");
	     },
	     message => sub {
	       my ($con, $msg) = @_;
	       ts_print("From ", $msg->from, ": ", $msg->any_body);
	       parse_cmd($con, $msg, $dbh);
	     },
	    );

my $http_status_host = $conf->{bot}->{statushost} || "127.0.0.1";
my $http_status_port = $conf->{bot}->{statusport} || "9876";

my $httpd = AnyEvent::HTTPD->new (
				  host => $http_status_host,
				  port => $http_status_port,
				  allowed_methods => [ 'GET' ],
				 );
$httpd->reg_cb (
		'' => sub {
		  my ($httpd, $req) = @_;
		  $req->respond ({ content => ['text/html',
					       wi_report_status(
								$dbh,
								$maxclients
							       )
					      ]});
		  $httpd->stop_request;
		},
	       );

$cl->connect();

$SIG{'INT'} = \&safe_exit;
$SIG{'QUIT'} = \&safe_exit;


$loop->recv;
$dbh->disconnect or warn $dbh->errstr;

print "DB disconnected cleanly\n";

exit 0 unless $reconnect_at_recv;


# here we're out of the loop (hopefully);
$ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH.
my @command = ('perl', $0, @ARGV);
exec @command or die "can't exec myself: $!\n";

sub safe_exit {
  my ($sig) = shift;
  print "Caught a SIG$sig... ";
  $reconnect_at_recv = 0;
  $loop->send;
}


sub pid_print {
  my $pidfile = shift || "bot.pid";
  open (my $fh, ">", $pidfile) or die "Can't write pid file: $!\n";
  print $fh $$;
  close $fh;
}

### this is an HACK because we try to get the internals of the object
### AE::XMPP::Node

sub try_to_recover_message_error {
  my ($con, $error) = @_;
  my $success = 1;
  my $body;
  my $to;
  try {
    $to = $error->[4]->[1]->[1]->[4];
    foreach my $line (@{$error->[4]->[1]->[1]->[4]}) {
      next unless (ref $line eq 'ARRAY');
      next if $line->[0] eq '2';
      if ($line->[0] eq '1') {
	$body .= $line->[1];
      }
    }
  } catch {
    ts_print($_);
    $success = 0;
  };
  return unless ($success and $to and $body);
  my $msg;
  try {
    $msg = $con->get_roster->get_contact($to)->make_message(
							    body => "RT\n$body",
							    type => 'chat',
							   );
  } catch {
    ts_print("Couldn't get contact $to: $_");
    return;
  };
  return unless defined $msg;
  ts_print("Resending message in 5 minutes");
  # here we basically create a memory leak
  my $retry; $retry = AE::timer 0, 300, sub {
    ts_print "Resending message to $to now!";
    $msg->send($con);
    # but here we free it (hopefully),
    undef $retry;
  };
}

