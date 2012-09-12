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

our @EXPORT_OK = qw(debug_print
		    ts_print
		    roster_check_max_client
		    jid_is_in_roster
		  );

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


sub roster_check_max_client {
  my ($con, $max) = @_;
  my $roster = $con->get_roster;
  unless ($roster->is_retrieved) {
    ts_print "Roster is not retrieved yet!";
    return 0;
  }
  my $existing = scalar $roster->get_contacts;
  if ($existing < $max) {
    return 1;
  } else {
    return 0;
  }
}

sub jid_is_in_roster {
  my ($con, $jid) = @_;
  if (my $contact = $con->get_roster->get_contact($jid)) {
    if ($contact->is_on_roster) {
      debug_print "$jid is on the roster";
      return 1;
    }
  }
  return 0;
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
