#!/usr/bin/env perl

use LeafyWeb::Package;
use Test::More qw(no_plan);

my $lfypkg = LeafyWeb::Package->new('x86_64_a22_core_2.2.4-devl.lpkg');

is($lfypkg->arch, 'x86_64', "basic parsing works?");

$lfypkg = LeafyWeb::Package->new('x86_64_a22_core_2.2.4-devl.lpkg');

print $lfypkg->arch . "\n";
print $lfypkg->prefix . "\n";
print $lfypkg->description . "\n";
