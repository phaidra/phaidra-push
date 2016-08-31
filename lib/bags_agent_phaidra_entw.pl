#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

use JSON;
use MongoDB;
use MongoDB::Connection;
use MongoDB::OID;

use Mojo::Base 'Mojolicious';
use Mojo::ByteStream qw(b);
use YAML::Syck;
use Mojo::Asset::File;
use Mojo::Upload;


=head1
  
  Usage perl bags_agent_phaidra_entw.pl /path/PhaidraPush.json path/phaidra.yml 
 
=cut


$ENV{MOJO_INACTIVITY_TIMEOUT} = 7200;
$ENV{MOJO_MAX_MESSAGE_SIZE} = 116777216;



my $filename = '/home/michal/Documents/code/area42/user/mf/phaidra-push/PhaidraPush.json';
#my $filename = $ARGV[0];
my $phaidraConfingAdress = '/media/phaidra-entw_root/etc/phaidra.yml';
#my $phaidraConfingAdress = $ARGV[1];

#read PhaidraPush.json
my $json_text = do {
   open(my $json_fh, "<:encoding(UTF-8)", $filename)
      or die("Can't open \$filename\": $!\n");
   local $/;
   <$json_fh>
};

my $json = JSON->new;
my $config = $json->decode($json_text);

my $client = MongoDB::Connection->new(
    host      => $config->{mongodb_phaidrapush}->{host}, 
    port      => $config->{mongodb_phaidrapush}->{port},
    username  => $config->{phaidra}->{mongodb}->{username},
    password  => $config->{phaidra}->{mongodb}->{password},
    db_name   => $config->{phaidra}->{mongodb}->{database}
);


my $collectionJobs = $client->ns( $config->{phaidra}->{mongodb}->{database}.'.'.'jobs');
my $collectionBags = $client->ns( $config->{phaidra}->{mongodb}->{database}.'.'.'bags');



my $config2           = YAML::Syck::LoadFile( $phaidraConfingAdress );
my $fedoraadminuser   = $config2->{"fedoraadminuser"};
my $fedoraadminpass   = $config2->{"fedoraadminpass"};
my $phaidraapibaseurl = $config2->{"phaidraapibaseurl"};


$phaidraapibaseurl =~ s/https:\/\///g;
my @base = split('/',$phaidraapibaseurl);
my $scheme = "https";

my $ua = Mojo::UserAgent->new;

sub uploadObject($);
sub getOctets($);


##################################################################
##################################################################
############          Main                    ####################
##################################################################
##################################################################

while(1){
   sleep(5);
   print "Start while loop.\n";
   my $dataSetPU = $collectionBags->find({'type' => 'push' , 'status' => 'new'});
   while (my $push_agent = $dataSetPU->next) {
                  my $data;
                  my $result = uploadObject($push_agent);
                  print 'ddd:',Dumper($result);
                  if((scalar @{$result->{error}}) eq 0){
                          # jobs add bag into job with new pid
                          print '$push_agent->{job_id}:',Dumper($push_agent->{job_id}),"\n";
                          my $dataJobs = $collectionJobs->find_one({ _id => MongoDB::OID->new(value => $push_agent->{job_id}) });
                          my $jobBags = $dataJobs->{bags};
                          my $jobsId = $dataJobs->{_id}->{value};
                          foreach my $bag (@{$jobBags}){
                               if($bag->{old_pid} eq  $push_agent->{old_pid}){
                                   $bag->{new_pid} = $result->{pid};
                               }
                          }
                          
                          $collectionJobs->update({"_id" => MongoDB::OID->new(value => $jobsId) }, {'$set' => {'bags' => $jobBags, 'time' => time}});
                          # bags add status processed
                          $collectionBags->update({"_id" => MongoDB::OID->new(value => $push_agent->{_id}->{value}) }, {'$set' => {'status'  => 'processed',
                                                                                                                                   'time'    => time, 
                                                                                                                                   'new_pid' => $result->{pid}}});
                  }else{
                          $collectionBags->update({"_id" => MongoDB::OID->new(value => $push_agent->{_id}->{value}) }, {'$set' => {'status' => 'error', 
                                                                                                                                   'time'   => time, 
                                                                                                                                   'error'  => $result->{error}}});
                  }
   }
   print "End while loop.\n";
}


sub uploadObject($){
  
     my $data = shift;
     my @error;

     # create object
     my $url = Mojo::URL->new;
     $url->scheme($scheme);
     $url->host($base[0]);
     $url->userinfo("$fedoraadminuser:$fedoraadminpass");
     print Dumper("/object/create/$data->{cmodel}");
     if(exists($base[1])){
         $url->path($base[1]."/object/create/$data->{cmodel}");
     }else{
         $url->path("/object/create/$data->{cmodel}");
     }
     my $tx = $ua->post($url);
     my $pid;
     if (my $res = $tx->success) {
         my $res_data =  $tx->res->json;
         $pid = $res_data->{pid};
         print Dumper($pid);
        
     }else {
          print "Error1:", Dumper($tx->error);
          if($tx->res->json && exists($tx->res->json->{alerts})){   
               my $temp = $tx->res->json->{alerts};
               my $temp2->{step} = 'object/pid/cmodel';
               $temp2->{alerts} = $temp;
               push @error, $temp2;
               print 'Error2:', Dumper($tx->res->json->{alerts});
          }else{
               my $temp = $tx->error;
               $temp->{step} = 'object/create/cmodel';
               push @error, $temp;
               print 'Error3:', Dumper($tx->error);
          }
          
     } 
   
    # upload octets data
    if(defined $pid){
            my $getOctetsRes = getOctets($data->{old_pid});
            my $octRes = $getOctetsRes->{result};
            @error = @{$getOctetsRes->{error}} if defined $getOctetsRes->{error};

            my $getDataFlag = 0;
           
            if(defined $octRes){
                  my $url3 = Mojo::URL->new;
                  $url3->scheme($scheme);
                  $url3->host($base[0]);
                  $url3->userinfo("$fedoraadminuser:$fedoraadminpass");
                  print Dumper("/object/$pid/data");
                  if(exists($base[1])){
                      $url3->path($base[1]."/object/$pid/data");
                  }else{
                      $url3->path("/object/$pid/data");
                  }    
                  
                  my $tx2 = $ua->post($url3 => form => { file => {file => $octRes} , mimetype =>  $data->{mimetype} }  );
                  if (my $res = $tx2->success) {
                         my $res_data =  $tx2->res->json;
                         $getDataFlag = 1;
                  }else {
                       print "Error1:", Dumper($tx2->error);
                       if($tx2->res->json && exists($tx2->res->json->{alerts})){
                            print 'Error2:', Dumper($tx2->res->json->{alerts});
                            my $temp = $tx2->res->json->{alerts};
                            my $temp2->{step} = 'object/pid/data';
                            $temp2->{alerts} = $temp;
                            print 'temp2:',Dumper($temp2);
                            push @error, $temp2;
                       }else{
                            print 'Error3:', Dumper($tx2->error);
                            my $temp = $tx2->error;
                            $temp->{step} = 'object/pid/data';
                            push @error, $temp;
                       }
                  } 
            }
     
   
   
            if($getDataFlag){
                    # upload metadata
                    my $url2 = Mojo::URL->new;
                    $url2->scheme($scheme);
                    $url2->host($base[0]);
                    $url2->userinfo("$fedoraadminuser:$fedoraadminpass");
                    print Dumper("/object/$pid/metadata");
                    if(exists($base[1])){
                        $url2->path($base[1]."/object/$pid/metadata");
                    }else{
                        $url2->path("/object/$pid/metadata");
                    }    
                    my $json_str = b(encode_json({ metadata => $data->{metadata_response}->{metadata}  }))->decode('UTF-8');
            
                    my $tx2 = $ua->post($url2 => form => { metadata => $json_str } );
            
                    if (my $res = $tx2->success) {
                           my $res_data =  $tx2->res->json;
                    }else {
                         print "Error1:", Dumper($tx2->error);
                         if($tx2->res->json && exists($tx2->res->json->{alerts})){   
                             my $temp = $tx2->res->json->{alerts};
                             my $temp2->{step} = 'object/pid/metadata';
                             $temp2->{alerts} = $temp;
                             push @error, $temp2;
                             print 'Error3:', Dumper($tx2->error);
                        }else{
                             my $temp = $tx2->error;
                             $temp->{step} = 'object/pid/metadata';
                             push @error, $temp;
                             print 'Error3:', Dumper($tx2->error);
                         }
                   } 
            
            
     
                    # activate object
                    my $url = Mojo::URL->new;
                    $url->scheme($scheme);
                    $url->host($base[0]);
                    $url->userinfo("$fedoraadminuser:$fedoraadminpass");
                    print Dumper("/object/$pid/modify activate");
                    if(exists($base[1])){
                        $url->path($base[1]."/object/$pid/modify/");
                    }else{
                        $url->path("/object/$pid/modify/");
                    } 
                    $url->query({'state' => 'A'});
                    my $tx = $ua->post($url);
                    if (my $res = $tx->success) {
                          my $res_data =  $tx->res->json;
                    }else {
                         print "Error1:", Dumper($tx->error);
                         if($tx->res->json && exists($tx->res->json->{alerts})){
                              my $temp = $tx->res->json->{alerts};
                              my $temp2->{step} = 'object/pid/modify/status';
                              $temp2->{alerts} = $temp;
                              push @error, $temp2;
                              print 'Error2:', Dumper($tx->res->json->{alerts});
                         }else{
                              my $temp = $tx->error;
                              $temp->{step} = 'object/pid/modify/status';
                              push @error, $temp;
                              print 'Error3:', Dumper($tx->error);
                         }
                   } 
                   
                   # change owner
                    my $url6 = Mojo::URL->new;
                    $url6->scheme($scheme);
                    $url6->host($base[0]);
                    $url6->userinfo("$fedoraadminuser:$fedoraadminpass");
                    print Dumper("/object/$pid/modify change owner");
                    if(exists($base[1])){
                        $url6->path($base[1]."/object/$pid/modify/");
                    }else{
                        $url6->path("/object/$pid/modify/");
                    } 
                    $url6->query({'ownerid' => $data->{owner}});
                    my $tx6 = $ua->post($url6);
                    if (my $res = $tx6->success) {
                         my $res_data =  $tx6->res->json;
                    }else {
                         print "Error1:", Dumper($tx6->error);
                         if($tx6->res->json && exists($tx6->res->json->{alerts})){   
                              my $temp = $tx6->res->json->{alerts};
                              my $temp2->{step} = 'object/pid/modify/owner';
                              $temp2->{alerts} = $temp;
                              push @error, $temp2;
                              print 'Error2:', Dumper($tx6->res->json->{alerts});
                         }else{
                              my $temp = $tx6->error;
                              $temp->{step} = 'object/pid/modify/owner';
                              push @error, $temp;
                              print 'Error3:', Dumper($tx6->error);
                         }
                   } 
            
                    # add new_pid to bags mongoDb collection
                    my $id = MongoDB::OID->new($data->{_id}->{value});
                    $collectionJobs->update({"_id" => $id} , {'$set' => {'new_pid' => $pid}});
            }
     }
     my $result;
     $result->{error} = \@error;
     $result->{pid} = $pid;
     
     
     
     return $result;
     
}


sub getOctets($){

     my $old_pid = shift;
     
     my $result;
     $result->{result} = undef;
     
     my $url = Mojo::URL->new;
     $url->scheme($scheme);
     $url->host($base[0]);
     $url->userinfo("$fedoraadminuser:$fedoraadminpass");
     print Dumper("/object/$old_pid/octets/");
     if(exists($base[1])){
         $url->path($base[1]."/object/$old_pid/octets/");
     }else{
         $url->path("/object/$old_pid/octets/");
     }    
     my $tx = $ua->get($url);
     if (my $res = $tx->success) {
         my $res_data =  $tx->res->json;
                my $tmp = $tx->res->content->asset;
                $result->{result} = $tx->res->content->asset;
                return $result;
        }else {
          print "Error1:", Dumper($tx->error);
          if($tx->res->json && exists($tx->res->json->{alerts})){   
               print 'Error2:', Dumper($tx->res->json->{alerts});
               my $temp = $tx->res->json->{alerts};
               my $temp2->{step} = 'object/pid/octets';
               $temp2->{alerts} = $temp;
               push @{$result->{error}}, $temp2;
          }else{
               print 'Error3:', Dumper($tx->error);
               my $temp = $tx->error;
               $temp->{step} = 'object/pid/octets';
               push @{$result->{error}}, $temp;
          }
            
          return $result;
     } 

}




1;