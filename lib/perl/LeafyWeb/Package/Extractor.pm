package LeafyWeb::Package::Extractor;

our @ISA = qw (Archive::Zip Archive::Zip::Archive);
use Archive::Zip;
use Archive::Zip::Archive;

sub new {
    my ($self, @args) = @_;
    return bless($self->SUPER::new(@args), __PACKAGE__);
}

sub import {
    my ($self) = shift;
    return Archive::Zip->export_to_level(1, @_);
}

# w/ perms preservation ftw
# $zip->extractTree( $root, $dest [, $volume] );
#
# $root and $dest are Unix-style.
# $volume is in local FS format.
#
sub extractTree {
    my $self = shift;
    my $root = shift;    # Zip format
    $root = '' unless defined($root);
    my $dest = shift;    # Zip format
    $dest = './' unless defined($dest);
    my $volume  = shift;                              # optional
    my $pattern = "^\Q$root";
    my @members = $self->membersMatching($pattern);

    foreach my $member (@members) {
        my $fileName = $member->fileName();           # in Unix format
        $fileName =~ s{$pattern}{$dest};    # in Unix format
                                            # convert to platform format:
        $fileName = Archive::Zip::_asLocalName( $fileName, $volume );
        my $status = $member->extractToFileNamed($fileName);

        # if we have file perms data.. lets chmod the file instead of being a total douchebag.
        if (my $attr = $member->unixFileAttributes()) {
            chmod($attr, $fileName);
        }

        return $status if $status != AZ_OK;
    }
    return AZ_OK;
}

1;

