#!/usr/bin/perl

use strict;
use warnings;
use lib './lib';
use Mouffette::Feeds qw/xml_feed_parse/;
use Data::Dumper;
use LWP::Simple;

die "provide an url as argument\n" unless $ARGV[0];

my $data = get $ARGV[0];


print Dumper(xml_feed_parse("test", \$data));
