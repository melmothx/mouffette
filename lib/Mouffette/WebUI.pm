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

sub wi_report_status {
  my $dbh = shift;
  return "Hello world!";
}


1;

