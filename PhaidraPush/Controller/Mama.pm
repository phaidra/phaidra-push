package PhaidraPush::Controller::Mama;

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

  my $init_data = { current_user => $self->current_user };
  $self->stash(init_data => encode_json($init_data));
  $self->stash(init_data_perl => $init_data);

  $self->render('home');
};


1;
