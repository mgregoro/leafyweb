#!/usr/bin/env perl

use lib($ENV{LEAFY_ROOT} . "/lib/perl");

use LeafyWeb::LeafyD;

my $ldip = new LeafyWeb::LeafyD;

foreach my $queue (@{$ldip->c->QUEUES}) {
    my @num;
    opendir(DIR, $ldip->c->LEAFYD_QUEUE_BASE . "/" . $queue) or die "Can't open queue $queue: $!\n";
    while (my $file = readdir(DIR)) {
        if ($file !~ /metadata/ && $file =~ /\.ldif$/) {
            push(@num, $file);
        } elsif ($file eq ".failed") {
            if (-d $ldip->c->LEAFYD_QUEUE_BASE . "/" . $queue . "/" . $file) {
                my @fnum;
                opendir(FAILED, $ldip->c->LEAFYD_QUEUE_BASE . "/" . $queue . "/" . $file) or die "Can't open failed: $!\n";
                while (my $failed = readdir(FAILED)) {
                    if ($failed !~ /metadata/ && $failed =~ /\.ldif$/) {
                        push (@fnum, $failed);
                    }
                }
                closedir(FAILED);
                printf("\n%20s:\t%6d\n\n", "$queue [fail]", scalar(@fnum));
            }
        }
    }
    closedir(DIR);

    printf("%20s:\t%6d\n", $queue, scalar(@num));
}
