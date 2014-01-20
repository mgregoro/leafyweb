#!/usr/bin/env perl

use LeafyWeb::Package;
use Test::More qw(no_plan);

my $lfypkg = LeafyWeb::Package->new($ARGV[0], undef, 1);
$lfypkg->install();
