#!/usr/bin/env perl

use lib($ENV{LDIP_ROOT} . "/lib");

use LDIP::Entry;
use LDIP;

my $seqno = $ARGV[0];
unless ($seqno) {
    die "Usage: requeue_orig.pl <seqno> <directory to start search in>\n";
}

my $ldip = new LDIP;

my ($year, $month, $date) = $ldip->ymd;
my $today_dir = $ARGV[1] ? $ARGV[1] : $ldip->c->LDIP_COMPLETED_BASE . "/$year/$month/$date";
my $entry;

if (-d $today_dir) {
    eval {
        $entry = LDIP::Entry->new($seqno, $today_dir);
    };
    
    if ($@ || !$entry->uid) {
        print "Error using base $today_dir: $@ trying completed base (will take a second)...\n";
        $entry = LDIP::Entry->new($seqno, $ldip->c->LDIP_COMPLETED_BASE);
    }

} else {
    print "$today_dir doesn't exist, trying completed base (will take a second)...\n";
    $entry = LDIP::Entry->new($seqno, $ldip->c->LDIP_COMPLETED_BASE);
}

$entry->write_to_queue;

print "Original entry " . $entry->seqno . " written to queue: " . lc($entry->get_value('subeventtype')) . "\n\n";

