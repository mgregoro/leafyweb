#!/usr/bin/env perl

use lib qq(../lib/);

use LeafyWeb::Config;

my $c = LeafyWeb::Config->new(ConfigFile    =>  './test.yml');

$c->write_cfg;

