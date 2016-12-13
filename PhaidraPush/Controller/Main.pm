package PhaidraPush::Controller::Main;

use strict;
use warnings;
use Data::Dumper;

use diagnostics;
use v5.10;
use utf8;
use Mojo::JSON qw(encode_json);
use base 'Mojolicious::Controller';
use PhaidraPush::Model::Email;


use base 'MojoX::Session::Store';
use Mango 0.24;
__PACKAGE__->attr('mango'); 

sub home {
  my $self = shift;  

  unless($self->flash('redirect_to')){
    # if no redirect was set, reload the current url
    $self->flash({redirect_to => $self->url_for('/')});
  }

  if($self->stash('opensignin')){
    $self->flash({opensignin => 1});
  }

  my $init_data = { 
    current_user => $self->current_user,
    phaidratemp_baseurl => $self->app->config->{'phaidra-temp'}->{baseurl},
    phaidra_baseurl => $self->app->config->{'phaidra'}->{baseurl}
  };
  $self->stash(init_data => encode_json($init_data));
  $self->stash(init_data_perl => $init_data);

  $self->render('index');
};


sub push {
  my $self = shift;
  my $objects = $self->req->json;

  my $res = { alerts => [], status => 201 };

  
  $self->app->log->debug('$objects123:',$self->app->dumper($objects));
  #$self->app->log->debug(@{$objects}[0]);

  my $entwDataSet = $self->mango_bagger->db->collection('jobs')->insert({
                                                                           'old_pid' => $objects, 
                                                                           'type' => 'push', 
                                                                           'owner' => $self->current_user->{username}, 
                                                                           'ts' => time, 
                                                                            #'status' => 'scheduled',
                                                                           'status' => 'new', 
                                                                           'agent' => 'push_agent',
                                                                           'origin_instance' => $self->app->config->{'phaidra-temp'}->{id},
                                                                           'project' => 'phaidra-push',
                                                                           'ingest_instance' => $self->app->config->{phaidra}->{id},
                                                                           'notify_user_on_success' => 1,
                                                                           'user_notified' => 0
                                                                         });
  
  
  my $credetials;
  $credetials->{username}     = $self->app->config->{'directory_user'}->{username};
  $credetials->{password}     = $self->app->config->{'directory_user'}->{password};
  my $Email = PhaidraPush::Model::Email->new;
  my $emailConf =  $self->app->config->{'email'};
  my $myEmail = $Email->getEmail($self,  $self->app->config->{'phaidra'}->{apibaseurl}, $credetials, $self->current_user->{username});

  my $r = $Email->send_email(
                             $self, 
                             $self->app->config->{'phaidra'}->{apibaseurl}, 
                             $credetials, 
                             $emailConf, 
                             #@{$objects}[0], 
                             $objects,
                             $self->current_user->{username}, 
                             'en',
                             $myEmail
                            );
  
  $self->render('index');
};

1;
