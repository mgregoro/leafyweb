# A base class for the masses.

package LeafyWeb;

use LeafyWeb::Config;
use Carp qw/croak/;

my $VERSION = '0.08';

# wicked easy constructor
sub new {
    my ($class, %attribs) = @_;
    return bless(\%attribs, $class);
}

sub c {
    my ($self) = @_;
    unless ($self->{config_object}) {
        $self->{config_object} = LeafyWeb::Config->new(ConfigFile       =>      $ENV{LEAFY_ROOT} . "/etc/leafyweb.yaml");
    }
    return $self->{config_object};
}

sub open_db {
    my ($self) = @_;
    unless ($self->{dbh}) {
        if (-e $self->c->SQLITE_DB_FILE) {
            $self->{dbh} = DBI->connect('DBI:SQLite:' . $self->c->SQLITE_DB_FILE);
        } else {
            system("sqlite3 " . $self->c->SQLITE_DB_FILE . " < $ENV{LEAFY_ROOT}/etc/index_tables.sql 2>&1 > /dev/null");
            $self->{dbh} = DBI->connect('DBI:SQLite:' . $self->c->SQLITE_DB_FILE);
            unless ($self->{dbh}) {
                croak "No mas: $!\n";
            }
        }
    }
    return $self->{dbh};
}

sub resolve_server_name {
    my ($self, $server_name) = @_;
    if (exists $self->c->INSTALLED_LEAFY_SERVERS->{$server_name}) {
        return $self->c->INSTALLED_LEAFY_SERVERS->{$server_name};
    }
    return undef;
}

sub reset_deployed_configs {
    my ($self, $site) = @_;
    my $dbh = $self->open_db;

    $dbh->do(qq/
        delete from deployed_config where site = ?
    /, {}, $site);
}

sub count_deployed_configs {
    my ($self, $config_file) = @_;
    my $dbh = $self->open_db;
    my $sth = $dbh->prepare(qq/
        select count(deployed_configid) from deployed_config where config_file = ?
        /
    );

    $sth->execute($config_file);

    my $ar = $sth->fetchrow_arrayref;
    return $$ar[0];
}

sub remove_deployed_config {
    my ($self, $site, $config_file) = @_;
    my $dbh = $self->open_db;

    $dbh->do(qq/
        delete from deployed_config where site = ? AND config_file = ?
    /, {}, $site, $config_file);
}

sub list_deployed_configs {
    my ($self, $site) = @_;
    my $dbh = $self->open_db;
    my $sth = $dbh->prepare(qq/
        select config_file from deployed_config where site = ?
    /);
    $sth->execute($site);

    my @configs;
    while (my $ar = $sth->fetchrow_arrayref) {
        push(@configs, $$ar[0]);
    }
    return \@configs;
}

sub remove_site_config {
    my ($self, $site) = @_;
    my $dbh = $self->open_db;

    $dbh->do(qq/
        delete from site_config where site = ? 
    /, {}, $site);
}

sub list_configed_sites {
    my ($self) = @_;
    my $dbh = $self->open_db;
    my $sth = $dbh->prepare(qq/
        select site from site_config
        /
    );
    $sth->execute;
    my @sites;
    while (my $ar = $sth->fetchrow_arrayref) {
        push(@sites, $$ar[0]);
    }
    return (@sites);
}

sub deployed_config {
    my ($self, $site, $file) = @_;
    my $dbh = $self->open_db;
    $dbh->do(qq/
        insert into deployed_config (site, config_file, deploy_time) VALUES (?, ?, ?)
    /, {}, $site, $file, time);
}

sub update_deploy_timestamp {
    my ($self, $id) = @_;
    my $dbh = $self->open_db;
    $dbh->do(qq/
        update deployed_config set deploy_time = ? where deployed_configid = ?
    /, {}, time, $id);
}

sub parse_uri {
    my ($self, $uri) = @_;
    if ($uri =~ /^http[s]?:\/\/([^\/]+)(.*?)\/*$/) {
        return ($1, $2);
    } elsif ("http://$uri" =~ /^http[s]?:\/\/([^\/]+)(.*?)\/*$/) {
        return ($1, $2);
    }
    return undef;
}

# copied and pasted. tsk tsk.
sub find_recursive {
    my ($self, $path) = @_;

    # open directory file handle..
    my $dfh;
    opendir($dfh, $path);

    while (my $file = readdir($dfh)) {
        next if $file =~ /^\.+$/;
        my $file_name_full = $path . "/" . $file;
        my ($file_name_rel) = $file_name_full =~ /^\.\/(.+)$/;
        my $type = -d $file_name_full ? "directory" : "file";

        push (@{$self->{target_files}}, {
            file_name       =>          $file,
            file_name_full  =>          $file_name_full,
            file_name_rel   =>          $file_name_rel
        });
        if ($type eq "directory") {
            $self->find_recursive($file_name_full);
        }
    }
}

sub is_config_deployed {
    my ($self, $site, $file) = @_;
    my $dbh = $self->open_db;

    my $sth = $dbh->prepare(qq/
        select deployed_configid from deployed_config where site = ? AND config_file = ?
        /);
    $sth->execute($site, $file);

    my $ar = $sth->fetchrow_arrayref;

    return $$ar[0];
}

sub installed_servers {
    my ($self) = @_;
    my %servers;
    foreach my $s_name (keys %{$self->c->INSTALLED_LEAFY_SERVERS}) {
        $servers{$self->c->INSTALLED_LEAFY_SERVERS->{$s_name}}++;
    }

    return keys %servers;
}


sub lfy_version {
    my ($self) = @_;
    return $VERSION;
}

1;
