package Mouffette::Feeds;

use 5.010001;
use strict;
use warnings;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(validate_feed
		    unsubscribe_feed
		    list_feeds
		    feed_fetch_and_dispatch
		    flush_queue
		  );

our $VERSION = '0.01';

use AnyEvent::HTTP;
use Data::Dumper;
use XML::Feed;

sub list_feeds {
  my ($form, $jid, $dbh) = @_;
  my $list = $dbh->prepare('SELECT handle FROM assoc WHERE jid = ?');
  $list->execute($jid);
  my @subscribed;
  while (my @row = $list->fetchrow_array) {
    push @subscribed, shift(@row);
  };
  my $reply;
  if (@subscribed) {
    $reply = "Your subscriptions: " . join(", ", @subscribed);
  } else {
    $reply = "No subscriptions";
  }
  $form->($reply);
}

sub unsubscribe_feed {
  my ($form, $jid, $dbh, $handle) = @_;
  # check
  my $assoccheck =
    $dbh->prepare('SELECT * FROM assoc WHERE handle = ? AND jid = ?;');
  $assoccheck->execute($handle, $jid);
  unless ($assoccheck->fetchrow_array) {
    return $form->("You are not subscribed to $handle");
  };

  # delete
  my $sth =
    $dbh->prepare('DELETE FROM assoc WHERE handle = ? AND jid = ?;');
  $sth->execute($handle, $jid);
  # usual error checking
  if (my $error = $sth->err) {
    return $form->("Cannot unsubscribe: $error");
  }
  $form->("you're unsubscribed from $handle now");

  # if it's empty, clean it
  my $check = $dbh->prepare('SELECT handle FROM assoc WHERE handle = ?');
  $check->execute($handle);
  unless ($check->fetchrow_array) {
    my $clean = $dbh->prepare('DELETE FROM feeds WHERE handle = ?');
    $clean->execute($handle);
    print "Purged feeds from $handle\n";
  }
}


sub validate_feed {
  my ($form, $jid, $dbh, $handle, $url) = @_;
  # sanity check
  unless ($handle and $url) {
    return $form->("Invalid arguments. See the help");
  }

  my $sthcheck =
    $dbh->prepare('SELECT handle, url FROM feeds WHERE url = ? or handle = ?;');
  my $sthfeed = $dbh->prepare('INSERT INTO feeds (handle, url) VALUES (?, ?);');
  my $sthassc = $dbh->prepare('INSERT INTO assoc (handle, jid) VALUES (?, ?);');
  my $sthhttp = $dbh->prepare('INSERT INTO gets  (url) VALUES (?);');

  $sthcheck->execute($url, $handle);
  if (my $checkerror = $sthcheck->err) {
    return $form->($checkerror);
  }
  # handle or url already present?
  if (my @feedrow = $sthcheck->fetchrow_array()) {
    ($handle, $url) = @feedrow;
    # yes? ok, add the association and notify.
    $sthassc->execute($handle, $jid);
    $form->("Feed already present: you're subscribed to " . 
	    "$handle ($url) now");
  } else {
    # fetch the feed. Everything is passed to the AnyEvent::HTTP
    # closure. Who knows if we get leaks doing so
    http_get $url, sub {
      my ($data, $hdr) = @_;
      # check if it's valid
      unless ($hdr->{Status} eq "200") {
	return $form->("Feed failed: " . $hdr->{Reason});
      }
      # and it parses cleanly
      my $feed = XML::Feed->parse(\$data) or
	return $form->("Feed failed: " . XML::Feed->errstr);
      # ok, all seems valid.
      $sthfeed->execute($handle, $url);
      $sthassc->execute($handle, $jid);
      $sthhttp->execute($url);
      if (my $error = $sthfeed->err || $sthassc->err || $sthhttp->err) {
	$form->("errors: $error");
      } else {
	$form->("Feed from $url, with title " . $feed->title .
		" subscribed as " . $handle);
      }
    };
  }
}


sub fetch_feeds {
  my $dbh = shift;
  # get the feeds we need to fetch
  my $query = q{
     SELECT feeds.handle, feeds.url, gets.etag, gets.time
     FROM feeds INNER JOIN gets ON feeds.url=gets.url
     ORDER BY feeds.handle;};
  my $sthlist = $dbh->prepare($query);
  $sthlist->execute;
  my $targets = $sthlist->fetchall_arrayref;
  while (@$targets) {
    # now we prepare the code to do a conditional get, to save resources
    my ($handle, $url, $etag, $time) = @{shift @$targets};
    my %myheaders = ( 'User-Agent' => "Mouffette RSS->XMPP gateway v.0.1"  );
    if ($etag) {
      $myheaders{'If-None-Match'} = $etag;
    } elsif ($time) {
      $myheaders{'If-Modified-Since'} = $time;
    };
    http_get $url, headers => \%myheaders, sub {
      my ($data, $hdr) = @_;
      if ($hdr->{Status} eq "200") {
  	print "Got $handle!\n";
	insert_feeds($dbh, $handle, $data, $hdr);
      } else {
  	print "$handle => $hdr->{Status}\n";
      }
    };
  }
}

sub insert_feeds {
  my ($dbh, $handle, $data, $hdr) = @_;
  # first thing (or last thing, I'm not sure)
  my $updatequery = q{
UPDATE gets SET etag = ?, time = ?
WHERE url = (SELECT url FROM feeds WHERE handle = ?);
};
  my $updategets = $dbh->prepare($updatequery);
  $updategets->execute($hdr->{etag}, $hdr->{'last-modified'}, $handle);
  return;
}


sub dispatch_feeds {
  my ($dbh, $roster) = @_;
  # open the feeditems table, retrieve the unseen

  # for each unseen, look into the assoc where the feed should be dispatched

  # ask the roster for the status. If it's not "" (available), put
  # them into the queue
  
  return;
}

sub flush_queue {
  my ($dbh, $jid) = @_;
  print "Spamming $jid as is available now\n";
  # if the contact gets online, look into the queue for its id and spam it
}


sub feed_fetch_and_dispatch {
  my ($dbh, $roster) = @_;
  # look in the feeds table,
  dispatch_feeds($dbh, $roster);
  fetch_feeds($dbh);
  # look in the assoc table,
}



1;
