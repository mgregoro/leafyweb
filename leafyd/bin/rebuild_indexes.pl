#!/usr/bin/env perl

use lib($ENV{LEAFY_ROOT} . "/lib/perl");

use LeafyWeb::LeafyD;
my $ldip = new LeafyWeb::LeafyD;

# make sure ldipd isn't running
my ($ldip_running) = `ps -ef | grep ldipd | grep -v grep`;
$ldip_running = $ldip_running =~ /ldipd/ ? 1 : 0;
if ($ldip_running) {
    die "Stop ldipd before rebuilding indexes!\n";
}

$ldip->rebuild_indexes;

