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
use Data::Dumper;
use XML::Feed;
use Mouffette::Utils qw/bot_fast_reply/;

sub validate_feed {
  my ($con, $msg, $url) = @_;
  return 0 unless $url;
  http_get $url, sub {
    my ($data, $hdr) = @_;
    unless ($hdr->{Status} eq "200") {
      return bot_fast_reply($con, $msg, $hdr->{Reason});
    }
    my $feed = XML::Feed->parse(\$data) or
      return bot_fast_reply($con, $msg, XML::Feed->errstr);
    bot_fast_reply($con, $msg, $feed->title);
    ### HERE WE HAVE TO INSERT $msg->from AND $url INTO THE DB
  };
};


1;
