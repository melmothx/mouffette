package Mouffette::Feeds;

use 5.010001;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(rss_loop);

our $VERSION = '0.01';

=head2 rss_loop

Doc here

=cut

sub rss_loop {
  print "Using ", @_;
}

1;
