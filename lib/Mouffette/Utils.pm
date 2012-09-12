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


=head1 AUTHOR

Marco Pessotto, marco@theanarchistlibrary.org

=head1 COPYRIGHT AND LICENSE

No Copyright

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
