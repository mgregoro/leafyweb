#
# $Id: Handler.pm,v 1.1 2005/04/07 12:58:19 corrupt Exp $
# the LeafyWeb::LeafyD handler registry
#
# Stores handler atributes in a nice neat little object ;)
#

package LeafyWeb::LeafyD::HandlerRegistry::Handler;

use Carp;

sub new {
    my ($class, %attribs) = @_;

    # we can be one of two ways..
    if (exists($attribs{register_text})) {
        my $self = bless({attribs   =>      {}}, $class);
        foreach my $entry (split(/\n/, $attribs{register_text})) {
            $entry =~ /^(.+)=(.*)$/;
            $self->{attribs}->{$1} = $2;
        }
        return $self;
    } else {
        # just require a few things.. nothing too strict.
        unless (exists($attribs{handler_name})) {
            croak "handler_name must be specified to register event handler.";
        }
        unless (exists($attribs{priority})) {
            croak "priority must be specified to register event handler.";
        }
        return bless({attribs   =>  \%attribs}, $class);
    }
}

sub registration {
    my ($self) = @_;
    my $return;
    foreach my $key (keys %{$self->{attribs}}) {
        if (ref($self->{attribs}->{$key}) eq "ARRAY") {
            $return .= "$key=" . join(',', @{$self->{attribs}->{$key}}) . "\n";
        } else {
            $return .= "$key=" . $self->{attribs}->{$key} . "\n";
        }
    }
    return $return;
}

# this way it won't be split into an array by commas in the description ;)
sub description {
    my ($self) = @_;
    if (exists($self->{attribs}->{description})) {
        return $self->{attribs}->{description};
    }
    return undef;
}

sub AUTOLOAD {
    my ($self) = @_;
    my $key = $AUTOLOAD;
    $key =~ s/^.+::([\w\_]+)$/$1/g;
    if (exists $self->{attribs}->{$key}) {
        if (ref($self->{attribs}->{$key}) eq "ARRAY") {
            return @{$self->{attribs}->{$key}};
        } elsif ($self->{attribs}->{$key} =~ /,/) {
            my @array = split(/\s*,\s*/, $self->{attribs}->{$key});
            $self->{attribs}->{$key} = \@array;
            return @array;
        } else {
            return $self->{attribs}->{$key};
        }
    } else {
        return undef;
    }
}

1;
