# 
# $Id: HandlerRegistry.pm,v 1.3 2005/10/24 15:57:15 corrupt Exp $
# the HandlerRegistry package
#

#
# Implementation notes for future me:
#
# you want to recurse through the sub directories in set.d running "register"
# we only need the handler name and the priority, so if they don't accept the 
# "register" command as $ARGV[0], take the priority and handler name out of the
# file name (\d\d)filename where the first two characters are the priority
# and just use the whole string as the handler name
#
# so new.d/98wsuExpireTimestamp would create a LeafyWeb::LeafyD::HandlerRegistry::Handler object
# with priority set to '98' and handler_name set to '98wsuExpireTimestamp' within the
# 'new' event_type space.  Also should set something like $handler->exec_path($full_name) 
# so we can just run it no problems.
#

package LeafyWeb::LeafyD::HandlerRegistry;

@ISA = ('LeafyWeb::LeafyD');
use LeafyWeb::LeafyD;
use LeafyWeb::LeafyD::HandlerRegistry::Handler;
use Carp;

sub new {
    my ($class, $event_type) = @_;

    # include the event type in the constructor so we don't have to register ALL handlers
    # every time we run this... just for the event_type that we're running for.
    my $self = bless({  handlers        =>      [],
                        event_type      =>      $event_type
                    }, $class);

    $self->register_handlers;
    return $self;
}

sub handlers {
    my ($self) = @_;
    return @{$self->{handlers}}
}

sub register_handlers {
    my ($self) = @_;
    opendir(HANDLERS, $self->c->LEAFYD_HANDLER_BASE . "/set.d/" . $self->event_type . ".d") or 
        croak $self->c->LEAFYD_HANDLER_BASE . "/set.d/" . $self->event_type . ".d" . " doesn't exist!";

    # iterate through these fine handlers.
    while (my $handler = readdir(HANDLERS)) {
        next if $handler =~ /^\.+$/;
        next if $handler eq "CVS";
        next if $handler eq ".svn";

        # preserve the original file name.
        my $handler_name = $handler;

        # Yesssss!
        $handler = $self->c->LEAFYD_HANDLER_BASE . "/set.d/" . $self->event_type . ".d" . "/$handler";

        # get the registration infos...
        my $register_text;

        # now file names are more efficient than compliant registry-enabled scripts
        # but this is how we want it, you can see more at a glance from the file 
        # names.  and it is a more understood convention.
        # oh and it also allows the file name's priority to override a hard-coded
        # priority.  that is sexy ;)
        if ($handler_name =~ /^(\d\d)(.+)$/) {
            $register_text .= "handler_name=$handler_name\n";
            $register_text .= "priority=$1\n";
            $register_text .= "name_sans_priority=$2\n";
            $register_text .= "registry=FALSE\n";
        } else {
            # check that the script uses the registry
            if (_handler_uses_registry($handler)) {
                # register the handler.
                $register_text = `$handler register`;
                $register_text .= "registry=TRUE\n";
            } else {
                # skip this file, its not a handler
                warn "$handler_name at $handler doesn't have a proper file name or a Registry declaration.  Get it outta here!";
                next;
            }
        }

        my @stat = stat($handler);
        $register_text .= "m_time=" . scalar localtime($stat[9]) . "\n";
        $register_text .= "size=$stat[7]\n";
        $register_text .= "exec_path=$handler\n";
        push(@{$self->{handlers}}, LeafyWeb::LeafyD::HandlerRegistry::Handler->new(register_text  =>  $register_text));
    }

    # Done!
    closedir(HANDLERS);
}

# return the handlers sorted by priority
sub handlers_in_priority_order {
    my ($self) = @_;
    return sort { $a->priority <=> $b->priority } @{$self->{handlers}};
}

sub handler_by_name {
    my ($self, $handler_name) = @_;
    foreach my $handler ($self->handlers) {
        return $handler if $handler->handler_name eq $handler_name;
    }
    return undef;
}

# cheap accessor .. rockx the houxe
sub event_type {
    my ($self, $event_type) = @_;
    if ($event_type) {
        $self->{event_type} = $event_type;
    }
    return $self->{event_type};
}


# returns true if the handler file passed (with full path) literally
# use()'s LeafyWeb::LeafyD::HandlerRegistry::Handler
sub _handler_uses_registry {
    my ($handler) = @_;

    # just in case we get an object.. which we never should.  dont call this method.
    if (ref($handler) eq "LeafyWeb::LeafyD::HandlerRegistry") {
        $handler = shift;
    }

    local $/;
    open(HANDLER_FILE, '<', $handler) or croak "Can't open $handler: $!";
    my $handler_text = <HANDLER_FILE>; #sluuuuurp
    close(HANDLER_FILE);

    return $handler_text =~ /LeafyWeb::LeafyD::HandlerRegistry::Handler/;
}

1;
