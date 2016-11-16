#!/usr/bin/env perl

use utf8;
use strict;
use warnings;
use Data::Dumper;

use JSON;
use MongoDB;
use MongoDB::Connection;

use Mojo::Base 'Mojolicious';
use Mojo::ByteStream qw(b);
use YAML::Syck;
use Mojo::Asset::File;
use Email::Valid;
use MIME::Lite::TT::HTML;
use Encode qw(is_utf8 encode decode);



$ENV{MOJO_INACTIVITY_TIMEOUT} = 7200;
$ENV{MOJO_MAX_MESSAGE_SIZE} = 116777216;



=head1
  
  Usage perl bags_agent_phaidra_entw.pl /path/PhaidraPush.json path/phaidra.yml path/jobs_agent_phaidra_entw.json
 
=cut


my $filename = '/home/michal/Documents/code/area42/user/mf/phaidra-push/PhaidraPush.json';
#my $filename             = $ARGV[0];
my $phaidraConfingAdress = '/media/phaidra-entw_root/etc/phaidra.yml';
#my $phaidraConfingAdress = $ARGV[1];
my $filenameAgent = '/home/michal/Documents/code/area42/user/mf/phaidra-push/lib/PhaidraPushAgent/phaidraPushJobsAgent.json';
#my $filenameAgent        = $ARGV[2];

#read PhaidraPush.json
my $json_text = do {
   open(my $json_fh, "<:encoding(UTF-8)", $filename)
      or die("Can't open \$filename\": $!\n");
   local $/;
   <$json_fh>
};
my $json   = JSON->new;
my $config = $json->decode($json_text);

#read jobs_agent_phaidra_entw.json
my $json_text_agent = do {
   open(my $json_fh_agent, "<:encoding(UTF-8)", $filenameAgent)
      or die("Can't open \$filenameAgent\": $!\n");
   local $/;
   <$json_fh_agent>
};
my $json_agent   = JSON->new;
my $config_agent = $json_agent->decode($json_text_agent);


my $client = MongoDB::Connection->new(
    host     =>     $config->{phaidra}->{mongodb}->{host}, 
    port     =>     $config->{phaidra}->{mongodb}->{port}, 
    username =>     $config->{phaidra}->{mongodb}->{username},
    password =>     $config->{phaidra}->{mongodb}->{password},
    db_name  =>     $config->{phaidra}->{mongodb}->{database}
);

my $originInstanceBaseUrl = $config->{'phaidra-temp'}->{baseurl};


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


sub getMetadata($$);
sub getCModel($$);
sub sendEmail($$);
sub jobIsComplete($);
sub addFieldToAlerts($$$);
sub addReferenceNumber($$$);
sub arrayInsertAfterPosition($$$);

##################################################################
##################################################################
############          Main                    ####################
##################################################################
##################################################################


while(1){
   sleep(5);
   #print "Start of the while loop!\n";
   my $dataSetPU = $collectionJobs->find({'agent' => 'push_agent' });
   while (my $push_agent = $dataSetPU->next) {
           my $id = MongoDB::OID->new($push_agent->{_id}->{value});
           if($push_agent->{status} eq 'new'){
                my $idJob = MongoDB::OID->new($push_agent->{_id}->{value});
                $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'processing', 'time' => time }});
                my @jobAlerts;
                my @bagsNode; 
                foreach my $mypid (@{$push_agent->{old_pid}}){
                        my $resultAlerts= { alerts => [], status => 200 , ts => time};
                        my $cmodel_result       = getCModel($mypid, $resultAlerts);
                        my $metadata_result     = getMetadata($mypid, $resultAlerts);                     
                        my $bagID;
                        my $bagIDPhaidraPush = $push_agent->{origin_instance}.$mypid;
                        $bagIDPhaidraPush =~ s/\W//g;
                        my @jobs;
                        push @jobs, {'jobid' => $push_agent->{_id}->{value}};
                        if($resultAlerts->{status}  == 200){
                                $bagID     = $collectionBags->insert_one({
                                                       metadata    => $metadata_result->{metadata},
                                                       cmodel      => $cmodel_result,
                                                       ts          => time,
                                                       owner       => $push_agent->{owner},
                                                       status      => 'new',
                                                       type        => $push_agent->{type},
                                                       cmodel      => $cmodel_result,
                                                       origin_instance => $push_agent->{origin_instance},
                                                       jobs        => \@jobs,
                                                       project     => 'phaidra-push',
                                                       old_pid     => $mypid,
                                                       alerts      => $resultAlerts,
                                                       bagid       => $bagIDPhaidraPush
                                                    });
                                my $bagNode;
                                $bagNode->{bag_id} = $bagID->{inserted_id}->{value};
                                $bagNode->{old_pid} = $mypid;
                                push @bagsNode, $bagNode;
                        }else{
                             $bagID = $collectionBags->insert_one({
                                                           metadata => $metadata_result->{metadata},
                                                           cmodel      => $cmodel_result,
                                                           ts          => time,
                                                           owner       => $push_agent->{owner},
                                                           status      => 'error_creating_bag',
                                                           type        => $push_agent->{type},
                                                           cmodel      => $cmodel_result,
                                                           origin_instance => $push_agent->{origin_instance},
                                                           jobs        => \@jobs,
                                                           project     => 'phaidra-push',
                                                           old_pid     => $mypid,
                                                           alerts      => $resultAlerts,
                                                           bagid       => $bagIDPhaidraPush
                                                          });
                                my $bagNode;
                                $bagNode->{bag_id} = $bagID->inserted_id()->value();
                                $bagNode->{old_pid} = $mypid;
                                push @bagsNode, $bagNode;
                        }
                        my $bagAlerts;
                        $bagAlerts->{bag_id} = $bagID->inserted_id()->value();
                        $bagAlerts->{alerts} = $resultAlerts;
                        push @jobAlerts, $bagAlerts;
                }
                my $allBagsCreatedWhitoutError = 1;
                foreach my $alert (@jobAlerts){
                    if(defined $alert->{alerts}){
                          if(defined $alert->{alerts}->{status}){
                                if($alert->{alerts}->{status} ne 200){
                                      $allBagsCreatedWhitoutError = 0;
                                }
                          }
                    }
                }
                if(!$allBagsCreatedWhitoutError){
                        $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'error', 'errors' => \@jobAlerts, 'time' => time, 'bags' => \@bagsNode}});
                }else{
                        $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'scheduled', 'time' => time, 'bags' => \@bagsNode}});
                }
           }
           #send email if job complete
           if($push_agent->{status} eq 'finished' &&  $push_agent->{user_notified} ne 1){
                   my $jobIsSuccessfullyCompleted = 1;
                   foreach my $bag (@{$push_agent->{bags}}){
                           if( !defined $bag->{new_pid} ){
                                  $jobIsSuccessfullyCompleted = 0;
                           }
                   }
                   my $idJob = MongoDB::OID->new($push_agent->{_id}->{value});
                   if($jobIsSuccessfullyCompleted && $push_agent->{notify_user_on_success} == 1){
                         my $emailResult = sendEmail($push_agent->{bags}, 'job_successful');
                         if(defined $emailResult->{status} && $emailResult->{status} eq 1){
                                   $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'finished__email_sent'}});
                         }else{
                                  my $dataJobs = $collectionJobs->find_one({'_id' => $idJob });
                                  push @{$dataJobs->{errors}}, $emailResult->{error};
                                  $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'finished__email_sending_error',
                                                                                          'errors' => $dataJobs->{errors} }});
                         }
                   }else{
                         my $emailResult = sendEmail($push_agent->{bags}, 'job_error');
                         if(defined $emailResult->{status} && $emailResult->{status} eq 1){
                                   $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'not_complete__email_sent'}});
                         }else{
                                  my $dataJobs = $collectionJobs->find_one({'_id' => $idJob });
                                  push @{$dataJobs->{errors}}, $emailResult->{error};
                                  $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'not_complete__email_sending_error',  
                                                                                          'errors' => $dataJobs->{errors} }});
                         }
                   }
                   $collectionJobs->update({"_id" => $idJob} , {'$set' => {'user_notified' => 1}});
           }
   }
   print "End of the while loop\n";
}






sub jobIsComplete($){
    
     my $jobId = shift;
    
     my $jobIsComplete = 1;
     my $dataJobs = $collectionJobs->find_one({'_id' => $jobId, 'status' => 'bag_created' });
     foreach my $bag ({$dataJobs->{bags}}){
            if( !(defined $bag->{old_pid} && defined $bag->{new_pid}) ){
                  $jobIsComplete = 0;
            }
     }
  
     return $jobIsComplete;
}


sub sendEmail($$){

      my $bags = shift;
      my $type = shift;
      
      my $email;
      if($type eq 'job_successful'){
            $email = $config_agent->{email};
      }else{
            $email = $config_agent->{email_error};
      }
      
      
      my $language = $config_agent->{language};
      my $baseurl = $config_agent->{baseurl};
      my $supportemail = $config_agent->{supportemail};
      my $from = $config_agent->{From};
      my $instance = $config_agent->{instance};
      
      my $result;
      unless(Email::Valid->address($email)){
                print "[Email to user cannot be sent, invalid email address: ",Dumper($email);
                $result->{error} = "Email to user cannot be sent, invalid email address: ".$email;
                return $result;
      }

      my @pids;
      my @oldPids;
      foreach my $mybag (@{$bags}){
            push @pids, $mybag->{new_pid};
            push @oldPids, $mybag->{old_pid};
      }
      
      my %emaildata;
      $emaildata{pids} = \@pids;
      $emaildata{oldpids} = \@oldPids;
      $emaildata{language} = $language;
      $emaildata{baseurl} = $baseurl;
      $emaildata{supportemail} = $supportemail;
      $emaildata{instance} = $instance;
      
      my $subject;
      if($language eq 'de'){
                $subject = "Phaidra-push - Redaktionelle Bearbeitung abgeschlossen";
      }else{
                $subject = "Phaidra-push - Submission process completed";
      }
      
      my %options; 
      $options{INCLUDE_PATH} = $config_agent->{installation_dir}.$config_agent->{template_path};
       
       
        eval
        {
                my $msg = MIME::Lite::TT::HTML->new(
                        From        => $from,
                        To          => $email,
                        Subject     => $subject,
                        Charset     => 'utf8',
                        Encoding    => 'quoted-printable',
                        Template    => { html => 'job_complete.html.tt', text => 'job_complete.txt.tt'},
                        TmplParams  => \%emaildata,
                        TmplOptions => \%options
                );

                $msg->send;
        };
        if($@)
        {
                #ERROR
                print 'error:',$@;
                $result->{error} = 'error:'.$@;
                return $result;

        }else{
               $result->{status} = 1;
               return $result;
        }
        
}


sub getCModel($$){

     my $pid = shift;
     my $resultAlerts = shift;
    
    
     my $url = Mojo::URL->new;
     $url->scheme($scheme);
     $url->host($base[0]);
     $url->userinfo("$fedoraadminuser:$fedoraadminpass");
     if(exists($base[1])){
         $url->path($base[1]."/search/triples/");
     }else{
         $url->path("/search/triples/");
     }
     $url->query({'q' => "<info:fedora/$pid> <info:fedora/fedora-system:def/model#hasModel> * "});
     my $tx = $ua->get($url);
     if (my $res = $tx->success) {
          my $result_cmodel;
          my $res_data =  $tx->res->json;
          foreach my $cmodel (@{$res_data->{result}}){
                if( @$cmodel[2] =~ m/cmodel/){
                    my @w = split qw%/%,  @$cmodel[2];
                    chop $w[1];
                    $result_cmodel = $w[1];
                }
          }
          if(@{$tx->res->json->{alerts}}){
                addFieldToAlerts($tx->res->json->{alerts}, '/search/triples/', 'step');
                addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
                push @{$resultAlerts->{alerts}}, $tx->res->json->{alerts} 
          }

          return $result_cmodel;
      }else {
          my $error;
          if($tx->res->json && exists($tx->res->json->{alerts})){
               $resultAlerts->{status} = 500;
               if(@{$tx->res->json->{alerts}}){
                        if (ref($tx->error) eq "HASH") {
                            addFieldToAlerts($tx->res->json->{alerts}, $tx->error->{code}, 'code');
                        }else{
                            addFieldToAlerts($tx->res->json->{alerts}, $tx->error, 'code');
                        }
                        addFieldToAlerts($tx->res->json->{alerts}, '/search/triples/', 'step');
                        addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                        addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
               }
               push @{$resultAlerts->{alerts}}, $tx->res->json->{alerts};
               
               return;
          }else{
               my $alert = {};
               $resultAlerts->{status} = 500;
               $alert->{msg} = 'Error accessing search triples: /search/triples/';
               $alert->{type} = 'danger';
               $alert->{step} = '/search/triples/';
               $alert->{code} = 400;
               $alert->{ts} = time;
               $alert->{'localtime'} = localtime;
               my @alerts;
               push @alerts, $alert;
               push @{$resultAlerts->{alerts}}, \@alerts;

               return;
          }
     }

}

sub getMetadata($$){

     my $pid = shift;
     my $resultAlerts = shift;
     
     
     
     my $url = Mojo::URL->new;
     $url->scheme($scheme);
     $url->host($base[0]);
     $url->userinfo("$fedoraadminuser:$fedoraadminpass");
     if(exists($base[1])){
         $url->path($base[1]."/object/$pid/metadata/");
     }else{
         $url->path("/object/$pid/metadata/");
     }   
     $url->query({'mode' => 'full'});
     my $tx = $ua->get($url);
     if (my $res = $tx->success) {
          my $res_data;        
          $res_data = $tx->res->json;
          
          # because of special characters
          my $json = encode_json($res_data);
          utf8::decode($json);
          
          $res_data = decode_json($json);
          
          $res_data = addReferenceNumber($res_data, $pid, $resultAlerts);
           
          if(@{$tx->res->json->{alerts}}){
                addFieldToAlerts($tx->res->json->{alerts}, 'object/pid/metadata/', 'step');
                addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
                push @{$resultAlerts->{alerts}}, $tx->res->json->{alerts};
          }
          return $res_data;
          
        }else {
          if($tx->res->json && exists($tx->res->json->{alerts})){
               $resultAlerts->{status} = 500;
               if(@{$tx->res->json->{alerts}}){
                        addFieldToAlerts($tx->res->json->{alerts}, $tx->error->{code}, 'code');
                        addFieldToAlerts($tx->res->json->{alerts}, '/object/pid/metadata/', 'step');
                        addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                        addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
               }
               push @{$resultAlerts->{alerts}}, $tx->res->json->{alerts};
               
               return;
          }else{
               my $alert = {};
               $resultAlerts->{status} = 500;
               $alert->{msg} = 'Error reading metadata: object/pid/metadata/';
               $alert->{type} = 'danger';
               $alert->{step} = '/object/pid/metadata/';
               $alert->{code} = 400;
               $alert->{ts} = time;
               $alert->{'localtime'} = localtime;
               my @alerts;
               push @alerts, $alert;
               push @{$resultAlerts->{alerts}}, \@alerts;
               
               return;
          }
        }

}

sub addReferenceNumber($$$){

     my $metadata = shift;
     my $pid = shift;
     my $resultAlerts = shift;
    
     my $histkultExist = 0;
     if(defined $metadata->{metadata}){
            if(defined $metadata->{metadata}->{uwmetadata}){
                   my $metadataLenght = scalar @{ $metadata->{metadata}->{uwmetadata} };
                   my $i = 0;
                   my $histkultIndex;
                   foreach  ( @{$metadata->{metadata}->{uwmetadata}} ){
                         if($_->{xmlname} eq 'histkult' ){
                                $histkultExist = 1;
                                $histkultIndex = $i;
                         }
                         $i++;
                   }

                   my $histkult;
                   $histkult->{xmlname} = 'histkult';
                   $histkult->{xmlns} = 'http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0';
                   $histkult->{datatype} = 'Node';
                   $histkult->{children} = [];
     
                   my $referenceNumber;
                   $referenceNumber->{xmlname} = 'reference_number';
                   $referenceNumber->{xmlns} = 'http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0';
                   $referenceNumber->{datatype} = 'Node';
                   $referenceNumber->{children} = [];
     
                   my $reference;
                   $reference->{xmlname} = 'reference';
                   $reference->{xmlns} = 'http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0';
                   $reference->{ui_value} = 'http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0/voc_25/1562604'; 
                   $reference->{datatype} = 'Vocabulary';
     
                   my $number;
                   $number->{xmlname} = 'number';
                   $number->{xmlns} = 'http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0';
                   $number->{ui_value} = $originInstanceBaseUrl.'/'.$pid; 
                   $number->{datatype} = 'CharacterString';
     
                   push @{$referenceNumber->{children}}, $reference, $number;
                   
                   
                   
                   #add 'histkult' after 'organization' node
                   if(!$histkultExist){
                         push @{$histkult->{children}}, $referenceNumber;
                         my $index = 0;
                         my $idAfterToAdd;
                         foreach ( @{$metadata->{metadata}->{uwmetadata}} ){
                               if($_->{xmlname} eq 'rights' ){
                                       $idAfterToAdd = $index;
                               }
                               $index++;
                         }
                         $index = 0;
                         foreach ( @{$metadata->{metadata}->{uwmetadata}} ){
                               if($_->{xmlname} eq 'annotation' ){
                                       $idAfterToAdd = $index;
                               }
                               $index++;
                         }
                         $index = 0;
                         foreach ( @{$metadata->{metadata}->{uwmetadata}} ){
                               if($_->{xmlname} eq 'classification' ){
                                       $idAfterToAdd = $index;
                               }
                               $index++;
                         }
                         $index = 0;
                         foreach ( @{$metadata->{metadata}->{uwmetadata}} ){
                               if($_->{xmlname} eq 'organization' ){
                                       $idAfterToAdd = $index;
                               }
                               $index++;
                         }
                         if(defined $idAfterToAdd){
                               my @metadataTemp;
                               push @metadataTemp, @{$metadata->{metadata}->{uwmetadata}}[0..$idAfterToAdd], $histkult,  @{$metadata->{metadata}->{uwmetadata}}[$idAfterToAdd+1..$metadataLenght-1];
                               $metadata->{metadata}->{uwmetadata} = \@metadataTemp;
                         }else{
                              my $alert = {};
                              $resultAlerts->{status} = 500;
                              $alert->{msg}  = 'Error adding reference_number.';
                              $alert->{type} = 'warning';
                              $alert->{code} = 400;
                              $alert->{ts}   = time;
                              $alert->{'localtime'} = localtime;
                              my @alerts;
                              push @alerts, $alert;
                              push @{$resultAlerts->{alerts}}, \@alerts;
                         }
                   }else{
                         #add 'reference_number' after 'inscription' and 'dimensions' nodes
                         if($metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}){
                                 my $index = 0;
                                 my $idAfterToAdd = -1;
                                 foreach ( @{$metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}} ){
                                      if($_->{xmlname} eq 'inscription' ){
                                            $idAfterToAdd = $index;
                                      }
                                      $index++;
                                 }
                                 $index = 0;
                                 foreach ( @{$metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}} ){
                                      if($_->{xmlname} eq 'dimensions' ){
                                            $idAfterToAdd = $index;
                                      }
                                      $index++;
                                 }
                                 $metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children} = arrayInsertAfterPosition($metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}, $idAfterToAdd, $referenceNumber);
                         }else{
                                 push @{$metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}}, $referenceNumber;
                         }
                   }
            }
     }
     
     return $metadata;
}


sub arrayInsertAfterPosition($$$)
{
  my ($inArray, $inPosition, $inElement) = @_;
  my @res         = ();
  my @after       = ();
  my $arrayLength = int @{$inArray};

  if ($inPosition < 0) { @after = @{$inArray}; }
  else {
         if ($inPosition >= $arrayLength)    { $inPosition = $arrayLength - 1; }
         if ($inPosition < $arrayLength - 1) { @after = @{$inArray}[($inPosition+1)..($arrayLength-1)]; }
       }

  push (@res, @{$inArray}[0..$inPosition],
              $inElement,
              @after);

  return \@res;
}


sub addFieldToAlerts($$$){

     my $alerts = shift;
     my $fieldValue = shift;
     my $fieldName = shift;
     
     if(@{$alerts}){
         foreach my $alert (@{$alerts}){
                 $alert->{$fieldName} = $fieldValue;
         }
     }
     return $alerts;
}


1;