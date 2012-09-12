package Mouffette::Commands;

use 5.010001;
use strict;
use warnings;
use utf8;
require Exporter;


our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our @EXPORT_OK = qw(parse_cmd);

our $VERSION = '0.01';

use AnyEvent::HTTP;
use AnyEvent::XMPP::Util qw/bare_jid/;
use Data::Dumper;
use Mouffette::Feeds qw/validate_feed
			show_last_feeds
			show_all_feeds
			list_feeds
			search_feeds
			subscribe_feed
			delete_queue
			retrieve_queue
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
		list => {
			 help => "list the feeds you're subscribed to",
			 call => \&list_feeds,
			},
		getqueue => {
			     help => "get the unread feeds when you were not available",
			     call => \&retrieve_queue,
			    },
		deletequeue => {
				help => "delete your queue with unread feeds",
				call => \&delete_queue,
			       },
		show => {
			 help => "show <alias>:  show the last 3 entries from the feed known as <alias>",
			 call => \&show_last_feeds,
			},
		showall => {
			    help => "showall <alias>: show all the entry of the feed known as <alias>",
			    call => \&show_all_feeds,
			   },
		search => {
			   help => "search <site>: search into the existing feeds (I'll scan the urls I follow)",
			   call => \&search_feeds,
			  },
		subscribe => {
			      help => "subscribe <alias>: subscribe an existing feed (try search <my site> to see which feeds are already available",
			      call => \&subscribe_feed,
			     },
	    );


sub parse_cmd {
  my ($con, $msg, $dbh) = @_;
  my @args = split(/\s+/, $msg->any_body);
  my $cmd = shift @args;
  my $jid = bare_jid($msg->from);
  # closure with the code to send a message. Basically, we know that
  # the command wants an answer, so we pack $con, $msg there and pass
  # it, along with the bare jid for db operations
  my $form = sub {
    my $what = shift;
    return unless ((defined $what) and ($what ne ""));
    my $reply = $msg->make_reply;
    $reply->add_body($what);
    $reply->send($con);
  };
  if ($cmd && (exists $commands{$cmd})) {
    $commands{$cmd}->{call}->($form, $jid, $dbh, @args);
  } else {
    give_help($form);
  }
}

sub download {
  my ($form, $jid, $dbh, $url) = @_;
  return unless $url;
  http_get $url, sub {
    my ($body, $hdr) = @_;
    $form->(Dumper($hdr));
  }
}

sub give_help {
  my ($form, $jid, $dbh, $arg) = @_;
  my $answer;
  if ($arg && (exists $commands{$arg})) {
    $answer = $commands{$arg}->{help};
  } else {
    $answer = "Available commands: " . join(", ", sort(keys %commands))
      . "\nTell me “help feed” to see how to add new feeds";
  }
  $form->($answer);
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
