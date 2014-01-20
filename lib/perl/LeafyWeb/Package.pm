# Object representation of a LeafyWeb package
# Provides compression, configuration, build, and (in)sanity checks.
package LeafyWeb::Package;

use Class::Accessor;
use YAML::Syck;
use LeafyWeb::Package::Extractor qw(:ERROR_CODES :CONSTANTS);
use Archive::Zip::MemberRead;
use Carp qw(croak);
use LeafyWeb;
use Data::UUID;
use Template;
use Carp qw(croak);
use Cwd qw(abs_path cwd);

our @ISA = qw/LeafyWeb Class::Accessor/;

local $YAML::Syck::ImplicitTyping = 1;

my $ug = Data::UUID->new();

__PACKAGE__->mk_accessors(qw/   arch prefix server_type platform version 
                                filename system_platform system_arch 
                                zip target_files temp_dir build_target 
                                execute_dir packed verbose/);

# a short description of this bundle of accessors
# arch: the machine's architecture package is built for
# prefix: the basis of this server e.g. tc5 (tomcat 5) a22 (apache 2.2) lht (lighttpd)
# platform: the platform (linux, darwin, solaris, etc)
# version: the package version, usually the base server's version is used in this
# server_type: the type of app server.. (core, php, perl, java, etc)
# filename: the name of the file this was instantiated with
# system_platform: lower case, underscore-friendly platform drived from uname of THIS system
# system_arch: lower case, underscore-friendly system architecture derived from uname of THIS system
# target_files: an array of all of the files targeted for packing
# zip: an instantiated Archive::Zip object for this package
# temp_dir: if true, both indicates that the file is extracted, and tells you where its temporarily extrated to
# execute_dir: the directoy where this package first was instantiated
# packed: boolean wether or not the package has been packed up (zipped)
# verbose: boolean wether or not we should be verbose with our errorz

sub new {
    my ($class, $filename, $target, $verbose) = @_;

    my ($self) = bless({filename => $filename}, $class);

	$self->{verbose} = $verbose;
    $self->{zip} = LeafyWeb::Package::Extractor->new();
    $self->parse_filename($filename);
    $self->parse_uname;
    
    $self->{execute_dir} = cwd();
    
    if (-e $filename) {
        # this is an existing package!
        croak "[init error] Error reading leafy package $filename!" unless $self->{zip}->read($filename) == AZ_OK;
        my $fh = Archive::Zip::MemberRead->new($self->{zip}, '.leafy_info');
        if ($fh) {
            my $buffer;
            while ($fh->read($buffer, 1024)) {
                $yaml .= $buffer;
            }
            $self->{pyaml} = Load($yaml);
        }
        $self->packed(1);
    } elsif (-d $target) {
        # we're creating this package!
        if (-e "$target/.leafy_info") {
            # they've already configured leafy info
            open(LFYML, '<', "$target/.leafy_info");
            my $yaml;
            {
                local $/;
                $yaml = <LFYML>;
            }
            $self->{pyaml} = Load($yaml);
            if ($filename ne $self->filename) {
                warn "[error] File name '$filename' isn't going to work out.  How about '" . $self->filename . "' instead?\n";
                
                $filename = $self->filename;

                # we altered it, we should re-parse it.
                $self->parse_filename($filename);
                
                if (-e $filename) {
                    warn "[error] Bizzare Situation: file we're trying to rename to: $filename already exists -- unlinking!";
                    unlink($filename);
                }
            }

            # make this dir, if it doesn't exist
            mkdir("$target/" . $self->name) unless (-d "$target/" . $self->name);
            
            # set the build target to the absolute path of $target
            $self->{build_target} = abs_path("$target");
        } else {
            croak "[init error] Please configure this leafy package by editing $target/.leafy_info\n";
        }
    } else {
        croak "[whammy] $filename not an existing leafy package.\n";
    }

    return $self;
}

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

sub filename {
    my ($self, $filename) = @_;
    if ($filename) {
        $self->{filename} = $filename;
    } elsif(my $name = $self->name) {
        # get the file name off of a passed full path.
        if ($name =~ /[\\\/]*([^\/\\]+?_[^_]+_[^_]+_[^_]+_[^_-]+-?\w*)$/) {
            $self->{filename} = "$1.lpkg";
        }
    }

    return $self->{filename};
}

sub parse_filename {
    my ($self) = @_;
    if ($self->{filename} =~ /([^\/\\]+?)_([^_]+)_([^_]+)_([^_]+)_([^_-]+)-?(\w*)\.lpkg$/) {
        $self->{platform} = $1;
        $self->{arch} = $2;
        $self->{prefix} = $3;
        $self->{server_type} = $4;
        $self->{version} = $5;
        $self->{impl} = $6;
    }
}

sub package_name {
    my ($self) = @_;
    my $name_string = $self->platform . '_' . $self->arch . '_' . $self->prefix . '_' . $self->server_type . '_' . $self->version;
    
    if ($self->impl) {
        $name_string .= '-' . $self->impl;
    }
    
    # always lower
    return lc($name_string);
}

sub parse_uname {
    my ($self) = @_;
    my $uname = `uname -sm`;
    
    my %proper_names = (
        x86_64  =>  'amd64',
        Darwin  =>  'macos',
    );
    
    if ($uname =~ /([^\s]+) ([^\s]+)$/) {
        $self->{system_platform} = exists($proper_names{$1}) ? $proper_names{$1} : lc($1);
        $self->{system_arch} = exists($proper_names{$2}) ? $proper_names{$2} : lc($2);
    }
}

sub install {
    my ($self) = @_;
    # extract us unless we're already extracted.
    unless ($self->temp_dir) {
        $self->temp_extract;
    }
    
    if ($self->source && !$self->binary_compat && !$self->built) {
        # build will call us right back!  uh.. the hell it will!
        $self->build();
    }

    # make sure we're not stepping on another server.
    if (-d $self->c->LEAFY_SERVER_ROOT . "/" . $self->name) {
        croak "[whammy] Server: " . $self->name . " already installed!";
    }

    # actual install!
    if (-d $self->temp_dir . "/" . $self->name . "/" . $self->c->LEAFY_SERVER_ROOT) {
        system("mv " . $self->temp_dir . "/" . $self->name . "/" . $self->c->LEAFY_SERVER_ROOT . "/* " . $self->install_dir);
    } else {
        system("mv " . $self->temp_dir . "/" . $self->name . " " . $self->c->LEAFY_SERVER_ROOT);
    }

    # don't forget the meta!
    system("cp -rp " . $self->temp_dir . "/meta" . " " . $self->install_dir);
    system("cp -rp " . $self->temp_dir . "/.leafy_info" . " " . $self->install_dir);

    # configure the server
    $self->configure;

    # save the global config
    $self->c->{pyaml}->{installed_leafy_servers}->{$self->server_type} = $self->package_name;
    $self->c->{pyaml}->{installed_leafy_servers}->{$self->package_name} = $self->package_name;
    foreach my $name (@{$self->aka}) {
        $self->c->{pyaml}->{installed_leafy_servers}->{$name} = $self->package_name;
    }

    $self->c->write_cfg;
}

sub install_dir {
    my ($self) = @_;
    return $self->c->LEAFY_SERVER_ROOT . "/" . $self->name;
}

sub build {
    my ($self) = @_;

    if ($self->packed && !$self->temp_dir) {
        $self->temp_extract;
    }

    # this package is now native!  or at least it should be, lets treat it as such.
    $self->platform($self->system_platform);
    $self->arch($self->system_arch);
    $self->name($self->package_name); 
    
    if (-d $self->build_target . "/src") {
        # we can build.. but first we need to put ourselves into the temp dir.
        chdir($self->build_target);
        
        # install only if we built successfully, the build script is in charge of bitching about
        # build issues.
        unless(system($self->process('build.sh'))) {
            $self->built(1);
        }    
    } else {
        croak "[error] Can't build " . $self->name . ", no 'src' directory found!";
    }
    
    $self->build_timestamp(time);
    $self->write_config;
}

# package-level config is always global.
sub configure {
    my ($self) = @_;

    # clear out anything we might have had in here.
    $self->{target_files} = undef;

    chdir($self->build_target);

    if (-d 'meta/global/') {
        print "[info] working in: " . cwd() . "\n";
        chdir('meta/global/');
        $self->find_recursive('.');
        if ($self->target_files) {
            foreach my $file (@{$self->target_files}) {
                next if -d $file->{file_name_full};
                $self->configure_file($file->{file_name_rel});
            }
        }
    } else {
        if (-d 'meta/') {
            warn "[error] No global config templates found, i think your package is stupid.\n";
        } else {
            warn "[error] No meta directory found, I doubt this is a leafyserver.\n";
            sleep 1;
            croak "[insult] asshole.";
        }
    }

    # go back to the execute dir
    chdir($self->execute_dir);
}


sub configure_file {
    my ($self, $file) = @_;
    print "[configuring] $file => " . $self->install_dir . "/" . "$file\n";
    open(CONFIG, '>', $self->install_dir . "/" . $file) or die "Can't open " . $self->install_dir . "/" . "$file: $!\n";
    print CONFIG $self->process("global/" . $file);
    close(CONFIG);
}

sub pack_up {
    my ($self, $target) = @_;

    return if $self->packed;

    print "Packing up $target to " . $self->execute_dir . "/" . $self->package_name . ".lpkg" . "\n";
    
    my $zipfh = IO::File->new($self->execute_dir . "/" . $self->package_name . ".lpkg", 'w');

    chdir($target);

    unless (-d $self->name) {
        croak "[error] Can't pack up this package, directory " . $self->name . " does not exist!";
    }
    
    $self->find_recursive('.');

    if ($self->verbose) {
        print "Archiving " . scalar(@{$self->target_files}) . " files.\n";
    }

    foreach my $file (@{$self->target_files}) {
        $self->zip->addFileOrDirectory($file->{file_name_full});
    }

    unless ($self->zip->writeToFileHandle($zipfh) == AZ_OK) {
        croak "[error] Write error! $!, $@\n";
    }

    # clean up
    $zipfh->close();
    chdir($self->execute_dir);

    # load packed up package into zip for future operations
    $self->{zip} = LeafyWeb::Package::Extractor->new();
    croak "[whammy] Error reading leafy package " . $self->filename unless $self->zip->read($self->filename) == AZ_OK;
    
    # mark this as packed!
    $self->packed(1);
}

sub pack_binaries {
    my ($self, $target) = @_;

	my $zip;
	if ($self->packed) {
		print "Extracting source / built code to temp directory...\n" if $verbose;
		$self->temp_extract;
		$target = $self->build_target;
		$self->impl('bin');
		$zip = LeafyWeb::Package::Extractor->new();
	} else {
		$zip = $self->{zip};
	}

    print "Packing up $target to " . $self->execute_dir . "/" . $self->package_name . ".lpkg (BINARIES ONLY)" . "\n";
    
    $self->source('false');
    $self->write_config();
    
    my $zipfh = IO::File->new($self->execute_dir . "/" . $self->package_name . ".lpkg", 'w');

    chdir($target);

    unless (-d $self->name) {
        croak "[inadequacy] Can't pack up binaries for this package, directory " . $self->name . " does not exist!  Try building first?";
    }

    $self->find_recursive('.');
    
    if ($self->verbose) {
        print "Archiving " . scalar(@{$self->target_files}) . " files.\n";
    }

    foreach my $file (@{$self->target_files}) {
        next if $file->{file_name_full} =~ /^\.\/src/;
        print "$file->{file_name_full}\n" if $self->verbose;
        $zip->addFileOrDirectory($file->{file_name_full});
    }

    unless ($zip->writeToFileHandle($zipfh) == AZ_OK) {
        croak "[error] Write error! $!, $@\n";
    }

    # clean up
    $zipfh->close();
    chdir($self->execute_dir);

	print "Done compressing package...\n" if $self->verbose;

    # load packed up package into zip for future operations
    $self->{zip} = LeafyWeb::Package::Extractor->new();
    croak "[emotional issue] Error reading leafy package " . $self->filename unless $self->zip->read($self->filename) == AZ_OK;
    
    # mark this as packed!
    $self->packed(1);
}

sub binary_compat {
    my ($self) = @_;
    if ($self->built && 
        $self->system_arch eq $self->arch && 
        $self->system_platform eq $self->platform) {
        return 1;
    } else {
        return 0;
    }
}

sub temp_extract {
    my ($self) = @_;
    
    if ($self->packed) {
        my $uuid = $ug->create_str();
        my $temp_dir = $self->c->LEAFY_TEMP . "/$uuid";
        $self->extract($temp_dir);
        $self->temp_dir($temp_dir);
    
        # we want to build here too.
        $self->build_target($temp_dir);
    }
}

sub temp_cleanup {
    my ($self) = @_;

    if (my $dir = $self->temp_dir) {
        system("rm -rf $dir");
        $self->temp_dir(undef);
        $self->build_target(undef);
    }
    
}

sub extract {
    my ($self, $dest) = @_;
    print "OK zip is: " . $self->zip . "\n";
    $dest = $dest ? $dest : $self->c->LEAFY_SERVER_ROOT . '/' . $self->name;
    $self->zip->extractTree(undef, $dest . "/");
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

# writes configs depending on the context
sub write_config {
    my ($self, $pack) = @_;
    if ($pack) {
        # write to the package's config!
        $self->temp_extract;
        DumpFile($self->build_target . '/.leafy_info', $self->{pyaml});
        $self->pack_up;
        $self->temp_cleanup;
    } else {
        # write to the temp dir!
        DumpFile($self->build_target . '/.leafy_info', $self->{pyaml});
    }
}

sub dump_config {
    my ($self) = @_;
    return Dump($self->{pyaml});
}

sub DESTROY {
    my ($self) = @_;
    $self->temp_cleanup;
    $self = {};
    return;
}

sub process {
    my ($self, $to_process) = @_;
    my $tt = Template->new(
        {
            INCLUDE_PATH    =>      [$self->build_target . "/meta", $self->build_target . "/meta/config"],
            COMPILE_DIR     =>      $self->leafy_temp,
            ABSOLUTE        =>      1,
        }
    );
    my $output;
    $tt->process($to_process, { this => $self, self => $self, package => $self }, \$output) or warn "Problem processing: $!, $@";
    return $output;
}
  
1;
