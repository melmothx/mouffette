package Mouffette::WebUI;

use 5.010001;
use strict;
use warnings;
use utf8;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(wi_report_status);

our $VERSION = '0.01';

use HTML::Entities;

sub wi_report_status {
  my $dbh = shift;

  my @rows = ('<table id="feeds"><tr>',
	      '<th>Alias</th>',
	      '<th>Feed</th>',
	      '<th>Subscribers</th>',
	      '</tr>');

  my $usercount = 0;
  my $users = $dbh->prepare('SELECT DISTINCT jid FROM assoc');
  $users->execute();
  while ($users->fetchrow_array()) {
    $usercount++;
  };

  my $feedcount = 0;
  my $feeds =
    $dbh->prepare('SELECT feeds.handle, feeds.title, feeds.url,
   (SELECT COUNT (jid) FROM assoc WHERE feeds.handle = assoc.handle) AS count
     FROM feeds ORDER BY title');

  $feeds->execute();
  while(my ($users, $title, $url, $followers) = $feeds->fetchrow_array()) {
    push @rows, '<tr><td>' . encode_entities($users) . '</td><td><a href="'
      . $url . '">' . encode_entities($title) . '</a></td><td>' . $followers
	. '</td></tr>';
    $feedcount++;
  }
  push @rows, '</tr></table>';

  return '<div id="botstatus">'
    . "<p>Serving $feedcount feeds to $usercount user!</p>"
    . join("", @rows) . '</div>';
}


1;

