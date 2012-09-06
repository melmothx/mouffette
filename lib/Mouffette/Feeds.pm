package Mouffette::Feeds;

use 5.010001;
use strict;
use warnings;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(validate_feed);

our $VERSION = '0.01';

use AnyEvent::HTTP;
use AnyEvent::XMPP::Util qw/bare_jid/;
use Data::Dumper;
use XML::Feed;
use Mouffette::Utils qw/bot_fast_reply/;

sub validate_feed {
  my ($con, $msg, $dbh, $handle, $url) = @_;
  unless ($handle and $url) {
    return bot_fast_reply($con, $msg, "Invalid arguments. See the help");
  }
  my $jid = bare_jid($msg->from); # bare jid
  # first, check if the url is already in the db;
  my $sth =
    $dbh->prepare('SELECT handle, url FROM feeds WHERE url = ? or handle = ?;');
  my $sthfeed = $dbh->prepare('INSERT INTO feeds (handle, url) VALUES (?, ?);');
  my $sthassc = $dbh->prepare('INSERT INTO assoc (handle, jid) VALUES (?, ?);');

  $sth->execute($url, $handle);
  if (my @feedrow = $sth->fetchrow_array()) {
    ($handle, $url) = @feedrow;
    # in the next query we get an error if the same association is present.
    # I don't care and keep saying that the dude is subscribed.
    $sthassc->execute($handle, $jid);
    bot_fast_reply($con, $msg,
		   "Feed already present: you're subscribed to " . 
		   "$handle ($url) now");
  } else {
    http_get $url, sub {
      my ($data, $hdr) = @_;
      unless ($hdr->{Status} eq "200") {
	return bot_fast_reply($con, $msg, "Feed failed: " . $hdr->{Reason});
      }
      my $feed = XML::Feed->parse(\$data) or
	return bot_fast_reply($con, $msg, "Feed failed: " . XML::Feed->errstr);
      # ok, all seems valid.
      $sthfeed->execute($handle, $url);
      $sthassc->execute($handle, $jid);
      if (my $error = $sthfeed->err || $sthassc->err) {
	bot_fast_reply($con, $msg, "errors: $error");
      } else {
	bot_fast_reply($con, $msg,
		       "Feed from $url, with title " . $feed->title .
		       " subscribed as " . $handle);
      }
    };
  }
}



1;
