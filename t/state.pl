#!/usr/bin/env perl

use LeafyWeb::State;

my $state = LeafyWeb::State->new();

my $id = "linux_amd64_a22_php_2.2.9-192.168.0.139:30000";

my $info = $state->server_instance($id);

#my $info = $state->server_instance(
#    {
#        server_name     =>      'php',
#        user            =>      'leafyweb',
#        site            =>      'web.mg2.org',
#    }
#);

#$state->destroy_instance(
#    {
#        server_name     =>      'php',
#        user            =>      'leafyweb',
#        site            =>      'web.mg2.org',
#    }
#);

print $state->identifier($info) . "\n";
use Data::Dumper;

print Dumper($info);


