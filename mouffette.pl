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
use DBI;

die "The first parameter must be the configuration file\n" unless $ARGV[0];
die "Missing configuration file\n" unless -f $ARGV[0];

my $debug = 1;
my $conf = LoadFile($ARGV[0]);

# INITIALIZATION
pid_print("bot.pid");

# the DB
my $db = $conf->{bot}->{db};
my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "",
		       { AutoCommit => 1, })
  or die "Can't open connection to the db\n";
$dbh->do('PRAGMA foreign_keys = ON;');

# INITIALIZE THE DB
$dbh->do('CREATE TABLE IF NOT EXISTS feeds (
       handle	VARCHAR(30) PRIMARY KEY NOT NULL,	
       url 	TEXT UNIQUE NOT NULL);');
$dbh->do('CREATE TABLE IF NOT EXISTS gets (
          url    TEXT UNIQUE NOT NULL,
          etag   TEXT,
          time   TEXT,
          FOREIGN KEY(url) REFERENCES feeds(url) ON DELETE CASCADE);');
$dbh->do('CREATE TABLE IF NOT EXISTS assoc (
       id       INTEGER PRIMARY KEY,
       jid   	VARCHAR(150) NOT NULL,
       handle 	VARCHAR(30)  NOT NULL,
       CONSTRAINT jidhandle UNIQUE (jid, handle),
       FOREIGN KEY(handle) REFERENCES feeds(handle) ON DELETE CASCADE);');
$dbh->do('CREATE TABLE IF NOT EXISTS feeditems (
       id    	INTEGER PRIMARY KEY,
       date 	INTEGER,
       handle   VARCHAR(30) NOT NULL,
       title    VARCHAR(255),
       url	TEXT UNIQUE NOT NULL,
       body 	TEXT NOT NULL,
       FOREIGN KEY(handle) REFERENCES feeds(handle) ON DELETE CASCADE);');
$dbh->do('CREATE TABLE IF NOT EXISTS queue (
       id    	INTEGER PRIMARY KEY,
       handle 	VARCHAR(30) NOT NULL,
       jid	VARCHAR(150) NOT NULL,
       body 	TEXT NOT NULL,
       FOREIGN KEY(jid) REFERENCES assoc(jid),
       FOREIGN KEY(handle) REFERENCES feeds(handle));');

# connection loop
my $loop = AnyEvent->condvar;
my $cl = AnyEvent::XMPP::IM::Connection->new (%{$conf->{connection}});
my $w; # the watcher;
my $interval = $conf->{bot}->{loopinterval};

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
	     presence_update => sub {
	       my ($con, $roster, $contact, $oldpres, $newpres) = @_;
	       debug_print ("Presence update ", $contact->jid, ": ",
			    show_pres($newpres));
	     },
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
	       debug_print("From ", $msg->from, ": ", $msg->any_body);
	       parse_cmd($con, $msg, $dbh);
	     },
	    );
$cl->connect();

$SIG{'INT'} = \&safe_exit;
$SIG{'QUIT'} = \&safe_exit;


$loop->recv;
$dbh->disconnect or warn $dbh->errstr;
# here we're out of the loop (hopefully);
$ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH.
my @command = ('perl', $0, @ARGV);
exec @command or die "can't exec myself: $!\n";

sub safe_exit {
  my ($sig) = shift;
  print "Caught a SIG$sig... ";
  $dbh->disconnect or warn $dbh->errstr;
  print "DB disconnected, exiting cleanly\n";
  exit(0);
}

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


sub show_pres {
  my $pres = shift;
  my $string;
  if (not defined $pres) {
    $string = "offline";
  } elsif (not $pres->show) {
    $string = "available";
  } else {
    $string = $pres->show;
  }
  return $string;
}

