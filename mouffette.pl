#!/usr/bin/env perl
use utf8;
use strict;
use warnings;
$| = 1;
binmode STDOUT, ":encoding(utf-8)";
binmode STDERR, ":encoding(utf-8)";

use AnyEvent;
use AnyEvent::XMPP::IM::Connection;
use AnyEvent::Strict;
use YAML::Any qw/LoadFile Dump/;
use lib './lib';
# use Mouffette::Feeds qw/rss_loop/;
use Mouffette::Commands qw/parse_cmd/;


die "The first parameter must be the configuration file\n" unless $ARGV[0];
die "Missing configuration file\n" unless -f $ARGV[0];

my $debug = 1;
my $conf = LoadFile($ARGV[0]);

# INITIALIZATION
pid_print("bot.pid");

# connection loop
my $loop = AnyEvent->condvar;
my $cl = AnyEvent::XMPP::IM::Connection->new (%{$conf->{connection}});
my $w; # the watcher;
my $interval = $conf->{bot}->{loopinterval};
my $db = $conf->{bot}->{db};

# Callback functions. The first argument to each callback is always
# the AnyEvent::XMPP::IM::Connection object itself.
$cl->reg_cb (
	     # placeholders
	     session_ready => sub {
	       my ($con, $acc) = @_;
	       debug_print("session ready, starting watcher!");
	       $w = AE::timer 0, $interval, sub {
		 print "watching";
	       };
	     },
	     connect => sub {
	       debug_print("Connected");
	     },
	     stream_pre_authentication => sub {
	       debug_print("Pre-authentication");
	     },
	     disconnect => sub {
	       my ($con, $h, $p, $reason) = @_;
	       warn "Disconnected from $h:$p: $reason";
	       $w = undef;
	       $loop->send;
	     },
	     roster_update => sub {
	       debug_print("Roster update");
	     },
	     error => sub {
	       my ($con, $err) = @_;
	       debug_print("ERROR: " . $err->string);
	     },
	     message_error => sub {
	       my ($con, $err) = @_;
	       debug_print("message error ", $err->type, $err->text);
	     },

	     # CONTACT MANAGING
	     contact_request_subscribe => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       $contact->send_subscribed;
	       # mutual subscription
	       $contact->send_subscribe;
	       debug_print($contact->jid, " mutual subscription");
	     },
	     contact_subscribed => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       my $reply = 
		 $contact->make_message( body => "I'll keep you updated, pal");
	       $reply->send($con);
	       debug_print($contact->jid, " is in the roster now");
	     },
	     contact_did_unsubscribe => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       $contact->send_unsubscribe;
	       debug_print($contact->jid, " is gone now");
	     },
	     contact_unsubscribed => sub {
	       my ($con, $roster, $contact, $message) = @_;
	       $contact->send_unsubscribed;
	       debug_print($contact->jid, " unsubscribed");
	     },
	     message => sub {
	       my ($con, $msg) = @_;
	       parse_cmd($con, $msg);
	       debug_print("Message from ", $msg->from, ":\n",
			   $msg->any_body);
	     },
	    );
$cl->connect();
$loop->recv;
# here we're out of the loop (hopefully);
$ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH.
my @command = ('perl', $0, @ARGV);
exec @command or die "can't exec myself: $!\n";

## tiny helpers. Everything more serious should go in a module under ./lib

sub debug_print {
  if ($debug) {
    my $time = localtime();
    print "[$time] ", @_, "\n";
  }
}

sub pid_print {
  my $pidfile = shift || "bot.pid";
  open (my $fh, ">", $pidfile) or die "Can't write pid file: $!\n";
  print $fh $$;
  close $fh;
}
