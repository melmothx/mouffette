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
		download => {
			     help => "download <url>: get the HTTP headers for <url>",
			     call => \&download,
			    },
		help => {
			 help => "help <arg>: get the help string for <arg>",
			 call => \&give_help,
			}
	    );


sub parse_cmd {
  my ($con, $msg) = @_;
  my @args = split(/\s+/, $msg->any_body);
  my $cmd = shift @args;
  if ($cmd && (exists $commands{$cmd})) {
    $commands{$cmd}->{call}->($con, $msg, @args);
  } else {
    give_help($con, $msg);
  }
}

sub download {
  my ($con, $msg, $url) = @_;
  return unless $url;
  http_get $url, sub {
    my ($body, $hdr) = @_;
    bot_fast_reply($con, $msg, Dumper($hdr));
  }
}

sub give_help {
  my ($con, $msg, $arg) = @_;
  my $answer;
  if ($arg && (exists $commands{$arg})) {
    $answer = $commands{$arg}->{help};
  } else {
    $answer = "Available commands: " . join(",", sort(keys %commands));
  }
  bot_fast_reply($con, $msg, $answer);
}


sub bot_fast_reply {
  my ($con, $msg, $what) = @_;
  return unless defined $what;
  my $reply = $msg->make_reply;
  $reply->add_body($what);
  $reply->send($con);
}


1;

