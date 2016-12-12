#!/usr/bin/env perl

package Phaidra_push_jobs_agent;

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


=head1
  
  Phaidra_push jobs_agent, Create 'Bags' for ingesting(by bagger agent) from 'Jobs'(created by phaidra-push ui)
 
=cut


sub new {
        my $class = shift;
   
        my $phaidraPushConfig = shift;
        my $phaidraOriginConfing = shift;
        my $phaidraPushJobAgentConfig = shift;
             
        if (not defined $phaidraPushConfig){
                print 'phaidraPushConfig not defined!';
                exit (0);
        }
        if (not defined $phaidraOriginConfing){
                print 'Origin phaidraConfing is not defined!';
                exit (0);
        }
        if (not defined $phaidraPushJobAgentConfig){
                print 'phaidraPushJobAgentConfig not defined!';
                exit (0);
        }
             
             
        my $phaidra_push_text = do {
        open(my $json_fh, "<:encoding(UTF-8)", $phaidraPushConfig)
             or die("Can't open \$phaidraPushConfig\": $!\n");
             local $/;
           <$json_fh>
        };

        my $json   = JSON->new;
        my $phaidra_push_config = $json->decode($phaidra_push_text);

        #read jobs_agent_phaidra_entw.json
        my $json_text_agent = do {
        open(my $json_fh_agent, "<:encoding(UTF-8)", $phaidraPushJobAgentConfig)
             or die("Can't open \$phaidraPushJobAgentConfig\": $!\n");
         local $/;
         <$json_fh_agent>
        };

        
        my $config_phaidra_push_job_agent = $json->decode($json_text_agent);
        
        my $client_phaidra_push = MongoDB::Connection->new(
           host     =>     $phaidra_push_config->{phaidra}->{mongodb}->{host}, 
           port     =>     $phaidra_push_config->{phaidra}->{mongodb}->{port}, 
           username =>     $phaidra_push_config->{phaidra}->{mongodb}->{username},
           password =>     $phaidra_push_config->{phaidra}->{mongodb}->{password},
           db_name  =>     $phaidra_push_config->{phaidra}->{mongodb}->{database}
        );

        my $collectionJobs = $client_phaidra_push->ns( $phaidra_push_config->{phaidra}->{mongodb}->{database}.'.'.'jobs');
        my $collectionBags = $client_phaidra_push->ns( $phaidra_push_config->{phaidra}->{mongodb}->{database}.'.'.'bags');
        

        my $configPhaidra     = YAML::Syck::LoadFile( $phaidraOriginConfing );
        my $fedoraadminuser   = $configPhaidra->{"fedoraadminuser"};
        my $fedoraadminpass   = $configPhaidra->{"fedoraadminpass"};
        my $phaidraapibaseurl = $configPhaidra->{"phaidraapibaseurl"};


        $phaidraapibaseurl =~ s/https:\/\///g;

        my @base = split('/',$phaidraapibaseurl);
  
        my $self = {};
        
        $self->{originInstanceBaseUrl}         = $phaidra_push_config->{'phaidra-temp'}->{baseurl};
        $self->{config_phaidra_push_job_agent} = $config_phaidra_push_job_agent;
        
        
        $self->{collectionJobs}                = $collectionJobs;
        $self->{collectionBags}                = $collectionBags;
        
        $self->{configPhaidra}     = $configPhaidra;
        $self->{fedoraadminuser}   = $fedoraadminuser;
        $self->{fedoraadminpass}   = $fedoraadminpass;
        $self->{phaidraapibaseurl} = $phaidraapibaseurl;
        $self->{base}              = \@base;
        $self->{ua}                = Mojo::UserAgent->new;
        $self->{scheme}            = 'https';
        
        
        bless($self, $class);
        return $self;
}


sub run {

   my $self = shift;
    
   print "Start of phaidra_push_jobs_agent.pl!\n";
   my $collectionJobs = $self->{collectionJobs};
   my $collectionBags = $self->{collectionBags};
   my $dataSetPU = $collectionJobs->find({'agent' => 'push_agent' })->sort( { ts => 1 } );
   while (my $push_agent = $dataSetPU->next) {
           my $id = MongoDB::OID->new($push_agent->{_id}->{value});
           if($push_agent->{status} eq 'new'){
                my $idJob = MongoDB::OID->new($push_agent->{_id}->{value});
                $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'processing', 'time' => time }});
                my @jobAlerts;
                my @bagsNode; 
                foreach my $mypid (@{$push_agent->{old_pid}}){
                        my $resultAlerts= { alerts => [], status => 200 , ts => time};
                        my $cmodel_result       = $self->getCModel($mypid, $resultAlerts);
                        my $metadata_result     = $self->getMetadata($mypid, $resultAlerts);
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
                         my $emailResult = $self->sendEmail($push_agent->{bags}, 'job_successful');
                         if(defined $emailResult->{status} && $emailResult->{status} eq 1){
                                   $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'finished__email_sent'}});
                         }else{
                                  my $dataJobs = $collectionJobs->find_one({'_id' => $idJob });
                                  push @{$dataJobs->{errors}}, $emailResult->{error};
                                  $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'finished__email_sending_error',
                                                                                          'errors' => $dataJobs->{errors} }});
                         }
                   }else{
                         my $emailResult = $self->sendEmail($push_agent->{bags}, 'job_error');
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
   print "End of the phaidra_push_jobs_agent.pl!\n";
}





sub sendEmail {

      my $self = shift;
      my $bags = shift;
      my $type = shift;
      
      my $config_agent = $self->{'config_phaidra_push_job_agent'};
      
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


sub getCModel {

     my $self = shift;
     my $pid = shift;
     my $resultAlerts = shift;
    
     my @base = @{$self->{base}};
     my $scheme = $self->{scheme};
     my $fedoraadminuser = $self->{fedoraadminuser};
     my $fedoraadminpass = $self->{fedoraadminpass};
     my $ua = $self->{ua} ;
     
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
                $self->addFieldToAlerts($tx->res->json->{alerts}, '/search/triples/', 'step');
                $self->addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                $self->addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
                push @{$resultAlerts->{alerts}}, $tx->res->json->{alerts} 
          }

          return $result_cmodel;
      }else {
          my $error;
          if($tx->res->json && exists($tx->res->json->{alerts})){
               $resultAlerts->{status} = 500;
               if(@{$tx->res->json->{alerts}}){
                        if (ref($tx->error) eq "HASH") {
                            $self->addFieldToAlerts($tx->res->json->{alerts}, $tx->error->{code}, 'code');
                        }else{
                            $self->addFieldToAlerts($tx->res->json->{alerts}, $tx->error, 'code');
                        }
                        $self->addFieldToAlerts($tx->res->json->{alerts}, '/search/triples/', 'step');
                        $self->addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                        $self->addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
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

sub getMetadata {

     my $self = shift;
     my $pid = shift;
     my $resultAlerts = shift;
     
     
     my @base = @{$self->{base}};
     my $scheme = $self->{scheme};
     my $fedoraadminuser = $self->{fedoraadminuser};
     my $fedoraadminpass = $self->{fedoraadminpass};
     my $ua = $self->{ua} ;
     
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
          
          $res_data = $self->addReferenceNumber($res_data, $pid, $resultAlerts);
           
          if(@{$tx->res->json->{alerts}}){
                $self->addFieldToAlerts($tx->res->json->{alerts}, 'object/pid/metadata/', 'step');
                $self->addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                $self->addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
                push @{$resultAlerts->{alerts}}, $tx->res->json->{alerts};
          }
          return $res_data;
          
        }else {
          if($tx->res->json && exists($tx->res->json->{alerts})){
               $resultAlerts->{status} = 500;
               if(@{$tx->res->json->{alerts}}){
                        $self->addFieldToAlerts($tx->res->json->{alerts}, $tx->error->{code}, 'code');
                        $self->addFieldToAlerts($tx->res->json->{alerts}, '/object/pid/metadata/', 'step');
                        $self->addFieldToAlerts($tx->res->json->{alerts}, time, 'ts');
                        $self->addFieldToAlerts($tx->res->json->{alerts}, localtime, 'localtime');
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

sub addReferenceNumber {

     my $self = shift;
     my $metadata = shift;
     my $pid = shift;
     my $resultAlerts = shift;
     
     my $originInstanceBaseUrl = $self->{originInstanceBaseUrl};
     
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
                                 $metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children} = $self->arrayInsertAfterPosition($metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}, $idAfterToAdd, $referenceNumber);
                         }else{
                                 push @{$metadata->{metadata}->{uwmetadata}[$histkultIndex]->{children}}, $referenceNumber;
                         }
                   }
            }
     }
     
     return $metadata;
}


sub arrayInsertAfterPosition {

  my ($this, $inArray, $inPosition, $inElement) = @_;
  
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


sub addFieldToAlerts {

     my $self = shift;
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