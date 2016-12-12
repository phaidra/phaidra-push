#!/usr/bin/env perl
use warnings;
use strict;
use Daemon::Control;
use Data::Dumper;

 
use Cwd 'abs_path';
use Path::Class::File;
use File::Spec;
 
my $currentDir =  Path::Class::File->new(abs_path($0))->dir();
my $processorScriptPath = File::Spec->catfile( @{$currentDir->{dirs}}, 'phaidra_push_jobs_queue_processor.pl' );
                                                                        
print "$processorScriptPath\n";

exit Daemon::Control->new(
    name        => "Phaidra-push Job Agent",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Phaidra-push Job Agent',
    lsb_desc    => 'Phaidra-push Job Agent. Writes bags into Bags MongoDb collection.',
    #path        => '/etc/init.d/apim-harvester',
    program     => "$processorScriptPath",
    #program_args => [ '--debug' ], for debugging the harvester
    pid_file    => '/tmp/phaidraPushJobAgent.pid',
    stderr_file => '/tmp/phaidraPushJobAgent.out',
    stdout_file => '/tmp/phaidraPushJobAgent.out',

    fork        => 2,
 
)->run;