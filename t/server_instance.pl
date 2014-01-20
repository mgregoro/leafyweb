#!/usr/bin/env perl

use LeafyWeb::Server::Instance;

my $si2 = LeafyWeb::Server::Instance->new(
    {
        server_name     =>      'php',
        user            =>      'leafyweb',
        site            =>      'www.mg2.org',
        location        =>      '/test2',
    }
);

my $si = LeafyWeb::Server::Instance->new(
    {
        server_name     =>      'php',
        user            =>      'leafyweb',
        site            =>      'www.mg2.org',
        location        =>      '/test',
    }
);

use Data::Dumper;

print $si->id . "\n";
print $si2->id . "\n";

print $si->location(1) . "\n";

my $si3 = LeafyWeb::Server::Instance->new($si->id);

print Dumper($si);
print Dumper($si2);
print Dumper($si3);

exit();

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


