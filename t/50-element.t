#!/usr/bin/env perl

use Test::More tests => 3;

use strict;
use warnings;

use XML::TreePuller;
use Data::Dumper;

my $xml = XML::TreePuller->new(location => 't/data/50-wikiexample.xml');
my @results;

my $element = $xml->next;
ok(ref($element) eq 'XML::TreePuller::Element');
@results = $element->get_elements('page/title');

ok($results[0]->text eq 'A good article');
ok($results[1]->text eq 'A bad article');


