# 
# i am server.  hear me roar.
#

package LeafyWeb::Server;

use Template;
use YAML::Syck;
use LeafyWeb;
use LeafyWeb::Server::Instance;
use Class::Accessor;
use File::Path;
use Carp qw(croak);
use Cwd qw(abs_path cwd);

our @ISA = qw/LeafyWeb Class::Accessor/;

local $YAML::Syck::ImplicitTyping = 1;

__PACKAGE__->mk_accessors(qw/
    server_name     instantiated_with  execute_dir  target_files
/);

sub new {
    my ($class, $server_name) = @_;
    my $self = bless {}, $class;

    if (-d $self->c->LEAFY_SERVER_ROOT . "/" . $server_name) {
        $self->{server_name} = $server_name;
    } elsif (my $server_name = $self->resolve_server_name($server_name)) {
        $self->{server_name} = $server_name if (-d $self->c->LEAFY_SERVER_ROOT . "/" . $server_name);
    }

    if ($self->{server_name}) {
        $self->{pyaml} = LoadFile($self->c->LEAFY_SERVER_ROOT . "/" . $self->{server_name} . '/.leafy_info');
    } else {
        return undef;
    }

    $self->{instantiated_with} = $server_name;
    $self->{execute_dir} = cwd();

    return $self;
}

sub directory {
    my ($self) = @_;
    return $self->c->LEAFY_SERVER_ROOT . "/" . $self->server_name;
}

sub check_syntax {
    my ($self, $site, $instance, $temp_uuid) = @_;
    my $temp_dir = $self->c->LEAFY_TEMP . "/check_config/" . $self->server_name . "/$temp_uuid";
    my $rc = $self->process('util/check_syntax.sh', $site, $instance, {
        type        =>      'default',
        temp_dir    =>      $temp_dir,
    });
    my $res = qx/$rc/;
    return $res;
}


sub pid {
    my ($self, $site, $instance) = @_;
    my $rc = $self->process('util/pid.sh', $site, $instance);
    my $res = qx/$rc/;
    $res = $self->server_name . ":" . $res;
    if ($instance) {
        $res .= ":" . $instance->location;
    }
    return $res;
}

sub running {
    my ($self, $site, $instance) = @_;
    my $rc = $self->process('util/running.sh', $site, $instance);
    my $res = qx/$rc/;
    $res = $self->server_name . ":" . $res;
    if ($instance) {
        $res .= ":" . $instance->location;
    }
    return $res;
}

sub start {
    my ($self, $site, $instance, $verbose) = @_;
    if ($instance && $instance->{state} eq 'STARTED') {
        return;
    } else {
        my $rc = $self->process('rc/start.sh', $site, $instance);
        my $res = qx/$rc/;
        print $res if $verbose;
        chomp($res);
        $instance->set_state('STARTED') if $instance;
        return $res;
    }
}

sub stop {
    my ($self, $site, $instance, $verbose) = @_;
    if ($instance && $instance->{state} eq 'STOPPED') {
        return;
    } else {
        my $rc = $self->process('rc/stop.sh', $site, $instance);
        my $res = qx/$rc/;
        print $res if $verbose;
        chomp($res);
        $instance->set_state('STOPPED') if $instance;
        return $res;
    }
}

sub restart {
    my ($self, $site, $instance, $verbose) = @_;
    my $res;
    if ($self->is_core || ($instance && $instance->{state} eq 'STARTED')) {
        my $rc = $self->process('rc/restart.sh', $site, $instance);
        $res = qx/$rc/;
        print $res if $verbose;
    } else {
        my $rc = $self->process('rc/start.sh', $site, $instance);
        $res = qx/$rc/;
        print $res if $verbose;
        $instance->set_state('STARTED') if $instance;
    }
    chomp($res);
    return $res;
}

# ok so:
# shared: local/conf/sites/_instance.site/_site.site_name.conf
#         local/conf/sites/_shared/web.mg2.org.conf
# also:   local/conf/sites/web.mg2.org/web.mg2.org.conf

sub cleanup_config_check {
    my ($self, $site, $instance, $temp_uuid) = @_;
    return unless $temp_uuid;
    my $temp_dir = $self->c->LEAFY_TEMP . "/check_config/" . $self->server_name . "/$temp_uuid";
    rmtree($temp_dir);
}

sub configure {
    my ($self, $site, $instance, $temp_uuid) = @_;

    # keep track of the configs we deploy
    my @deployed;

    # clear out anything we might have had in here.
    $self->{target_files} = undef;

    chdir($self->directory);

    if (-d 'meta/local/') {
        chdir('meta/local/');
        $self->find_recursive('.');
        if ($self->target_files) {
            foreach my $file (@{$self->target_files}) {
                next if -d $file->{file_name_full};
                push(@deployed, $self->configure_file($file->{file_name_rel}, $site, $instance, $temp_uuid));
            }
        }
    } else {
        if (-d 'meta/') {
            warn "[error] No local config templates found, i think your package is stupid.\n";
        } else {
            warn "[error] No meta directory found, I doubt this is a leafyserver at all.\n";
            sleep 1;
            croak "[insult] asshole.";
        }
    }

    # go back to the execute dir
    chdir($self->execute_dir);

    return(@deployed);
}

sub configure_file {
    my ($self, $file, $site, $instance, $temp_uuid) = @_;

    my ($target_file, $target_dir);

    # use this to figure out if we're the last path element (for directory purposes)
    my $i = 0;

    my @path_elements = split(/\//, $file);
    foreach my $pe (@path_elements) {
        ++$i;
        my $rpe;
        if ($pe =~ /^_([^\.]+)\.([^\.]+)(.*)$/) {
            my $obj = '$' . $1;
            my $method = $2;
            my $rest = $3;
            #print '$rpe = ' . "$obj->{" . $method . "}" . "\n";
            eval ('$rpe = ' . $obj . '->{' . $method . '}');

            if ($@) {
                die "Can't resolve file name $pe, $@\n";
            } else {
                $rpe .= $rest;
            }
        } else {
            $rpe = $pe;
        }

        # rpe's can't start with /.  kthx.
        $rpe =~ s/^\///g;

        if ($target_file) {
            $target_file .= "/$rpe";
        } else {
            $target_file = $rpe;
        }

        # skip the last element for this
        unless ($i == scalar(@path_elements)) {
            if ($target_dir) {
                $target_dir .= "/$rpe";
            } else {
                $target_dir = $rpe;
            }
        }
    }

    # form it here
    my $temp_dir;
    if ($temp_uuid) {
        $temp_dir = $self->c->LEAFY_TEMP . "/check_config/" . $self->server_name . "/$temp_uuid";
    }

    if ($temp_dir) {
        $target_dir = $temp_dir . "/$target_dir";
        $target_file = $temp_dir . "/$target_file";
    } else {
        $target_dir = $self->directory . "/$target_dir";
        $target_file = $self->directory . "/$target_file";
    }

    mkpath($target_dir, undef, 0755);

    open(CONFIG, '>', $target_file) or die "Can't open $target_file for writing: $!\n";
    print CONFIG $self->process("local/" . $file, $site, $instance, {
        type        =>      'default',
        temp_dir    =>      $temp_dir,
    });

    # cfg aliases -- ONLY alias sites.
    if (my $ar = $site->aka) {
        foreach my $aka (@$ar) {
            print CONFIG $self->process("local/" . $file, $site, $instance, {
                type        =>      'alias',
                alias       =>      $aka,
                temp_dir    =>      $temp_dir,
            });
        }
    }

    close(CONFIG);

    # don't take note of temporary deployments pls, LeafyWeb::Site will clean them up.
    unless ($temp_dir) {
        if (my $id = $self->is_config_deployed($site->site_name, $target_file)) {
            # update its timestamp
            $self->update_deploy_timestamp($id);
        } else {
            # create it new
            $self->deployed_config($site->site_name, $target_file);
        }
    }

    return $target_file;
}

sub is_core {
    my ($self) = @_;
    if ($self->aka->[0] eq "leafy-core") {
        return 1;
    } else {
        return 0;
    }
}

sub instances {
    my ($self) = @_;

    return LeafyWeb::Server::Instance->list_instances(
        {
            server_name     =>      $self->server_name
        }
    );
}

sub process {
    my ($self, $to_process, $site, $instance, $pass) = @_;
    
    my ($location, @locations);
    # resolve the first matching location.
    if ($site) {
        $location = $site->location($site->locations_by_instance($instance));
        @locations = $site->locations_by_instance($instance);
    }

    my $tt = Template->new(
        {   
            INCLUDE_PATH    =>      [$self->directory . "/meta", $self->directory . "/meta/config"],
            COMPILE_DIR     =>      $self->leafy_temp,
            ABSOLUTE        =>      1,
        }
    );

    # GET TO THE CHOPPA
    my $output;
    $tt->process($to_process, 
        { 
            server => $self, 
            site => $site,
            instance => $instance,
            location => $location,
            locations => \@locations,
            pass => $pass,
        }, \$output ) or warn "Problem processing: $!, $@";
    return $output;
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
