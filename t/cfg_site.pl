#!/usr/bin/env perl

use LeafyWeb::Site;

my $site = LeafyWeb::Site->new('web.mg2.org');

#print $site->instance_by_location('/saq') . "\n";
$site->configure;

use Data::Dumper;
