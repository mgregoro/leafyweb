package LeafyWeb::PortDoler;

use base qw/LeafyWeb/;

sub dole_port {
    my ($self, $host) = @_;
    my $dbh = $self->open_db;

    $host = $host ? $host : 'default';

    # must have a port range defined for leafy srvrz :D
    my $port_range = $self->c->LEAFY_PORT_RANGE;
    $port_range = '30000-40000' unless $port_range;

    my ($range_low, $range_high) = split(/-/, $port_range);

    my $sth = $dbh->prepare('select port from server_port where host = ? AND port BETWEEN ? AND ?');
    $sth->execute($host, $range_low, $range_high);

    my @assigned_ports;
    while (my $ar = $sth->fetchrow_arrayref) {
        push (@assigned_ports, $$ar[0]);
    }

    foreach my $try_port ($range_low..$range_high) {
        unless (_is_assigned($try_port, @assigned_ports)) {
            # we can put try / catch code here to make this thread-safe
            $dbh->do('insert into server_port (port, host, timestamp) VALUES (?, ?, ?)', undef, $try_port, $host, time);
            return $try_port;
        }
    }

    die "No ports left to assign!";
}

sub free_port {
    my ($self, $port, $host) = @_;
    my $dbh = $self->open_db;
    $host = $host ? $host : 'default';
    $dbh->do('delete from server_port where port = ? AND host = ?', undef, $port, $host);
}

sub _is_assigned {
    my ($port, @ports) = @_;
    foreach my $p (@ports) {
        return 1 if $p == $port;
    }
    return undef;
}

1;
