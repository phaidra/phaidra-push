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
my $filenameAgent = '/home/michal/Documents/code/area42/user/mf/phaidra-push/lib/jobs_agent_phaidra_entw.json';
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
    host     =>     $config->{mongodb_phaidrapush}->{host}, 
    port     =>     $config->{mongodb_phaidrapush}->{port}, 
    username =>     $config->{phaidra}->{mongodb}->{username},
    password =>     $config->{phaidra}->{mongodb}->{password},
    db_name  =>     $config->{phaidra}->{mongodb}->{database}
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


sub getMetadata($);
sub getOctetsFileExtensionAndMimetype($);
sub getCModel($);
sub sendEmailToOwner($);
sub jobIsComplete($);


##################################################################
##################################################################
############          Main                    ####################
##################################################################
##################################################################

while(1){
   sleep(5);
   print "Start of the while loop!\n";
   my $dataSetPU = $collectionJobs->find({'agent' => 'push_agent' });
   while (my $push_agent = $dataSetPU->next) {
           print 'id:',Dumper($push_agent->{_id}->{value}), "\n";
           print 'status:',Dumper($push_agent->{status}), "\n";
           my $id = MongoDB::OID->new($push_agent->{_id}->{value});
           if($push_agent->{status} eq 'new'){
                my @bagsNode; 
                my $errorOccurred = 0;
                my @error;
                foreach my $mypid (@{$push_agent->{old_pid}}){
                        my $cmodel_result    = getCModel($mypid);
                        my $dataExt_result      = getOctetsFileExtensionAndMimetype($mypid);
                        print '$dataExt_result:', Dumper($dataExt_result);
                        my $metadata_result = getMetadata($mypid);;
                        
                        my $metadata;
                        if(defined $metadata_result->{error}){
                               print 'error metadata', "\n";
                               push @error, $metadata_result->{error};
                               $errorOccurred = 1;
                        }else{
                               $metadata = $metadata_result->{result};
                        }
                        
                        my $cmodel;
                        print '$cmodel_result:', Dumper($cmodel_result);
                        if(defined $cmodel_result->{error}){
                               print 'error $cmodel', "\n";
                               push @error, $cmodel_result->{error};
                               $errorOccurred = 1;
                        }else{
                               $cmodel = $cmodel_result->{result};
                        }
                        print '$cmodel:', Dumper($cmodel);
                        
                        my $mimeType;
                        my $dataExt;
                        if(defined $dataExt_result->{error}){
                               print 'error $dataExt', "\n";
                               push @error, $dataExt_result->{error};
                               $errorOccurred = 1;
                        }else{
                               $dataExt = $dataExt_result->{result};
                               $mimeType  = $dataExt->{mimetype};
                        }
                        print 'error:',Dumper(\@error);
                        if((scalar @error) eq 0){
                                my $bagID     = $collectionBags->insert_one({
                                                       metadata_response    => $metadata,
                                                       ts          => time,
                                                       owner       => $push_agent->{owner},
                                                       status      => 'new',
                                                       type        => $push_agent->{type},
                                                       mimetype    => $mimeType,
                                                       cmodel      => $cmodel,
                                                       origin_instance => $push_agent->{origin_instance},
                                                       job_id      => $push_agent->{_id}->{value},
                                                       old_pid     => $mypid
                                                    });
                                my $bagNode;
                                $bagNode->{bad_id} = $bagID->{inserted_id}->{value};
                                $bagNode->{old_pid} = $mypid;
                                push @bagsNode, $bagNode;
                        }else{
         
                        }
                }
                my $idJob = MongoDB::OID->new($push_agent->{_id}->{value});
                if($errorOccurred){
                        $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'error', 'errors' => \@error, 'time' => time}});
                }else{
                        $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'bags_created', 'time' => time}});
                }
                # add bags to Jobs collection
                $collectionJobs->update({"_id" => $idJob} , {'$set' => {'bags' => \@bagsNode}});
           }
           #send email if job complete
           if($push_agent->{status} eq 'bags_created'){
                   my $jobIsComplete = 1;
                   foreach my $bag (@{$push_agent->{bags}}){
                           if( !(defined $bag->{old_pid} && defined $bag->{new_pid}) ){
                                  $jobIsComplete = 0;
                           }
                   }
                   print '$jobIsComplete:',$jobIsComplete, "\n";
                   if($jobIsComplete){
                         my $emailResult = sendEmailToOwner($push_agent->{bags});
                         print '$emailResult:',Dumper($emailResult);
                         my $idJob = MongoDB::OID->new($push_agent->{_id}->{value});
                         if(defined $emailResult->{status} && $emailResult->{status} eq 1){
                                  print "aaaa\n";
                                  $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'bag_created__email_sent'}});
                         }else{
                                  print "bbb\n";
                                  $collectionJobs->update({"_id" => $idJob} , {'$set' => {'status' => 'bag_created__email_sending_error'}});
                                  my $dataJobs = $collectionJobs->find_one({'_id' => $idJob });
                                  push @{$dataJobs->{errors}}, $emailResult->{error};
                                  $collectionJobs->update({"_id" => $idJob} , {'$set' => {'errors' => $dataJobs->{errors} }});
                         }
                   }
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


sub sendEmailToOwner($){

      my $bags = shift;
      
      print 'sending email:',Dumper($bags);

      my $email = $config_agent->{email};
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
      foreach my $mybag (@{$bags}){
            push @pids, $mybag->{new_pid};
      }
      my %emaildata;
      $emaildata{pids} = \@pids;
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
      $options{INCLUDE_PATH} = $config_agent->{template_include_path};
       
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
               print 'Email sent!',"\n";
               $result->{status} = 1;
               return $result;
        }
        
}


sub getCModel($){
 
     my $pid = shift;
    
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
     print 'getCModel $url:', $url,"\n";
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
          my $result->{result} = $result_cmodel;
          return $result;

        }else {
          print "Error1:", Dumper($tx->error);
          if($tx->res->json && exists($tx->res->json->{alerts})){
               print 'Error2:', Dumper($tx->res->json->{alerts}), Dumper($tx->code);
               my $error;
               $error->{error} = $tx->res->json->{alerts};
               $error->{error}->{step} = 'search/triples/';
               $error->{error}->{old_pid} = $pid;
               return $error;
          }else{
               print 'Error3:', Dumper($tx->error);
               my $error;
               $error->{error} = $tx->error;
               $error->{error}->{step} = 'search/triples/';
               $error->{error}->{old_pid} = $pid;
               return $error;
          }
     }

}




sub getMetadata($){

     my $pid = shift;
     
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
     print 'getMetadata $url:', $url,"\n";
     my $tx = $ua->get($url);
     if (my $res = $tx->success) {
          my $res_data;        
          $res_data = $tx->res->json;
          # because of special characters
          my $json = encode_json($res_data);
          utf8::decode($json);
          $res_data = decode_json($json);
          my $result;
          $result->{result} = $res_data;
          return $result;
          
        }else {
          print "Error1:", Dumper($tx->error);
          if($tx->res->json && exists($tx->res->json->{alerts})){
               print 'Error2:', Dumper($tx->res->json->{alerts}), Dumper($tx->code);
               my $error;
               $error->{error} = $tx->res->json->{alerts};
               $error->{error}->{step} = 'object/pid/metadata/';
               $error->{error}->{old_pid} = $pid;
               return $error;
          }else{
               print 'Error3:', Dumper($tx->error);
               my $error;
               $error->{error} = $tx->error;
               $error->{error}->{step} = 'object/pid/metadata/';
               $error->{error}->{old_pid} = $pid;
               return $error;
          }
        }

}


sub getOctetsFileExtensionAndMimetype($){

    my $pid = shift;
    
     my $url = Mojo::URL->new;
     $url->scheme($scheme);
     $url->host($base[0]);
     $url->userinfo("$fedoraadminuser:$fedoraadminpass");
     if(exists($base[1])){
         $url->path($base[1]."/object/$pid/techinfo");
     }else{
         $url->path("/object/$pid/techinfo");
     }
     $url->query({'format' => 'xml'});
     #print 'getOctetsFileExtension $url:', $url,"\n";
     my $tx = $ua->get($url);
     if (my $res = $tx->success) {
             my $result;
             $result->{mimetype} = $tx->res->dom->at('mimetype')->text;
             $result->{filetype} = $tx->res->dom->at('filetype')->text;
             my $result2;
             #print 'getOctetsFileExtensionAndMimetype $tx->res:', Dumper($tx->res);
             print 'getOctetsFileExtensionAndMimetype:', Dumper($result);
             $result2->{result} = $result;
             return $result2;
     }else {
          print "Error1:", Dumper($tx->error);
          if($tx->res->json && exists($tx->res->json->{alerts})){   
               print 'Error2:', Dumper($tx->res->json->{alerts}), Dumper($tx->code);
               my $error;
               $error->{error} = $tx->res->json->{alerts};
               $error->{error}->{step} = 'object/pid/techinfo/';
               $error->{error}->{old_pid} = $pid;
               return $error;
          }else{
               print 'Error3:', Dumper($tx->error);
               my $error;
               $error->{error} = $tx->error;
               $error->{error}->{step} = 'object/pid/techinfo/';
               $error->{error}->{old_pid} = $pid;
               return $error;
          }
     } 

}


1;