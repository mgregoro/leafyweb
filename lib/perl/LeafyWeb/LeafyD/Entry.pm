#
# One LeafyWeb::LeafyD::Entry object
#

package LeafyWeb::LeafyD::Entry;

use Net::LDAP::LDIF;
use Carp;

our @ISA = qw/Net::LDAP::Entry LeafyWeb::LeafyD/;

# a nice new constructor (to automagically pull from LDIF)!
sub new {
    my ($class, $file_name, $directory) = @_;

    if (ref($class) eq "LeafyWeb::LeafyD::Entry") {
        # we're trying a clone.. just set the class to itself and rock-rock on
        $class = ref($class);
    }

    my $self = bless(Net::LDAP::Entry->new(), $class);

    $directory = $self->c->LEAFYD_QUEUE_BASE unless $directory;

    if ($file_name =~ /^[A-Z0-9]+$/) {
        # this is a sequence number...
        $file_name = $self->_file_name_from_seqno($file_name, $directory);
    }

    if (-e $file_name) {
        my $fh;
        open($fh, '<', $file_name);
        my $ldif = Net::LDAP::LDIF->new($fh);
        $self = $ldif->read_entry;
        close($fh);

        # we got from a file, lets bless this into our classy class
        if ($self) {
            bless($self, $class);
        } else {
            warn "Can't read LDIF file $file_name! $!\n";
            return undef;
        }
        $self->add(LeafyDfromFile     =>      $file_name);
    } else {
        # if $file_name is defined, but doesn't exist.. rock out w/ our cox out.
        if ($file_name) {
            warn "File $file_name doesn't exist!";
            return undef;
        }
    }      

    return $self;
} 

# write a so-far-nameless entry to the queue
sub write_to_queue {
    my ($self) = @_;

    # unless we've already done this..
    unless ($self->exists('uniqueid')) {
        # figure out who our unique identifier is
        foreach my $uid (@{$self->c->UNIQUE_IDS}) {
            if ($self->exists($uid)) {
                $self->add(uniqueid     =>      $self->get_value($uid));
            }
        }
    }

    # this never should happen (except in few cases) but just to be safe.
    if ($self->exists('LeafyDfromFile')) {
        $self->delete('LeafyDfromFile');
    }

    my $file_name = $self->get_file_name;
    my $queue_name = $self->queue_name;

    # make the queue if it doesn't exist!
    $self->mkqueue($queue_name);

    my $full_file_name = $self->c->LEAFYD_QUEUE_BASE . "/$queue_name/$file_name";

    my $ldif = Net::LDAP::LDIF->new($full_file_name, 'w');

    # keep track of it here...
    $self->udb_add($self->uid, $self->seqno, {
            queue       =>      lc($queue_name),
            file        =>      $full_file_name,
        },
        1 # don't save!
    );

    if ($ldif) {
        $ldif->write_entry($self);
        chmod(oct('0660'), $full_file_name);
    } else {
        $self->error_log("FATAL: Can't write to queue: $queue_name/$file_name $!");
        croak "FATAL: Can't write to queue: $queue_name/$file_name $!";
    }

    # since we weren't returning anything, let's be useful here, returning both a true value
    # and a string i need in LeafyWeb::LeafyD::Entry::fork_to();
    return $full_file_name;
}

# add or replace.. adds if it doesn't exist.. replaces otherwise (does not save)
sub add_or_replace {
    my ($self, %attribs) = @_;
    foreach my $key (keys %attribs) {
        if ($self->exists($key)) {
            $self->replace($key     =>      $attribs{$key});
        } else {
            $self->add($key         =>      $attribs{$key});
        }
    }
}

# quickly add attributes to the md with saving.
# note, dont use this if you have your own $md object
# that you plan on save()ing.
sub set_md {
    my ($self, %attribs) = @_;
    my $md = $self->md;
    foreach my $key (keys %attribs) {
        if ($md->exists($key)) {
            $md->replace($key       =>      $attribs{$key});
        } else {
            $md->add($key           =>      $attribs{$key});
        }
    }
    $md->save;
}

# same as set_md, except rather than replace, it always adds.
sub add_md {
    my ($self, %attribs) = @_;
    my $md = $self->md;
    foreach my $key (keys %attribs) {
        $md->add($key           =>      $attribs{$key});
    }
    $md->save;
}

# quickly get attributes from the md
sub get_md {
    my ($self, $attrib) = @_;
    my $md = $self->md;
    return $md->get_value($attrib);
}

# get metadata about this entry.. as another entry
sub md {
    my ($self) = @_;

    # this needs to be able to be mixed case.. for TO_LDAP specifically
    my $queue_name = $self->get_value('subeventtype');

    # if it's not a destination queue, make it lower case.
    $queue_name = $queue_name =~ /^TO_/o ? $queue_name : lc($queue_name);

    $self->mkqueue($queue_name);

    my $file_name = $self->get_file_start . "_" . $queue_name . "_metadata.ldif";

    # figure out where this metadata file is
    my $md_from_file;
    if (-e $self->c->LEAFYD_QUEUE_BASE . "/$queue_name/$file_name") {
        # where it's supposed to be...
        $md_from_file = $self->c->LEAFYD_QUEUE_BASE . "/$queue_name/$file_name"
    } else {
        # where it is if it's not in a proper queue directory, ie ".failed"
        $md_from_file = $self->from_file_path . "/$file_name";
    }

    my $ldif = Net::LDAP::LDIF->new($md_from_file);

    my $entry;
    if ($ldif) {
        $entry = $ldif->read_entry;
    } else {
        $entry = Net::LDAP::Entry->new();
    }

    # keep note of where we got this data for easy saving...
    $entry->add(LeafyDfromFile    =>      $md_from_file);

    # bless the entry object as LeafyWeb::LeafyD::Entry and return
    return bless($entry, ref($self));
}

sub from_file_path {
    my ($self) = @_;
    my ($path) = $self->from_file =~ /^(.+)\/[A-Za-z0-9\_\.]+$/;
    return $path ? $path : ".";
}

# save an instantiated entry object.
sub save {
    my ($self) = @_;
    my $from_file = $self->get_value('LeafyDfromFile');
    $self->delete('LeafyDfromFile');
    
    my $ldif = Net::LDAP::LDIF->new($from_file, 'w');

    if ($ldif) {
        # write out the entry
        $ldif->write_entry($self);
    } else {
        $self->error_log("Cannot write to $from_file: $!");
        croak("FATAL:Can't save to $from_file: $!\n");
    }
}

# pull it out of the index!
sub _file_name_from_seqno {
    my ($self, $seqno, $directory) = @_;

    my $file_name = $self->seqno_db($seqno)->{file};
    #print "returning $file_name for $seqno\n";

    return $file_name;
}

# recursive seqno to file_name resolvertron
sub _file_name_from_seqno_no_index {
    my ($self, $seqno, $directory) = @_;

    # scope the file_name var
    my $file_name;

    # prime the recursive search with a nice directory
    unless ($directory) {
        $directory = $self->c->LEAFYD_QUEUE_BASE;
    }

    # gotta scope the file handle since this is a recursive function!
    my $dir;

    # Open the damn directory.. or .. get outta dodge.
    opendir($dir, $directory) or 
        croak "Can't open dir: $directory $!";

    while (my $file = readdir($dir)) {
        # ignore . and .. 
        next if $file =~ /^\.+/;

        # recurse into subdirectories
        if (-d "$directory/$file") {
            # stop when we find a file that matches.. no point in continuing
            if ($file_name = $self->_file_name_from_seqno($seqno, "$directory/$file")) {
                last;
            }
        }

        if ($file =~ /_$seqno\./) {
            # stop the madness!
            $file_name = "$directory/$file";
            last;
        }

    }
    closedir($dir);

    # will be undef if not set by the while search
    return $file_name;
}

sub failed {
    my ($self) = @_;

    my $current_queue = $self->get_value('subeventtype');

    # unless it's a destination queue, lowercase it!
    unless ($current_queue =~ /^TO_/) {
        $current_queue = lc($current_queue);
    }

    # the new queue can be whatever case you want because I know you'll be good and
    # realize that queue names are case sensitive.

    my $md = $self->md;
    my $old_file = $self->get_value('LeafyDfromFile');
    my $old_md_file = $md->get_value('LeafyDfromFile');

    # make the failed queue (possibly)
    $self->mkqueue("$current_queue/.failed");

    # construct the new file name
    my $new_md_file = $self->c->LEAFYD_QUEUE_BASE . "/$current_queue/.failed/" . $self->get_file_start .
    "_$current_queue\_metadata.ldif";

    my $new_file = $self->c->LEAFYD_QUEUE_BASE . "/$current_queue/.failed/" . $self->get_file_name;

    # change the file name in the entry's LeafyDfromFile attribute
    $self->replace(LeafyDfromFile     =>      $new_file);

    # change the file name in the md's LeafyDfromFile attribute
    $md->replace(LeafyDfromFile       =>      $new_md_file);

    # add additional data to the metadata file regarding this requeueing
    $md->add(reQueued               =>      "$current_queue <=> $current_queue: FAILED");

    # mark this failed!
    $md->add(failedInQueue          =>      $current_queue);
    $md->add(recordFailed           =>      'TRUE');

    # keep track of the original queue (only on the first requeueing)
    unless ($md->exists('originalQueue')) {
        $md->add(originalQueue      =>      $current_queue);
    }

    #$_->save for ($self, $md);

    # this looks better
    # save the new entry
    $self->save;

    # save the new md entry
    $md->save;

    # remove old files.
    unlink($old_file, $old_md_file);

    # keep track of this little transaction here..
    $self->udb_update($self->uid, $self->seqno, {
            queue       =>      $current_queue,
            file        =>      $new_file,
        },
        1 # don't save!
    );
}

sub requeue {
    my ($self, $queue) = @_;
    
    my $current_queue = $self->get_value('subeventtype');
    
    if ($current_queue =~ /^TO_/i) {
        croak "Can't requeue something in a destination queue unless sloppy requeueing is set to true in leafyd.yaml." unless $self->c->SLOPPY_REQUEUEING;
    } else {
        # lowercase unless it's a destination queue!
        $current_queue = lc($current_queue);
    } 
        
    # the new queue can be whatever case you want because I know you'll be good and
    # realize that queue names are case sensitive.

    # make sure the target queue exists
    unless (-d $self->c->LEAFYD_QUEUE_BASE . "/$queue") {
        croak "Target queue does not exist!";
    }

    # this is the absolute way to make SURE that the item is not in the destination queue..
    if (!-e $self->c->LEAFYD_QUEUE_BASE . "/$queue/" . $self->get_file_name) {
        my $md = $self->md;
        my $old_file = $self->get_value('LeafyDfromFile');
        my $old_md_file = $md->get_value('LeafyDfromFile');

        # construct the new file name
        my $new_md_file = $self->c->LEAFYD_QUEUE_BASE . "/$queue/" . $self->get_file_start .
            "_$queue\_metadata.ldif";
 
        my $new_file = $self->c->LEAFYD_QUEUE_BASE . "/$queue/" . $self->get_file_name;
    
        # change this entry to reflect the new event type
        $self->replace(subeventtype     =>      $queue);
    
        # change the file name in the entry's LeafyDfromFile attribute
        $self->replace(LeafyDfromFile     =>      $new_file);

        # change the file name in the md's LeafyDfromFile attribute
        $md->replace(LeafyDfromFile       =>      $new_md_file);

        # add additional data to the metadata file regarding this requeueing
        $md->add(reQueued               =>      "$current_queue <=> $queue");

        # keep track of the original queue (only on the first requeueing)
        unless ($md->exists('originalQueue')) {
            $md->add(originalQueue      =>      $current_queue);
        }

        #$_->save for ($self, $md);

        # this looks better
        # save the new entry
        $self->save;

        # save the new md entry
        $md->save;

        # remove old files.
        unlink($old_file, $old_md_file);

        # keep track of this little transaction here..
        $self->udb_update($self->uid, $self->seqno, {
                queue       =>      $queue,
                file        =>      $new_file,
            },
            1 # don't save!
        );
    } else {
        warn $self->seqno . " already in queue $queue!";
    }
}

sub fork_to {
    my ($self, $queue) = @_;
    my $fork = $self->clone;

    # fork this one out...
    $fork->add_or_replace(seqno         =>      $self->internal_seqno);
    $fork->add_or_replace(subeventtype  =>      $queue);

    # write to queue and update the fromFile!
    $fork->add_or_replace(LeafyDfromFile  =>      $fork->write_to_queue);

    # get the metadata files..
    $self->add_md(forkedTo              =>      $fork->seqno);
    $fork->set_md(forkedFrom            =>      $self->seqno);

    return $fork;
}

sub dequeue {
    my ($self) = @_;
    my $md = $self->md;

    unlink($self->from_file, $md->from_file);

    if (-e $self->get_file_dir . $self->get_file_start . "_FINAL.ldif") {
        unlink ($self->get_file_dir . $self->get_file_start . "_FINAL.ldif");
    }

    if (-e $self->get_file_dir . $self->get_file_start . "_ROLLBACK.ldif") {
        unlink($self->get_file_dir . $self->get_file_start . "_ROLLBACK.ldif");
    }

    # delete this transaction..
    $self->udb_delete($self->uid, $self->seqno, 1);
}


# copies all the data to it's respective completed dir and dequeues the entry!
sub completed {
    my ($self) = @_;

    my $entry = $self->clone;

    # get the metadata
    my $md = $self->md->clone;

    # get the uid and event type
    my $uid = $self->uid;
    my $event_type = lc($md->get_value('originalQueue'));
    $event_type = $entry->queue_name unless $event_type;

    # build the directory hierarchy
    my $completed_dir = $entry->mkcompleted($event_type, $uid);

    my $completed_file = $completed_dir . "/" . $entry->get_file_start . "_FINAL.ldif";
    my $completed_md_file = $completed_dir . "/" . $entry->get_file_start . "_$event_type\_metadata.ldif";

    $entry->replace(LeafyDfromFile        =>      $completed_file);
    $md->replace(   LeafyDfromFile        =>      $completed_md_file);

    # write the file to the completed dir
    $entry->save;

    # write the md to the completed dir
    $md->save;

    # if we don't have a "regular" in our completed dir, just use the final
    unless (-e $completed_dir . "/" . $entry->get_file_name) {
        $entry->replace(LeafyDfromFile    =>      $completed_dir . "/" . $entry->get_file_name);
        $entry->replace(subeventtype    =>      $event_type);
        $entry->save;
    }

    # these aren't clones now.  work with the real deals!
    $md = $self->md;

    # get rid of the old stuff.
    unlink($self->from_file, $md->from_file);

    # keep track of this little transaction here..
    $self->udb_update($self->uid, $self->seqno, {
            queue       =>      "COMPLETED",
            file        =>      $completed_dir . "/" . $entry->get_file_name,
        },
        1 # don't save!
    );
}

sub uniqueid {
    my ($self) = @_;
    return $self->uid;
}

sub uid {
    my ($self) = @_;
    if ($self->from_file =~ /^(.+)_([A-Z0-9]+)_(.+)_metadata/o) {
        # if we're metadata, return the sequence number from the file name
        return $1;
    } else {
        # if we're not, just return the sequence number.
        return $self->get_value('uniqueid');
    }
}

sub seqno {
    my ($self) = @_;
    if ($self->from_file =~ /^(.+)_([A-Z0-9]+)_(.+)_metadata/o) {
        # if we're metadata, return the sequence number from the file name
        return $2;
    } else {
        # if we're not, just return the sequence number.
        return $self->get_value('seqno');
    }
}

# case sensitive
sub has_value {
    my ($self, $attr, $value, $case_insensitive) = @_;
    unless ($value) {
        croak "Illegal use of has_value() must specify and attribute and a value!";
    }

    my @values = $self->get_value($attr);

    if ($case_insensitive) {
        foreach my $v (@values) {
            return 1 if lc($v) eq lc($value);
        }
    } else {
        foreach my $v (@values) {
            return 1 if $v eq $value;
        }
    }

    return undef;
}

sub from_file {
    my ($self) = @_;
    return $self->get_value('LeafyDfromFile');
}

# cos some people like to be wordy
sub metadata {
    $self->md(@_);
}

sub get_file_dir {
    my ($self) = @_;
    my @path = split(/\//, $self->from_file);
    return join('/', @path[0..($#path - 1)], undef);
} 

sub get_file_name {
    my ($self) = @_;
    return $self->get_file_start . ".ldif";
}

sub get_file_start {
    my ($self) = @_;
    return sprintf("%s_%s", lc($self->get_value('uniqueid')), $self->get_value('seqno'));
}

sub queue_name {
    my ($self) = @_;
    return lc($self->get_value('subeventtype'));
}

1;
