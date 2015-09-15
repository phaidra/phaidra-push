package PhaidraPush::Controller::Main;

use strict;
use warnings;
use diagnostics;
use v5.10;
use utf8;
use Mojo::JSON qw(encode_json);
use base 'Mojolicious::Controller';

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

  my $res = { alerts => [], status => 200 };

  $self->app->log->debug($self->app->dumper($objects));

  $self->render(json => $res, status => $res->{status} );
};

1;
