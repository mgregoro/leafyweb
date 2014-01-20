#
# encapsulates one server instance
#

# this code changed forms like a million times.. pardon the ugly.

package LeafyWeb::Server::Instance;

use base qw/Class::Accessor LeafyWeb/;

__PACKAGE__->mk_accessors(qw/
    stateid server_name user site port modify_time state bind_ip 
/);

sub new {
    my ($class, $criteria) = @_;

    if (!ref($criteria)) {
        $criteria = {
            stateid         =>      $criteria,
        };
    }

    my $self = bless($criteria, $class);

    $self->{server_name} = $self->resolve_server_name($self->{server_name}) if exists($self->{server_name});

    my $instances = $self->list_instances($criteria);
    if ($instances && scalar(@$instances) == 1) {
        return bless ($instances->[0], $class);
    }

    $self->{bind_ip} = $self->{bind_ip} ? $self->{bind_ip} : $self->c->LEAFY_ADDR->[0];
    $self->{location} = $self->{location} ? $self->{location} : "_lfy_default";

    # must have a port range defined for leafy srvrz :D
    my $port_range = $self->c->LEAFY_PORT_RANGE;
    $port_range = '30000-40000' unless $port_range;

    my ($range_low, $range_high) = split(/-/, $port_range);

    my $dbh = $self->open_db;
    my $sth = $dbh->prepare('select port from state where bind_ip = ? AND port BETWEEN ? AND ?');
    $sth->execute($self->{bind_ip}, $range_low, $range_high);

    my @assigned_ports;
    while (my $ar = $sth->fetchrow_arrayref) {
        push (@assigned_ports, $$ar[0]);
    }

    foreach my $try_port ($range_low..$range_high) {      
        unless (_is_assigned($try_port, @assigned_ports)) {
            # we can put try / catch code here to make this thread-safe
            $dbh->do(qq/
                insert into state
                    (server_name, user, site, port, modify_time, state, bind_ip, location)
                values
                    (?, ?, ?, ?, ?, ?, ?, ?)
                /, {}, $self->{server_name}, $self->{user}, $self->{site}, $try_port, 
                        time, 'NEW', $self->{bind_ip}, $self->{location});
            $self->{port} = $try_port;
            last;
        }
    }

    $self->{stateid} = $dbh->func('last_insert_rowid');

    return $self;
}

sub identifier {
    my ($self) = @_;
    return $self->stateid;
}

*id = \&identifier;

sub list_instances {
    my ($self, $criteria) = @_;

    $criteria->{server_name} = $self->resolve_server_name($criteria->{server_name}) if exists($criteria->{server_name});

    my $sql;
    my @values;
    foreach my $k (qw/stateid server_name user site port modify_time state bind_ip location/) {
        next unless $self->{$k};
        if ($sql) {
            $sql .= " AND $k = ?";
        } else {
            $sql = "select * from state where $k = ?";
        }
        push(@values, $criteria->{$k});
    }

    # if we got nothing, we got nothing.
    return undef unless $sql;

    #print "SQL: $sql\n";
    #print "VALS: " . join(', ', @values) . "\n";

    my $dbh = $self->open_db;
    my $sth = $dbh->prepare($sql);
    my $records = $sth->execute(@values);

    my @instances;
    while (my $hr = $sth->fetchrow_hashref) {
        push(@instances, $hr);
    }

    return \@instances;
}

sub location {
    my ($self, $omit_leading_slash) = @_;
    my $location = $self->{location};
    if ($omit_leading_slash) {
        $location =~ s/^\///g;
    }
    return $location;
}

sub unique_filename {
    my ($self) = @_;
    return $self->server_name . "." . $self->stateid;
}

sub delete {
    my ($self) = @_;

    my $dbh = $self->open_db;
    $dbh->do('delete from state where stateid = ?', {}, $self->{stateid});
}

sub set_state {
    my ($self, $state) = @_;
    my $dbh = $self->open_db;
    $dbh->do(qq/
        update state set state = ? where stateid = ?
        /, {}, $state, $self->{stateid});
    $self->{state} = $state;
}

sub shared {
    my ($self) = @_;
    if ($self->location eq "_lfy_default" && $self->site eq "_shared") {
        return "global";
    } elsif ($self->location eq "_lfy_default") {
        return "site";
    } else {
        return undef;
    }
}
         
sub _is_assigned {
    my ($port, @ports) = @_;
    foreach my $p (@ports) {
        return 1 if $p == $port;
    }
    return undef;
}

1;
