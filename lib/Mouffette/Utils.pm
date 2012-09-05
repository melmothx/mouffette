package Mouffette::Utils;

use 5.010001;
use strict;
use warnings;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(bot_fast_reply);

our $VERSION = '0.01';


sub bot_fast_reply {
  my ($con, $msg, $what) = @_;
  return unless defined $what;
  my $reply = $msg->make_reply;
  $reply->add_body($what);
  $reply->send($con);
}

1;

