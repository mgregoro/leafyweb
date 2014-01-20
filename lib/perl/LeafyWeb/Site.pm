# 
# i am a leafysite :D
#

package LeafyWeb::Site;

use Data::UUID;
use Template;
use YAML::Syck;
use File::Path;
use LeafyWeb;
use LeafyWeb::Server;
use LeafyWeb::Server::Instance;
use Class::Accessor;

our @ISA = qw/LeafyWeb Class::Accessor/;

local $YAML::Syck::ImplicitTyping = 1;

__PACKAGE__->mk_accessors(qw/
    site_name     instantiated_with
/);

sub new {
    my ($class, $site_name) = @_;

    my $self = bless {}, $class;

    unless ($site_name) {
        die "[repremand] LeafyWeb::Site->new takes one argument, the site's name.  C'mon, I expected better from you.\n";
    }

    if (-d $self->c->LEAFY_SITE_ROOT . "/" . $site_name) {
        $self->{site_name} = $site_name;
    } else {
        die "Can't find site: $site_name\n";
    }

    if ($self->{site_name}) {
        $self->{pyaml} = LoadFile($self->c->LEAFY_SITE_ROOT . "/" . $self->{site_name} . '/conf/' . $self->{site_name} . '.yaml') or die "No config file found for $site_name\n";
    }

    $self->{instantiated_with} = $site_name;

    return $self;
}

sub config_file {
    my ($self) = @_;
    return $self->c->LEAFY_SITE_ROOT . "/" . $self->{site_name} . '/conf/' . $self->{site_name} . ".yaml";
}

sub directory {
    my ($self) = @_;
    if ($self->{directory}) {
        return $self->{directory};
    } else {
        return $self->c->LEAFY_SITE_ROOT . "/" . $self->{site_name};
    }
}

sub document_root {
    my ($self) = @_;
    my $document_root = $self->{pyaml}->{document_root};

    unless ($document_root && -d $document_root) {
        $document_root = $self->c->LEAFY_SITE_ROOT . "/" . $self->{site_name} . "/html";
    }

    return $document_root;
}


sub server_instance {
    my ($self, $location) = @_;

    my $loc = $self->location($location);

    # we cant make instances for the core, so dont bother.
    return undef if $loc->{server} eq "core";

    # make sure we run as a user.. location specific then site owner, then the default.
    # only applies if the instance is NOT shared.
    my $user = $loc->{user} ? $loc->{user} : $self->owner ? $self->owner : $self->c->DEFAULT_SERVER_USER;

    my ($site_name);
    if (my $shared = $loc->{shared}) {
        if ($shared eq "global") {
            # this is a globally shared server instance
            $site_name = "_shared";
            $location = "_lfy_default";

            # by default we run as leafyweb here.
            $user = $self->c->DEFAULT_SERVER_USER;

        } elsif ($shared eq "site") {
            # this instance is shared site-wide (other locations in this site can use it)
            $site_name = $self->name;
            $location = "_lfy_default";

        } elsif ($shared eq "location") {
            # this instance is not shared by any other location.
            $site_name = $self->name;
        }
    } else {
        # leave location alone, cos its already in this function.
        $site_name = $self->name;
    }

    return LeafyWeb::Server::Instance->new(
        {
            site            =>          $site_name,
            server_name     =>          $loc->{server},
            user            =>          $loc->{shared} ? $self->c->DEFAULT_SERVER_USER : $user,
            location        =>          $location,
        }
    );
}

sub instance_map {
    my ($self) = @_;
    unless ($self->{instance_map}) {
        $self->{instance_map} = {};
        foreach my $location ($self->locations) {
            my $si = $self->server_instance($location);
            if ($si) {
                push(@{$self->{instance_map}->{$si->id}}, $location);
            }
        }
    }

    return $self->{instance_map};
}

sub locations_by_instance {
    my ($self, $instance) = @_;
    $instance = $instance->id if ref $instance;
    return wantarray ? @{$self->instance_map->{$instance}} : $self->instance_map->{$instance}->[0];
}

sub instance_by_location {
    my ($self, $location) = @_;

    my $im = $self->instance_map;

    my $match;
    while (my ($k, $v) = each %$im) {
        foreach my $loc (@$v) {
            if ($location eq $loc) {
                $match = $k;
            }
        }
    }

    return LeafyWeb::Server::Instance->new($match);
}

sub start_location {
    my ($self, $location, $verbose) = @_;
    my $si = $self->instance_by_location($location);
    $self->server($si->{server_name})->start($self, $si, $verbose);
}

sub stop_location {
    my ($self, $location, $verbose) = @_;
    my $si = $self->instance_by_location($location);
    $self->server($si->{server_name})->stop($self, $si, $verbose);
}

sub restart_location {
    my ($self, $location, $verbose) = @_;
    my $si = $self->instance_by_location($location);
    $self->server($si->{server_name})->restart($self, $si, $verbose);
}

sub pid {
    my ($self, $location) = @_;

    if ($location) {
        my $si = $self->instance_by_location($location);
        return $self->server($si->{server_name})->pid($self, $si)
    } else {   
        my @ret;
        foreach my $id (keys %{$self->instance_map}) {
            my $si = LeafyWeb::Server::Instance->new($id);
            push(@ret, $self->server($si->{server_name})->pid($self, $si));
        }
        push(@ret, $self->server('core')->pid($self));
        return (@ret);
    }      

}

sub running {
    my ($self, $location) = @_;

    if ($location) {
        my $si = $self->instance_by_location($location);
        return $self->server($si->{server_name})->running($self, $si)
    } else {
        my @ret;
        foreach my $id (keys %{$self->instance_map}) {
            my $si = LeafyWeb::Server::Instance->new($id);
            push(@ret, $self->server($si->{server_name})->running($self, $si));
        }
        push(@ret, $self->server('core')->running($self));
        return (@ret);
    }

}

sub is_running {
    my ($self, $location) = @_;
    my $is_running = 1;
    foreach my $ret ($self->running($location)) {
        my ($server, $running, $pid, $serving) = split(/:/, $ret);
        unless ($running) {
            $is_running = 0;
        }
    }
    return $is_running;
}

sub start {
    my ($self, $verbose) = @_;
    my @ret;
    foreach my $id (keys %{$self->instance_map}) {
        my $si = LeafyWeb::Server::Instance->new($id);
        push(@ret, $self->server($si->{server_name})->start($self, $si, $verbose));
    }
    return (@ret);
}

sub stop {
    my ($self, $verbose) = @_;
    my @ret;
    foreach my $id (keys %{$self->instance_map}) {

        my $si = LeafyWeb::Server::Instance->new($id);

        foreach my $loc ($self->locations_by_instance($id)) {
            my $shared = $self->location($loc)->{shared};
            # can't stop globally shared servers for a partikular indivishual
            if ($shared eq "site" || !$shared) {
                push(@ret, $self->server($si->{server_name})->stop($self, $si, $verbose));
            }
        }
    }
    return (@ret);
}

sub stop_all {
    my ($self, $verbose) = @_;
    my @ret;
    foreach my $id (keys %{$self->instance_map}) {

        my $si = LeafyWeb::Server::Instance->new($id);

        foreach my $loc ($self->locations_by_instance($id)) {
            my $shared = $self->location($loc)->{shared};
            # stop everything, indiscriminately.
            push(@ret, $self->server($si->{server_name})->stop($self, $si, $verbose));
        }
    }
    return (@ret);
}

sub restart {
    my ($self, $verbose) = @_;
    my @ret;
    foreach my $id (keys %{$self->instance_map}) {
        my $si = LeafyWeb::Server::Instance->new($id);
        push(@ret, $self->server($si->{server_name})->restart($self, $si, $verbose));
    }
    return (@ret);
}

sub deconfigure {
    my ($self, $verbose) = @_;
    foreach my $config (@{$self->list_deployed_configs($self->site_name)}) {
        if ($self->count_deployed_configs($config) == 1) {
            print "[info] removing $config\n" if $verbose;
            $self->remove_file($config);
        }
        $self->remove_deployed_config($self->site_name, $config);
    }
    $self->remove_site_config($self->site_name);
}

sub check_location_syntax {
    my ($self, $location, $temp_uuid) = @_;
    my $si = $self->instance_by_location($location);
    my @ret;
    push(@ret, $self->server($si->{server_name})->check_syntax($self, $si, $temp_uuid));
    push(@ret, $self->server('core')->check_syntax($self, undef, $temp_uuid));
    return (@ret);
}

sub check_syntax {
    my ($self, $temp_uuid) = @_;
    my @ret;
    foreach my $id (keys %{$self->instance_map}) {
        my $si = LeafyWeb::Server::Instance->new($id);
        push(@ret, $self->server($si->{server_name})->check_syntax($self, $si, $temp_uuid));
    }
    push(@ret, $self->server('core')->check_syntax($self, undef, $temp_uuid));
    return (@ret);
}

sub cleanup_config_check {
    my ($self, $temp_uuid, $location) = @_;
    my @ret;
    if ($location) {
        my $si = $self->instance_by_location($location);
        push(@ret, $self->server($si->{server_name})->cleanup_config_check($self, $si, $temp_uuid));
    } else {
        foreach my $id (keys %{$self->instance_map}) {
            my $si = LeafyWeb::Server::Instance->new($id);
            push(@ret, $self->server($si->{server_name})->cleanup_config_check($self, $si, $temp_uuid));
        }
    }
    $self->server('core')->cleanup_config_check($self, undef, $temp_uuid);
    return @ret;
}

sub check_config {
    my ($self, $location) = @_;
    my $uuid = Data::UUID->new()->create_str();

    my @check;
    if ($location) {
        $self->configure_location($location, $uuid);
        @check = $self->check_location_syntax($location, $uuid);
    } else {
        $self->configure($uuid);
        @check = $self->check_syntax($uuid);
    }

    $self->cleanup_config_check($uuid, $location);

    # do something about our config, form an error, make a decision, make this useful here
    my $pass_fail = 1;
    my $errors;
    foreach my $chk (@check) {
        my ($instance, $pass, $error) = split(/:/, $chk, 3);
        if ($instance eq "core") {
            unless ($pass) {
                $pass_fail = 0;
                $errors .= "leafycore: $error\n";
            }
        } else {
            my $si = LeafyWeb::Server::Instance->new($instance);
            unless ($pass) {
                $pass_fail = 0;
                $errors .= $si->site . "/" . $si->location(1) . ": $error";
            }
        }
    }

    return ($pass_fail, $errors);
}

sub configure_location {
    my ($self, $location, $temp_uuid) = @_;

    my $si = $self->instance_by_location($location);

    if ($temp_uuid) {
        $self->server($si->{server_name})->configure($self, $si, $temp_uuid);
        $self->server->('core')->configure($self, undef, $temp_uuid);
    } else {
        my @deployed;
        push(@deployed, $self->server($si->{server_name})->configure($self, $si));
        push(@deployed, $self->server('core')->configure($self));

        my @to_delete;
        # get an array of stuff to delete.
        foreach my $db_config (@{$self->list_deployed_configs($self->site_name)}) {
            my $still_deployed = 0;
            foreach my $l_config (@deployed) {
                if ($l_config eq $db_config) {
                    $still_deployed = 1;
                    last;
                }
            }
            unless ($still_deployed) {
                push (@to_delete, $db_config);
            }
        }

        foreach my $config (@to_delete) {
            if ($self->count_deployed_configs($config) == 1) {
                $self->remove_file($config);
            }
        }
    }

    return 1;
}

sub configure {
    my ($self, $temp_uuid) = @_;

    if ($temp_uuid) {
        foreach my $id (keys %{$self->instance_map}) {
            my $si = LeafyWeb::Server::Instance->new($id);
            $self->server($si->{server_name})->configure($self, $si, $temp_uuid);
        }
        push(@deployed, $self->server('core')->configure($self, undef, $temp_uuid));
    } else {
        my @deployed;
        foreach my $id (keys %{$self->instance_map}) {
            my $si = LeafyWeb::Server::Instance->new($id);
            push(@deployed, $self->server($si->{server_name})->configure($self, $si));
        }

        push(@deployed, $self->server('core')->configure($self));

        my @to_delete;
        # get an array of stuff to delete.
        foreach my $db_config (@{$self->list_deployed_configs($self->site_name)}) {
            my $still_deployed = 0;
            foreach my $l_config (@deployed) {
                if ($l_config eq $db_config) {
                    $still_deployed = 1;
                    last;
                }
            }
            unless ($still_deployed) {
                push (@to_delete, $db_config);
            }
        }

        foreach my $config (@to_delete) {
            if ($self->count_deployed_configs($config) == 1) {
                $self->remove_file($config);
            }
        }
    }

    return 1;
}

# krizzle said "delete the dirs if they're empty" <3 krizzle.
sub remove_file {
    my ($self, $config) = @_;
    my @fcs = split(/\//, $config);
    my $path = $config;
    until ($path eq $self->c->LEAFY_SERVER_ROOT) {
        if (-f $path) {
            unlink($path);
        } elsif (-d $path) {
            opendir(DIR, $path);
            my $empty = 1;
            while (my $file = readdir(DIR)) {
                next if $file eq "." or $file eq "..";
                $empty = 0;
            }
            if ($empty) {
                rmdir($path);
            } else {
                last;
            }
        }
        pop(@fcs);
        $path = join('/', @fcs);
    }
}

sub locations {
    my ($self) = @_;
    # we want to return a / location last, for proxy ordering reasons, so if there
    # is one, lets do so.
    my @locations = keys %{$self->{pyaml}->{locations}};

    my @return;
    my $has_slash = 0;
    foreach my $loc (@locations) {
        if ($loc eq "/") {
            $has_slash = 1;
        } else {
            push(@return, $loc);
        }
    }

    push(@return, "/") if $has_slash;
    return @return;
}

sub location {
    my ($self, $location) = @_;
    return $self->{pyaml}->{locations}->{$location};
}

sub server {
    my ($self, $type) = @_;
    return LeafyWeb::Server->new($type);
}

sub location_info {
    my ($self, $location) = @_;
    my $server = LeafyWeb::Server->new($location->{server});
    return $server->info;
}

sub AUTOLOAD {
    my ($self, $val) = @_;
    my $option = $AUTOLOAD;
    $option =~ s/^.+::([\w\_]+)$/$1/g;
    if ($val) {
        $self->{pyaml}->{lc($option)} = $val;
        return $val;
    } else {
        if (exists($self->{pyaml}->{lc($option)})) {
            return $self->{pyaml}->{lc($option)};
        } else {
            return undef;
        }
    }
}

1;
