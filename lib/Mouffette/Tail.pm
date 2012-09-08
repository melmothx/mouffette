# -*- mode: cperl -*-
package Mouffette::Tail;
use 5.010001;

use strict;
use warnings;

use File::Basename;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(file_tail);
our $VERSION = '0.01';

$| = 1;

my %file_stats;

sub file_tail {
  my $file = shift;
  my ($name, $path, $suffix) = fileparse($file);
  return unless (-f $file);
  return unless (-T $file);
  my $firstrun = 0;
  my $oldmoddate = 0;
  my $oldbytes;			# the old size, if any
  if (exists $file_stats{$file}) {
    $oldbytes = $file_stats{$file}
  } else {
    $oldbytes = 0;
    $firstrun = 1;
  }
  my $bytes = -s $file;		# the new size
  # update the hash
  $file_stats{$file} = $bytes;
  # the first run we just skip. An alternate solution could be: define
  # max, 500b, seek that from the end, read and output the stuff.
  return if $firstrun;

  return if ($oldbytes == $bytes); # nothing changed, so next!
  my $offset;
  if ($bytes > $oldbytes) { # the new size is bigger, so the offset is the 
    $offset = $oldbytes;    # old size
  } else {
    $offset = 0; # if the old size is bigger, it means the file was truncated
  }

  open (my $fh, '<:encoding(utf8)', $file)
    or die "Houston, we have a problem: $!";
  if ($offset > 0) {
    seek($fh, $offset, 0);    # move the cursor, starting from the end
  }
  my @saythings;
  while (<$fh>) {
    chomp;
    s/\r//g;
    next if m/^\s*$/;
    push @saythings, $_;
  }
  close $fh;
  # first run, don't output all the stuff.
  return unless $#saythings >= 0;
  $saythings[$#saythings] .=  " (" . $name . ")";
  return @saythings;
}

1;
