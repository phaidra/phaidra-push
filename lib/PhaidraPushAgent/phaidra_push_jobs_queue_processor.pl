#!/usr/bin/env perl


=head1 NAME

phaidra_push_jobs_queue_processor.pl


=head1 DESCRIPTION

use: perl phaidra_push_jobs_queue_processor.pl

Running Phaidra_push_jobs_agent->run() in given intervals, process jobss, create baggs in
'bags' MongoDb collection (status => new  in 'jobs' MongoDb)

=cut


use strict;
use warnings;
use Data::Dumper;

use MongoDB;

use Cwd 'abs_path';
use Path::Class::File;
use File::Spec;
use JSON;

use MongoDB;
use MongoDB::Connection;

use Phaidra_push_jobs_agent;


my $sleepIntervalSeconds = 5;


my $phaidraYmlConfigPath = '/etc/phaidra.yml';
#my $phaidraYmlConfigPath = '/media/phaidra-entw_root/etc/phaidra.yml';

my $currentDir             = Path::Class::File->new(abs_path($0))->dir();
my $pushJobAgentConfigPath = File::Spec->catfile( @{$currentDir->{dirs}}, 'phaidraPushJobsAgent.json' );
my $last_one               = pop @{$currentDir->{dirs}};
$last_one                  = pop @{$currentDir->{dirs}};
my $configPath             = File::Spec->catfile( @{$currentDir->{dirs}}, 'PhaidraPush.json' );


my $json_text = do {
   open(my $json_fh, "<:encoding(UTF-8)", $configPath)
      or die("Can't open \$configPath\": $!\n");
   local $/;
   <$json_fh>
};
my $json   = JSON->new;
my $config = $json->decode($json_text);


my $client = MongoDB::Connection->new(
    host     =>     $config->{phaidra}->{mongodb}->{host},
    port     =>     $config->{phaidra}->{mongodb}->{port},
    username =>     $config->{phaidra}->{mongodb}->{username},
    password =>     $config->{phaidra}->{mongodb}->{password},
    db_name  =>     $config->{phaidra}->{mongodb}->{database}
);



while (1) {
     my $collectionJobs = $client->ns( $config->{phaidra}->{mongodb}->{database}.'.'.'jobs');
     my $dataSetPU = $collectionJobs->find({'status' => 'new', 'agent' => 'push_agent'});
     my $exists = $dataSetPU->count();
     if($exists){
           my $agent = Phaidra_push_jobs_agent->new(
                                          $configPath,
                                          $phaidraYmlConfigPath,
                                          $pushJobAgentConfigPath,
                                        );
           print "Runing phaidra push jobs agent.  \n";
           $agent->run();
           sleep($sleepIntervalSeconds);
     }else{
           print "sleeping... \n";
           sleep($sleepIntervalSeconds);
     }
}

1;