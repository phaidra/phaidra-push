package PhaidraPush::Model::Email;

use strict;
use warnings;
use Data::Dumper;
use base qw/Mojo::Base/;
use MIME::Base64;
use MIME::Lite::TT::HTML;
use Email::Valid;



sub getEmail
{
        my ($self, $c, $baseurl, $config, $username)=@_;
       
        $username = lc($username);
        
        my $url = Mojo::URL->new;
        $url->userinfo($config->{username}.":".$config->{password});
        $url->scheme('https');
        my @base = split('/',$baseurl);
        $url->host($base[0]); 
        $url->path($base[1]."/directory/user/$username/email") if exists($base[1]);
       
        my $cred=encode_base64($config->{username}.':'.$config->{password});
        my $response = $c->ua->get($url,Authorization => "Basic $cred");
        if ($response->success) {
                $c->app->log->debug("getEmail success.", Dumper($response->res->json));
                return $response->res->json;
        }else {
                if(defined($response->res->json)){
                    if(exists($response->res->json->{alerts})) {
                               $c->app->log->debug("[$baseurl] [$username]: error getting email alerts: ". Dumper($response->res->json->{alerts}));
                               return; 
                    }else{
                              $c->app->log->debug("[$baseurl] [$username]: error getting: ".Dumper($response->res->json));
                              return; 
                    }
                }else{
                       $c->app->log->debug("[$baseurl] [$username]: error getting email error: ".Dumper($response->error));
                       return; 
                }
        }
}


sub send_email
{
        my ($self, $c, $baseurl, $config, $emailConf, $p, $username, $language, $emailHash) = @_;
        
        #print '$config:',Dumper($config);
        
        my $email = $emailHash->{email};
        $c->app->log->debug("send_email!!!",$baseurl, $p,$email);
        unless($username){
                $c->app->log->debug("[$baseurl] [$username]: email to user cannot be sent, username missing.");
                return; 
        }
        $c->app->log->debug("[$baseurl] [$username]: email: $email");
        
        unless(Email::Valid->address($email)){
                $c->app->log->debug("[$baseurl] [$username]: email to user cannot be sent, invalid email address: ",Dumper($email));
                return;
        }
        
        my %emaildata;

        $emaildata{pids} = $p;
        $emaildata{language} = $emailConf->{language};
        $emaildata{baseurl} = $baseurl;
        $emaildata{supportemail} = $emailConf->{supportemail};

        my $subject;
        if($language eq 'de'){
                $subject = "Phaidra-push - Redaktionelle Bearbeitung abgeschlossen";
        }else{
                $subject = "Phaidra-push - Submission process completed";
        }
        
        #$c->app->log->debug('emaildata11:',Dumper(\%emaildata));
        
        my %options; 
        $options{INCLUDE_PATH} = $emailConf->{template_include_path};

        $c->app->log->debug("send email1 ######");
        
        eval
        {
                $c->app->log->debug("send email2 ######");
                my $msg = MIME::Lite::TT::HTML->new(
                        From        => $emailConf->{From},
                        To          => $emailConf->{email},
                        Subject     => $subject,
                        Charset     => 'utf8',
                        Encoding    => 'quoted-printable',
                        Template    => { html => 'job_created.html.tt', text => 'job_created.txt.tt'},
                        TmplParams  => \%emaildata,
                        TmplOptions => \%options
                );

                $msg->send;
        };
        if($@)
        {
                #ERROR
                $c->app->log->debug('error:',$@);

        }
}





1;