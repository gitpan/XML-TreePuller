#!/usr/bin/env perl

use Test::More tests => 9;

use strict;
use warnings;

use XML::TreePuller;

my $xml = XML::TreePuller->new(location => 't/data/50-wikiexample.xml');

$xml->config('/wiki', 'short');
$xml->config('/wiki/siteinfo', 'subtree');
$xml->config('/wiki/page/title', 'short');

my @results;

while(my ($path, $e) = $xml->next) {
	push(@results, $path);
	ok(ref($e) eq 'XML::TreePuller::Element');
}

ok($results[0] eq '/wiki');
ok($results[1] eq '/wiki/siteinfo');
ok($results[2] eq '/wiki/page/title');
ok($results[3] eq '/wiki/page/title');
ok(! defined($results[4]));