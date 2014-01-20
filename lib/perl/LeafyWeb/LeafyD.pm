#
# LeafyWeb::LeafyD.pm
# the core of the Leafy Daemon
#

package LeafyWeb::LeafyD;
use LeafyWeb;
use LeafyWeb::LeafyD::Entry;
use YAML::Syck;
use DB_File;
use FreezeThaw qw(freeze thaw);
use DBI;

# others..
use Carp;

our @ISA = qw/LeafyWeb/;

# udb looks like
# uid => { seqno => { key => val }, seqno => { key => val }, }

# sdb looks like
# seqno => { key => val }, seqno => { key => val }

# qdb looks like udb.
# the queue db stuff will be too slow.  don't use it.  It will have to thaw() a huge data structure out
# on every lookup.  this is weak, and im not caching thaw()ed content... well maybe i will. no i won't.

sub uid_db {
    my ($self, $uid, $seqno) = @_;
    my $dbh = $self->open_db;
    my ($sth, $hr);
    if ($seqno) {
        $sth = $dbh->prepare("select uid, seqno, queue, file, timestamp from leafyd_index where seqno = ?");
        $self->stubborn_execute($sth, $seqno);
        $hr = $sth->fetchrow_hashref;
    } else {
        $sth = $dbh->prepare("select uid, seqno, queue, file, timestamp from leafyd_index where uid = ?");
        $self->stubborn_execute($sth, $uid);
        while (my $shr = $sth->fetchrow_hashref) {
            $hr->{$shr->{seqno}} = {
                file        =>  $shr->{file},
                queue       =>  $shr->{queue},
                timestamp   =>  $shr->{timestamp},
            };
        }
    }
    return $hr;
}

sub udb_delete {
    my ($self, $uid, $seqno, $no_save) = @_;
    my $dbh = $self->open_db;
    my $sth = $dbh->prepare("delete from leafyd_index where seqno = ?");
    $self->stubborn_execute($sth, $seqno);
}

# extract structure, modify structure, store structure.
sub udb_add {
    my ($self, $uid, $seqno, $substruct, $no_save) = @_;
    if ($self->udb_present($uid, $seqno)) {
        return $self->udb_update($uid, $seqno, $substruct, $no_save);
    }

    my $dbh = $self->open_db;
    my $sth = $dbh->prepare("insert into leafyd_index (uid, seqno, queue, file, timestamp) VALUES (?, ?, ?, ?, ?)");
    $self->stubborn_execute($sth, $uid, $seqno, $substruct->{queue}, $substruct->{file}, time());
}

# checks to see if a seqno is present under a uid
sub udb_present {
    my ($self, $uid, $seqno) = @_;

    if ($self->uid_db($uid, $seqno)) {
        return 1;
    }

    return undef;
}

# unique id database update (by seqno)
sub udb_update {
    my ($self, $uid, $seqno, $substruct, $no_save) = @_;

    my $dbh = $self->open_db;
    my $sth = $dbh->prepare("update leafyd_index set queue = ?, file = ?, timestamp = ? where seqno = ?");
    $self->stubborn_execute($sth, $substruct->{queue}, $substruct->{file}, time(), $seqno);
}

sub queue_db {
    my ($self) = @_;
    unless ($self->{queue_db}) {
        my %hash;
        my $db = tie(%hash, 'DB_File', $self->c->QUEUE_INDEX_FILE, O_CREAT|O_RDWR, 0600, $DB_HASH)
            or die "cannot open " . $self->c->QUEUE_INDEX_FILE . ": $!\n";
        $db->filter_store_value(sub{ $_ = freeze($_) });
        $db->filter_fetch_value(sub{ ($_) = thaw($_) });
        $self->{queue_db} = \%hash;
    }
    return $self->{queue_db};
}

sub seqno_db {
    my ($self, $seqno) = @_;
    return $self->uid_db(undef, $seqno);
}

sub save_seqno_db {
    return;
}

sub save_queue_db {
    return;
}

sub save_uid_db {
    return;
}

# returns the full path
sub mkcompleted {
    my ($self, $event_type, $unique_id) = @_;
    my $complete_base = $self->c->LEAFYD_COMPLETED_BASE;
    my ($year, $month, $day) = $self->ymd;
    if (-d "$complete_base/$year/$month/$day/$event_type") {
        mkdir("$complete_base/$year/$month/$day/$event_type/$unique_id");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type/$unique_id")
    } elsif (-d "$complete_base/$year/$month/$day") {
        mkdir("$complete_base/$year/$month/$day/$event_type");
        mkdir("$complete_base/$year/$month/$day/$event_type/$unique_id");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type/$unique_id");
    } elsif (-d "$complete_base/$year/$month") {
        mkdir("$complete_base/$year/$month/$day");
        mkdir("$complete_base/$year/$month/$day/$event_type");
        mkdir("$complete_base/$year/$month/$day/$event_type/$unique_id");
        chmod(oct('2775'), "$complete_base/$year/$month/$day");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type/$unique_id");
    } elsif (-d "$complete_base/$year") {
        mkdir("$complete_base/$year/$month");
        mkdir("$complete_base/$year/$month/$day");
        mkdir("$complete_base/$year/$month/$day/$event_type");
        mkdir("$complete_base/$year/$month/$day/$event_type/$unique_id");
        chmod(oct('2775'), "$complete_base/$year/$month");
        chmod(oct('2775'), "$complete_base/$year/$month/$day");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type/$unique_id");
    } elsif (-d "$complete_base") {
        mkdir("$complete_base/$year");
        mkdir("$complete_base/$year/$month");
        mkdir("$complete_base/$year/$month/$day");
        mkdir("$complete_base/$year/$month/$day/$event_type");
        mkdir("$complete_base/$year/$month/$day/$event_type/$unique_id");
        chmod(oct('2775'), "$complete_base/$year");
        chmod(oct('2775'), "$complete_base/$year/$month");
        chmod(oct('2775'), "$complete_base/$year/$month/$day");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type/$unique_id");
    } else {
        mkdir("$complete_base");
        mkdir("$complete_base/$year");
        mkdir("$complete_base/$year/$month");
        mkdir("$complete_base/$year/$month/$day");
        mkdir("$complete_base/$year/$month/$day/$event_type");
        mkdir("$complete_base/$year/$month/$day/$event_type/$unique_id");
        chmod(oct('2775'), "$complete_base");
        chmod(oct('2775'), "$complete_base/$year");
        chmod(oct('2775'), "$complete_base/$year/$month");
        chmod(oct('2775'), "$complete_base/$year/$month/$day");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type");
        chmod(oct('2775'), "$complete_base/$year/$month/$day/$event_type/$unique_id");
    }
    return "$complete_base/$year/$month/$day/$event_type/$unique_id";
}

sub mkqueue {
    my ($self, $event_type) = @_;
    my $queue_base = $self->c->LEAFYD_QUEUE_BASE;
    unless (-d "$queue_base/$event_type") {
        mkdir("$queue_base/$event_type");
    }
}

sub ymd {
    my ($self) = @_;
    my @time = localtime;

    # return year, month, day :)
    return ($time[5] + 1900, sprintf('%02d', $time[4] + 1), sprintf('%02d', $time[3]));
}

sub dim_now {
    my $self = shift;
    my @time = localtime(time);
    return sprintf('%d%02d%02d%02d%02d%02d', $time[5] + 1900, $time[4] + 1, $time[3], $time[2], $time[1], $time[0]);
}

sub error_log {
    my ($self, $message) = @_;
    $self->log('leafyd_error.log', $message);
}

sub log {
    my ($self, $file, $message) = @_;

    # allow a 2 argument version and specify a default file
    unless ($message) {
        $message = $file;
        $file = "leafyd.log";
    }

    open(LOG, '>>', $self->c->LEAFYD_LOG_BASE . "/$file");
    print LOG "[ " . $self->dim_now . " ] " . $message . "\n";
    close(LOG);
}

# recursively find all entries in the queue (exclude metadata)
sub all_in_queue {
    my ($self, $directory) = @_;

    # scope the entries
    my (@entries, $dir);

    # prime the recursive search with a nice directory
    unless ($directory) {
        $directory = $self->c->LEAFYD_QUEUE_BASE;
    }

    # Open the damn directory.. or .. get outta dodge.
    # damn. had to scope that.
    opendir($dir, $directory) or 
        croak "Can't open dir: $directory $!";

    while (my $file = readdir($dir)) {
        # ignore . and .. and ... and .... and ................. ... .. . . . and .svn ;)
        next if $file =~ /^\.+/o;

        # recurse into subdirectories
        if (-d "$directory/$file") {
            push(@entries, $self->all_in_queue("$directory/$file"));
        } else {
            # skip ones that are metadata... changed \d to \w to accomodate internal sequence numbers..
            next if $file !~ /^(.+)_([A-Z0-9]+)\.ldif$/;
            # load up on entries ;)
            push(@entries, LeafyWeb::LeafyD::Entry->new("$directory/$file"));
        }
    }
    closedir($dir);

    # will be undef if not set by the while search
    return @entries;
}


sub rebuild_indexes {
    my ($self) = @_;

    # this order is better.
    $self->build_index($self->c->LEAFYD_COMPLETED_BASE);
    $self->build_index($self->c->LEAFYD_QUEUE_BASE);
}

# you MUST call $self->save_uid_db and $self->save_seqno_db after calling build_index.  rebuild_indexes does it for you!
sub build_index {
    my ($self, $directory) = @_;

    my $dir;

    unless ($directory) {
        $directory = $self->c->LEAFYD_QUEUE_BASE;
    }

    # Open the damn directory.. or .. get outta dodge.
    # damn. had to scope that.
    opendir($dir, $directory) or
        croak "Can't open dir: $directory $!";

    while (my $file = readdir($dir)) {
        # ignore . and .. and ... and .... and ................. ... .. . . . and .svn ;)
        next if $file =~ /^\.+/o;

        # recurse into subdirectories
        if (-d "$directory/$file") {
            $self->build_index("$directory/$file");
        } else {
            # skip ones that are metadata... changed \d to \w to accomodate internal sequence numbers..
            next if $file !~ /^(.+?)_([A-Z0-9]+)\.ldif$/o;

            # get the sequence number from the file name
            my $fn_seqno = $2;

            # skip ROLLBACK, FINAL, and metadata files..
            next if $file =~ /(?:ROLLBACK|FINAL|metadata)/o;

            # build the index...
            my $entry = LeafyWeb::LeafyD::Entry->new("$directory/$file");

            my $queue = lc($entry->queue_name);
            if ($entry->from_file =~ /completed/) {
                $queue = "COMPLETED";
            }


            print "Processing " . $entry->seqno . " ($fn_seqno - $file)\n";

            unless ($entry) {
                print "\tERROR creating LeafyWeb::LeafyD::Entry object from $directory/$file $2!\n";
                next;
            }
            # this now handles it all.. all the info for both indices is here.
            $self->udb_add($entry->uid, $entry->seqno, {
                    queue       =>      $queue,
                    file        =>      $entry->from_file,
                },
                1 # don't save!
            );
            print "\tUnique ID index created!\n";
            print "\n";
        }
    }

    closedir($dir);
    return 1;
}

sub s {
    my ($self) = @_;
    if (-e "$ENV{LEAFYD_ROOT}/.leafyd_status.yaml") {
        $self->{status_structure} = LoadFile("$ENV{LEAFYD_ROOT}/.leafyd_status.yaml");
    } else {
        # populates the status object
        $self->init_status();
    }
    # return the status object
    return $self->{status_structure};
}

# just run s().
sub status {
    $_[0]->s;
}

sub init_status {
    my ($self) = @_;

    # initialization directly accesses the data structure..
    $self->{status_structure}->{internal_seqno} = "LEAFYD000000000001";
    $self->{status_structure}->{records_processed} = "0";

    $self->save_status;
}

sub save_status {
    my ($self) = @_;
    DumpFile("$ENV{LEAFYD_ROOT}/.leafyd_status.yaml", $self->{status_structure});
}

sub set_status {
    my ($self, $key, $value) = @_;
    $self->s->{$key} = $value;
    $self->save_status;
}

sub get_status {
    my ($self, $key) = @_;
    return $self->s->{$key};
}

sub internal_seqno {
    my ($self) = @_;

    # get the current sequence number..
    my $cur_seqno = $self->get_status("internal_seqno");
    my ($number) = $cur_seqno =~ /^LEAFYD(\d+)$/;
    # set the next sequence number immediately.
    $number += 1;
    $self->set_status("internal_seqno", "LEAFYD" . sprintf("%012d", $number));

    return $cur_seqno;
}

sub stubborn_execute {
    my ($self, $sth, @args) = @_;
    for (my $i = 0; $i < 1000; $i++) {
        eval {
            $sth->execute(@args);
        };
        $i = 1000 unless $@;
    }
    return $sth;
}

1;
