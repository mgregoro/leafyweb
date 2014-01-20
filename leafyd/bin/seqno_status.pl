#!/usr/bin/env perl

use lib($ENV{LEAFY_ROOT} . "/lib/perl");

use Getopt::Std;
use Net::LDAP::LDIF;
use LeafyWeb::LeafyD::Entry;
use LeafyWeb::LeafyD;

my $opts = {};

getopts('vpf', $opts);

my $seqno = $ARGV[0];
unless ($seqno) {
    die "Usage: seqno_status.pl <seqno|filename>\n";
}

my $ldip = new LeafyWeb::LeafyD;

my ($year, $month, $date) = $ldip->ymd;
my $today_dir = $ldip->c->LEAFYD_COMPLETED_BASE . "/$year/$month/$date";
my ($entry);

if (-e $seqno) {
    my $ldif = Net::LDAP::LDIF->new($seqno);
    $entry = $ldif->read_entry;
    $entry->add(LeafyDfromFile        =>      $seqno);
} else {
    $entry = LeafyWeb::LeafyD::Entry->new($seqno, $ldip->c->LEAFYD_QUEUE_BASE);
}

unless ($entry->get_value('uniqueid')) {
    if (-d $today_dir) {
        eval {
            $entry = LeafyWeb::LeafyD::Entry->new($seqno, $today_dir);
        };
        
        if ($@ || !$entry->uid) {
            print "Error using base $today_dir: $@ trying completed base (will take a second)...\n";
            $entry = LeafyWeb::LeafyD::Entry->new($seqno, $ldip->c->LEAFYD_COMPLETED_BASE);
        }

    } else {
        print "$today_dir doesn't exist, trying completed base (will take a second)...\n";
        $entry = LeafyWeb::LeafyD::Entry->new($seqno, $ldip->c->LEAFYD_COMPLETED_BASE);
    }
}

my ($path, $uid, $seqno) = $entry->get_value('LeafyDfromFile') =~
    /^(.*?)\/{0,1}?([\w\-\.]+)_([A-Z0-9]+)\.ldif$/;

my $queue = $entry->get_value('subeventtype');

my $md_file = "$path/$uid\_$seqno\_$queue\_metadata.ldif";

my $md;
if (-e $md_file) {
    $md = $entry->md;
} else {
    $queue = lc($entry->get_value('subeventtype'));
    $md_file = "$path/$uid\_$seqno\_$queue\_metadata.ldif";
    if (-e $md_file) {
        $md = $entry->md;
    } else {
        undef $md_file;
    }
}

my $completed = $entry->from_file =~ /completed/;
my $failed = $entry->from_file =~ /failed/;

if ($completed) {
    print $entry->get_value('seqno') . ": Completed\n";
} elsif ($failed) {
    print $entry->get_value('seqno') . ": Failed\n";
} else {
    print $entry->get_value('seqno') . " queued in queue: $queue\n";
}

if ($opts->{v} && $md) {
    # verbose..
    foreach my $attr ($md->attributes) {
        my $pattr;

        if ($attr =~ /^([\w+\_\-]+?)\_(\d\d)([\w+\_\-]+?)\_(status|lastruntime)$/) {
        #    $pattr = ucfirst($3);
        #    if ($4 eq "status") {
        #        $pattr .= " Status:";
        #    } elsif ($4 eq "lastruntime") {
        #        $pattr .= " Last Run Date/Time:";
        #    }
            if ($4 eq "lastruntime") {
                $pattr = "";
            } else {
                $pattr = "[$1] $3";
            }
        } else {
            $pattr = $attr;
        }
        my @pval = $md->get_value($attr);
        foreach my $val (@pval) {
            if ($val =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/) {
                $val = ("$1-$2-$3 $4:$5:$6");
            }
            printf ("%-35s  %s\n", substr($pattr, 0, 35), $val);
            print "\n" unless $pattr;
        }
    }
} 

if ($opts->{p}) {
    if ($opts->{f}) {
        $entry = $entry->final;
    }
    system("cat " . $entry->from_file);
}
