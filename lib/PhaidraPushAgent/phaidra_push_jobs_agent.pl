#!/usr/bin/env perl

use utf8;
use strict;
use warnings;
use Data::Dumper;

use Cwd 'abs_path';
use Path::Class::File;
use File::Spec;

use Phaidra_push_jobs_agent;


my $phaidraYmlConfigPath = '/etc/phaidra.yml';


my $currentDir             = Path::Class::File->new(abs_path($0))->dir();
my $pushJobAgentConfigPath = File::Spec->catfile( @{$currentDir->{dirs}}, 'phaidraPushJobsAgent.json' );
my $last_one               = pop @{$currentDir->{dirs}};
$last_one                  = pop @{$currentDir->{dirs}};
my $configPath             = File::Spec->catfile( @{$currentDir->{dirs}}, 'PhaidraPush.json' );

my $agent = Phaidra_push_jobs_agent->new(
                                          $configPath,
                                          $phaidraYmlConfigPath,
                                          $pushJobAgentConfigPath
                                        );
$agent->run();


1;