package Mouffette::Commands;

use 5.010001;
use strict;
use warnings;
use AnyEvent::HTTP;
use Data::Dumper;
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(parse_cmd);

our $VERSION = '0.01';

=head2 execute_cmd($connection, $msg);

We define an hash with coderefs. If the command exists, execute it
with the provided arguments.

=cut

my %commands = (
		download => \&download,
		help => \&give_help,
	    );


sub parse_cmd {
  my ($con, $msg) = @_;
  my @args = split(/\s+/, $msg->any_body);
  my $cmd = shift @args;
  if ($cmd && $commands{$cmd} ) {
    $commands{$cmd}->($con, $msg, @args);
  } else {
    my $reply = $msg->make_reply;
    $reply->add_body("command not supported");
    $reply->send($con);
  }
}

sub download {
  my ($con, $msg, $url) = @_;
  return unless $url;
  http_get $url, sub {
    my ($body, $hdr) = @_;
    my $reply = $msg->make_reply;
    $reply->add_body(Dumper($hdr));
    $reply->send($con);
  }
}

sub give_help {
  my ($con, $msg) = @_;
  my $reply = $msg->make_reply;
  $reply->add_body(join(" ", sort(keys %commands)));
  $reply->send($con);
}


1;
