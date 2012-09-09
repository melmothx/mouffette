package Mouffette::Utils;

use 5.010001;
use strict;
use warnings;
use utf8;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(debug_print ts_print);

our $VERSION = '0.01';

sub debug_print {
  return unless $ENV{MUFFDEBUG};
  my $time = localtime();
  print "[$time] ", join(" ", @_), "\n";
}

sub ts_print {
  my $time = localtime();
  print "[$time] ", join(" ", @_), "\n";
}




1;

