#!/usr/bin/env perl
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
use Mouffette::Utils qw/debug_print ts_print/;
use Mouffette::Commands qw/parse_cmd/;
use Mouffette::Feeds qw(
			 fetch_feeds
			 dispatch_feeds
			 flush_queue
		       );
use Mouffette::WebUI qw/wi_report_status/;


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
my $interval = $conf->{bot}->{loopinterval};

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
	       $dispatchloop = AE::timer 10, $interval, sub {
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
	     },

	     # CONTACT MANAGING
	     presence_update => sub {
	       my ($con, $roster, $contact, $oldpres, $newpres) = @_;
	       # print "presence update from " . $contact->jid . "\n";
	       flush_queue($con, $contact, $dbh) if defined $newpres;
	     },
	     contact_request_subscribe => sub {
	       my ($con, $roster, $contact, $message) = @_;
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
					       wi_report_status($dbh)
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

