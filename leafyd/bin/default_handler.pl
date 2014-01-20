#!/usr/local/bin/perl

use lib($ENV{LEAFY_ROOT} . "/lib/perl");

use LeafyWeb::LeafyD;
use LeafyWeb::LeafyD::Entry;
use LeafyWeb::LeafyD::HandlerRegistry;

# clean it up
use strict;
no strict qw/vars/;

# gotta have an ldip object
my $ldip = new LeafyWeb::LeafyD;

# are we caching bytecode?
my $cache_bytecode = $ldip->c->CACHE_BYTECODE;

# set to true to turn debugging output on
my $debug = 0;

my $file_name = $ARGV[0];

# make sure we have a file name
unless ($file_name) {
    if ($cache_bytecode) {
        return "FAILED:no file name specified!\n";
    } else {
        print "FAILED:no file name specified!\n";
        exit();
    }
}

# create the entry object for this piece of data.
my $entry;
# catch errors
eval {
    $entry = LeafyWeb::LeafyD::Entry->new($file_name);
};

if ($@) {
    if ($cache_bytecode) {
        return "FAILED:entry creation error $@\n";
    } else {
        print "FAILED:entry creation error $@\n";
        exit();
    }
}

# extract the queue name from the entry...
my $queue_name = $entry->queue_name;

# create the handler registry object for an event of this tyle
my $hr;
# catch errors
eval {
    $hr = LeafyWeb::LeafyD::HandlerRegistry->new($queue_name);
};

if ($@) {
    if ($cache_bytecode) {
        return "FAILED:handler registry error $@\n";
    } else {
        print "FAILED:handler registry error $@\n";
        exit();
    }
}

my $md = $entry->md;

set_md($md, processingStarted       =>      $entry->dim_now);
set_md($md, runCount                =>      $md->get_value('runCount') + 1);

my $handler_count = 0;
my $previously_passed = 0;

# write out our changes..
$md->save;

foreach my $handler ($hr->handlers_in_priority_order) {
    # skip handlers that already passed
    if ($md->get_value($queue_name . "_" . $handler->handler_name . "_" . "Status") =~ /^\s*PASSED/o) {
        #print $handler->handler_name . ": PASSED at " . $md->get_value($queue_name . $handler->handler_name . "LastRunTime") . ", skipping...\n";
        ++$previously_passed;
        next;
    }

    my ($status, $info);
    if ($cache_bytecode) {
        my $return = call_handler($handler->exec_path, $file_name);
        ($status, $info) = $return =~ /^([A-Z]+)\s*:\s*(.+)[\r\n]*$/o;
        chomp($info);
    } else {
        # IPC version!
        my $run;
        # run the program, get the output!
        open($run, '-|', $handler->exec_path . " " . $file_name);
        ($status, $info) = <$run> =~ /^([A-Z]+)\s*:\s*(.+)[\r\n]*$/o;
        chomp($info);
        close($run);
    }

    # refresh our entry and metadata.
    $entry = LeafyWeb::LeafyD::Entry->new($entry->seqno);
    $md = $entry->md;

    set_md($md, $queue_name . "_" . $handler->handler_name . "_Status"      =>          $status . " - " . $info);
    set_md($md, $queue_name . "_" . $handler->handler_name . "_LastRunTime" =>          $entry->dim_now);

    if ($status ne "PASSED") {
        my $requeued = 0;
        if ($status eq "FAILED") {
            $entry->error_log("problem running " . $handler->handler_name . ": $info");
            if ($cache_bytecode) {
                $md->save;
                return "FAILED:[" . $entry->get_value('seqno') . "] after $handler_count handler(s) run ($previously_passed previously passed) - " . $handler->handler_name . ": $info\n";
            } else {
                print "FAILED:[" . $entry->get_value('seqno') . "] after $handler_count handler(s) run ($previously_passed previously passed) - " . $handler->handler_name . ": $info\n";
            }
        } elsif ($status eq "QUEUED") {
            $entry->log("queueing " . $entry->get_value('seqno') . ": $info") if $debug;
            if ($cache_bytecode) {
                return "QUEUED:[" . $entry->get_value('seqno') . "] by " . $handler->handler_name . ": $info\n";
            } else {
                print "QUEUED:[" . $entry->get_value('seqno') . "] by " . $handler->handler_name . ": $info\n";
            }
        } elsif ($status eq "REQUEUED") {
            $entry->log($entry->get_value('seqno') . " was requeued into another queue by " . $handler->handler_name . ": $info");
            if ($cache_bytecode) {
                return "REQUEUED:[" . $entry->get_value('seqno') . "] entry was reqeueued by " . $handler->handler_name . ": $info\n";
            } else {
                print "REQUEUED:[" . $entry->get_value('seqno') . "] entry was reqeueued by " . $handler->handler_name . ": $info\n";
            }
            $requeued = 1;
        } else {
            $entry->error_log("bad output from " . $handler->handler_name . ": $info") if $debug;
            # make sure we mark it failed here
            set_md($md, $queue_name . "_" . $handler->handler_name . "_Status"      =>      'FAILED' . " - handler returned bad (or no) output.");

            if ($cache_bytecode) {
                $md->save;
                return "FAILED:[" . $entry->get_value('seqno') . "] illegal return string(s) from " . $handler->handler_name . ".\n";
            } else {
                print "FAILED:[" . $entry->get_value('seqno') . "] illegal return string(s) from " . $handler->handler_name . ".\n";
            }
        }

        # if its been requeued, don't write out the metadata, let the new queue handle it from here.
        unless ($requeued) {
            set_md($md, processingCompleted      =>      $entry->dim_now);
            $md->save;
        }
        exit();
    }
    # keep track of how much work we did
    ++$handler_count;

    # save on every pass.
    $md->save;
}

# get the newest metadata (again)
$md = $entry->md;

set_md($md, processingCompleted      =>      $entry->dim_now);
$md->save;

if ($cache_bytecode) {
    return "PASSED:[" . $entry->get_value('seqno') . "] $handler_count handlers successfuly run!\n";
} else {
    print "PASSED:[" . $entry->get_value('seqno') . "] $handler_count handlers successfuly run!\n";
}

sub set_md {
    my ($md, %attribs) = @_;
    foreach my $key (keys %attribs) {
        if ($md->exists($key)) {
            $md->replace($key       =>      $attribs{$key});
        } else {
            $md->add($key           =>      $attribs{$key});
        }
    }
}
