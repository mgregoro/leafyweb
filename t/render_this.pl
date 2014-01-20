#!/usr/bin/perl

use YAML::Syck;
$YAML::Syck::ImplicitTyping = 1;

my $data = {
    hi  =>      'there',
    locations   =>  {
        '/'         =>  {
            this        =>      "that",
            the         =>      "other",
            thing       =>      "."
        },      
        '/example'  =>  {
            hi          =>      "there",
            how         =>      "does this",
            serial      =>      "ize?",
        }
    },
    hi   =>     ,
};

print Dump($data);
