# LeafyWeb::LeafyD::Config is where we're going to store all of our fun configuration options!
# BadNews::Config - Now w/ YAML!
# $Id: Config.pm,v 1.3 2005/04/07 12:58:19 corrupt Exp $

package LeafyWeb::Config;

use YAML::Syck;
use LeafyWeb::LeafyD;
use Carp;

# make sure we stick this in here.. so we can do Yes = 1 and No = 0
local $YAML::Syck::ImplicitTyping = 1;

sub new {
    my ($class, %attribs) = @_;
    my $self = bless(\%attribs, $class);
    if (-e $self->{ConfigFile}) {
        $self->{pyaml} = LoadFile($self->{ConfigFile});
    } else {
        # create :D
        warn "Creating new config file: $self->{ConfigFile}\n";
        $self->{pyaml} = {};
    }
    return $self;
}

# ok we can now set shit, u heard?
sub set {
    my ($self, $key, $value) = @_;
    $self->{pyaml}->{$key} = $value;
}

sub AUTOLOAD {
    my ($self) = @_;
    my $option = $AUTOLOAD;
    $option =~ s/^.+::([\w\_]+)$/$1/g;
    if (exists($self->{pyaml}->{lc($option)})) {
        return $self->{pyaml}->{lc($option)};
    } else {
        # environment variables are config too for leafy, cos we <3 u
        if (exists($ENV{uc($option)})) {
            return $ENV{uc($option)};
        } else {
            return undef;
        }
    }
}

sub write_cfg {
    my ($self) = @_;
    DumpFile($self->{ConfigFile}, $self->{pyaml});
}

sub dump_cfg {
    my ($self) = @_;
    my $cfg;
    foreach my $key (keys %{$self->{pyaml}}) {
        $cfg .= "$key: $self->{pyaml}->{$key}\n";
    }
    return $cfg;
}

sub DESTROY {
    my ($self) = @_;
    $self = {};
    return;
}
