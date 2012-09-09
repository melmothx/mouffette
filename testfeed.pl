#!/usr/bin/perl

use strict;
use warnings;
use lib './lib';
use Mouffette::Feeds qw/xml_feed_parse/;
use Data::Dumper;
use LWP::UserAgent;

die "provide an url as argument\n" unless $ARGV[0];

my $ua = LWP::UserAgent->new(agent => "Mozilla");
$ua->show_progress(1);

my $data = $ua->get($ARGV[0])->decoded_content();

print Dumper(xml_feed_parse("test", \$data));


