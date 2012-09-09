package Mouffette::Feeds;

use 5.010001;
use strict;
use warnings;
use utf8;
use Encode qw/encode_utf8/;
use Digest::SHA qw/sha1_hex/;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(validate_feed
		    unsubscribe_feed
		    list_feeds
		    feed_fetch_and_dispatch
		    delete_queue
		    retrieve_queue
		    flush_queue
		    xml_feed_parse
		  );

our $VERSION = '0.01';

use AnyEvent::HTTP;
use Data::Dumper;
use XML::Feed;
use Try::Tiny;
use HTML::PullParser;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Mouffette::Utils qw/debug_print/;

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
      # check if it's rate-limited
      if ($hdr->{'x-ratelimit-limit'}) {
	return $form->("There is a rate limit on this server, sorry");
      }
      check_unzip_broken_server($hdr, \$data);
      my $feed;
      try {
	$feed = XML::Feed->parse(\$data)
      } catch {
	warn "caught error: $_";
	return $form->("Error while parsing XML");
      };
      # and it parses cleanly
      return $form->("Feed failed: " . XML::Feed->errstr) unless $feed;
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


####################################################################
#                     FETCHING                                     #
####################################################################

sub fetch_feeds {
  my $dbh = shift;
  my $sthlist =
    $dbh->prepare('SELECT feeds.handle, feeds.url, gets.etag, gets.time
     FROM feeds INNER JOIN gets ON feeds.url=gets.url
     ORDER BY feeds.handle;');
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
  	debug_print("Got $url!");
	check_unzip_broken_server($hdr, \$data);
	insert_feeds($dbh, $handle, \$data, $hdr);
      } else {
  	debug_print("$handle => $hdr->{Status}");
      }
    };
  }
}

sub insert_feeds {
  my ($dbh, $handle, $data, $hdr) = @_;
  # data here is actually a reference to a scalar
  # create a hashref with url => { key => value  }
  my $items = xml_feed_parse($handle, $data);
  return unless $items;

  # { 'hash' => {
  # 		  'body' => 'bla',
  # 		  'handle' => 'lib',
  # 		  'date' => 1345011030,
  # 		  'url' => 'permalink',
  # 		  'title' => 'My title'
  # 		   }, { ... }, { ... }}

  # now we check if the feeds already exist (based on the hash)
  my $hashes = $dbh->prepare('SELECT hash FROM feeditems where handle = ?');
  $hashes->execute($handle);
  my %exist;
  while (my ($hash) = $hashes->fetchrow_array) {
    $exist{$hash} = 1;
  };
  # insert code
  my $insertion = $dbh->prepare('INSERT INTO feeditems
     (date, handle, title, url, body, hash, send) VALUES
     ( ?  ,   ?   ,   ?  ,  ? ,  ?  ,  ? ,   1  );');
				
  my $deletion =
    $dbh->prepare('DELETE FROM feeditems
                   WHERE hash = ? AND handle = ? AND send = 0');

  # do
  foreach my $hashparsed (keys %$items) {
    $insertion->execute(
			$items->{$hashparsed}->{date},
			$items->{$hashparsed}->{handle},
			$items->{$hashparsed}->{title},
			$items->{$hashparsed}->{url},
			$items->{$hashparsed}->{body},
			$items->{$hashparsed}->{hash},
		       ) unless $exist{$hashparsed};
  };
  foreach my $oldhash (keys %exist) {
    $deletion->execute($oldhash, $handle)
      unless $items->{$oldhash};
  }
  # update the gets
  my $updategets = $dbh->prepare('UPDATE gets SET etag = ?, time = ?
     WHERE url = (SELECT url FROM feeds WHERE handle = ?);');
  $updategets->execute($hdr->{etag}, $hdr->{'last-modified'}, $handle);
  debug_print("Done with fetching $handle");
  return;
}

sub xml_feed_parse {
  my ($handle, $data) = @_;
  my $feed;
  try {
    $feed = XML::Feed->parse($data);
  } catch {
    warn "Error on $handle while parsing: $_";
    return;
  };
  unless ($feed) {
    warn "Error on $handle: ", XML::Feed->errstr, "\n";
    return;
  }
  my %items;
  # create a hashref with url => { key => value  }
  for my $entry ($feed->entries) {
    # HERE WE HAVE A PROBLEM BECAUSE SOME BUGGY FEEDS HAVE THE SAME LINK
    my $link  = $entry->link || " ";
    my $title = parse_html($entry->title);
    my $date = $entry->modified || $entry->issued;
    my $realdate;
    if ($date) {
      $realdate = $date->epoch;
    } else {
      $realdate = 1; # which is basically +30 years ago :-)
    }
    my $body = $entry->content || $entry->summary;
    my $realbody;
    if (defined $body) {
      $realbody = parse_html($body->body);
    }

    my %fields;
    $fields{handle} = $handle;
    $fields{title}  = $title;
    $fields{url}    = $link;
    $fields{body}   = $realbody;
    $fields{date}   = $realdate;

    my $hash = _feed_make_hash(\%fields);
    $fields{hash}   = $hash;

    $items{$hash} = \%fields;
  }
  return \%items;
}

sub _feed_make_hash {
  my $item = shift;
  return sha1_hex($item->{handle} . $item->{title} . $item->{url} .
    $item->{body} . $item->{date}); # nothing should be undefined here.
}

# our parser
sub parse_html {
  my $html = shift;
  return " " unless $html;
  my $p = HTML::PullParser->new(
				doc   => $html,
				start => '"S", tagname',
				end   => '"E", tagname',
				text  => '"T", dtext',
				empty_element_tags => 1,
				marked_sections => 1,
				unbroken_text => 1,
				ignore_elements => [qw(script style)]
			       ) or return undef;
  my @text;
  while (my $token = $p->get_token) {
    my $type = shift @$token;
    if ($type eq 'S') {
      my $tag = shift @$token;
      if ($tag =~ m/^(div|p|br)$/s) {
	push @text, "\n";
      }
    } elsif ($type eq 'E') {
      my $tag = shift @$token;
      if ($tag =~ m/^(div|p|br)$/s) {
	push @text, "\n";
      }
    } elsif ($type eq 'T') {
      my $txt = shift @$token;
      $txt =~ s/\s+/ /;
      push @text, $txt;
    } else {
      warn "unknon type passed in the parser\n";
    }
  }
  my $result = join("", @text);
  undef @text;
  $result =~ s/\n{2,}/\n/gs;
  return $result;
};


####################################################################
#                     DISPATCH                                     #
####################################################################
    ## 
    # $contacts = {
     # $feeds = { lib => {

# $feeds = {
# 	  lib => {
# 		  "marco@test" => {
# 				   msg => sub { };
# 				   avail => 1;
# 				  },
# 		  "ruff@test" => {
# 				  msg => sub { };
# 				  avail => 1;
# 				 }
# 		 },
# 	  next => { user => { }, user, { } },
	  
sub get_availables {
  # build a hash with code refs for sending message and the followed feeds; 
  my ($dbh, $con) = @_;
  my $roster = $con->get_roster;
  return unless $roster->is_retrieved;

  my $feedtable = {};
  my $assoc = $dbh->prepare('SELECT handle, jid FROM assoc');
  $assoc->execute;
  while(my @ass = $assoc->fetchrow_array) {
    my ($handle, $jid) = @ass;
    $feedtable->{$handle} = {} unless exists $feedtable->{$handle};
    $feedtable->{$handle}->{$jid} = { avail => 0};
  }

  foreach my $c ($roster->get_contacts) {
    my $jid = $c->jid;
    next unless (defined $c->get_priority_presence);
    foreach my $hand (keys %$feedtable) {
      if (exists $feedtable->{$hand}->{$jid}) {
	$feedtable->{$hand}->{$jid}->{avail} = 1;
	$feedtable->{$hand}->{$jid}->{msg} = sub {
	  my $message = shift;
	  $c->make_message( body => $message,
			    type => 'chat')->send($con);
	};
      }
    }
  }
  return $feedtable;
}

sub dispatch_feeds {
  my ($dbh, $con) = @_;
  my $feedtable = get_availables($dbh, $con);
  $dbh->begin_work or warn "NO TRANSACTIONS!: $dbh->errstr";
  # open the feeditems table, retrieve the unseen
  my $tosend =
    $dbh->prepare('SELECT handle, title, url, body FROM
                              feeditems WHERE send = 1 ORDER BY date;');
  my $fdsent =
    $dbh->prepare('UPDATE feeditems SET send = 0
                            WHERE send = 1 AND url = ? AND handle = ?;');
  my $toqueue =
    $dbh->prepare('INSERT INTO queue (handle, jid, body) VALUES (?, ?, ?);');

  $tosend->execute;
  while (my @feed = $tosend->fetchrow_array) {
    # compose message
    my ($handle, $title, $url, $body) = @feed;
    my $message = "$handle: $title\n$body\n$url\n========εοφ========\n\n";
    foreach my $buddy (keys %{$feedtable->{$handle}}) {
      if ($feedtable->{$handle}->{$buddy}->{avail}) {
	debug_print("Sending $url to $buddy");
	$feedtable->{$handle}->{$buddy}->{msg}->($message);
      } else {
	debug_print("Queded $handle for $buddy");
	$toqueue->execute($handle, $buddy, $message);
      }
    }
    debug_print("Marking feeds $url as read");
    $fdsent->execute($url, $handle);
  };
  warn "Errors: $tosend->err" if $tosend->err;
  $dbh->commit; # or $dbh->rollback; 
  return;
}

sub flush_queue {
  # ask the contact if it wants to be spammed
  my ($con, $contact, $dbh) = @_;
  my $jid = $contact->jid;
  my $queue = $dbh->prepare('SELECT COUNT(id) FROM queue WHERE jid = ?');
  $queue->execute($jid);
  my ($count) = $queue->fetchrow_array;
  return unless $count;
  my $body = "You have $count feeds unread. Tell me \"getqueue\" if you want to send them all, or \"deletequeue\" if you want me to delete them. You can issue these commands at any time"; 
  $contact->make_message( body => $body, type => 'chat')->send($con);
}

sub retrieve_queue {
  my ($form, $jid, $dbh) = @_;
  $dbh->begin_work;
  my $queue = $dbh->prepare('SELECT body FROM queue WHERE jid = ?');
  my $flush = $dbh->prepare('DELETE FROM queue WHERE jid = ?');
  $queue->execute($jid);
  while (my ($body) = $queue->fetchrow_array) {
    $form->($body);
  }
  $flush->execute($jid);
  $dbh->commit;
  $form->("queue cleared");
}

sub delete_queue {
  my ($form, $jid, $dbh) = @_;
  my $deletion = $dbh->prepare('DELETE FROM queue WHERE jid = ?');
  $deletion->execute($jid);
  $form->("Your queue has been deleted");
}

# and this is just the glue

sub feed_fetch_and_dispatch {
  my ($dbh, $con) = @_;
  # look in the feeds table,
  dispatch_feeds($dbh, $con);
  fetch_feeds($dbh);
  # look in the assoc table,
}

sub check_unzip_broken_server {
  my ($hdr, $gzipped) = @_;
  if ($hdr->{'content-encoding'} and
      $hdr->{'content-encoding'} eq 'gzip') {
    my $uncompressed;
    if (gunzip $gzipped => \$uncompressed) {
      # we modify the referenced scalar
      $$gzipped = $uncompressed;
      undef $uncompressed;
    } else {
      warn "Uncompressing failed\n";
    }
  }
}


1;
