package Mouffette::Commands;

use 5.010001;
use strict;
use warnings;
require Exporter;


our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(parse_cmd);

our $VERSION = '0.01';

use AnyEvent::HTTP;
use Data::Dumper;
use Mouffette::Utils qw/bot_fast_reply/;
use Mouffette::Feeds qw/validate_feed
			unsubscribe_feed/;


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
			},
		feed => {
			 help => "feed <alias> <url>: subscribe the feed locate at <url> and give it an alias <alias>. E.g. feed library http://theanarchistlibrary.org/rss.xml",
			 call => \&validate_feed,
			},
		unsub => {
			  help => "unsub <alias>: unsubscribe the feed know as <alias>",
			  call => \&unsubscribe_feed,
			 },
	    );


sub parse_cmd {
  my ($con, $msg, $dbh) = @_;
  my @args = split(/\s+/, $msg->any_body);
  my $cmd = shift @args;
  if ($cmd && (exists $commands{$cmd})) {
    $commands{$cmd}->{call}->($con, $msg, $dbh, @args);
  } else {
    give_help($con, $msg);
  }
}

sub download {
  my ($con, $msg, $dbh, $url) = @_;
  return unless $url;
  http_get $url, sub {
    my ($body, $hdr) = @_;
    bot_fast_reply($con, $msg, Dumper($hdr));
  }
}

sub give_help {
  my ($con, $msg, $dbh, $arg) = @_;
  my $answer;
  if ($arg && (exists $commands{$arg})) {
    $answer = $commands{$arg}->{help};
  } else {
    $answer = "Available commands: " . join(", ", sort(keys %commands));
  }
  bot_fast_reply($con, $msg, $answer);
}



1;

