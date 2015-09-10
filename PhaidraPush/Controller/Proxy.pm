package PhaidraPush::Controller::Proxy;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);


sub search {
    my $self = shift;  	 
    
    my $username = $self->current_user->{username};

    my $instance = $self->param('instance');
    
    my $url = Mojo::URL->new;
	$url->scheme('https');		
	my @base = split('/', $self->app->config->{$instance}->{apibaseurl});

	$url->host($base[0]);
	if(exists($base[1])){
		$url->path($base[1]."/search/owner/$username");
	}else{
		$url->path("/search/owner/$username");
	}
		    
	my %params;
	if(defined($self->param('q'))){
		$params{q} = $self->param('q');
	}
	if(defined($self->param('from'))){
		$params{from} = $self->param('from');
	}
	if(defined($self->param('limit'))){
		$params{limit} = $self->param('limit');
	}
	if(defined($self->param('sort'))){
		$params{'sort'} = $self->param('sort');
	}
	if(defined($self->param('reverse'))){
		$params{'reverse'} = $self->param('reverse');
	}
	if(defined($self->param('fields'))){	
		my @fields = $self->param('fields');	
		$params{'fields'} = \@fields;
	}
    $url->query(\%params);
	
	my $temp_token = $self->load_token;
	
  	$self->ua->get($url => sub { 	
  		my ($ua, $tx) = @_;

	  	if (my $res = $tx->success) {
	  		$self->render(json => $res->json, status => 200 );
	  	}else {
		 	my ($err, $code) = $tx->error;
		 	if($tx->res->json){	  
			  	if(exists($tx->res->json->{alerts})) {
				 	$self->render(json => { alerts => $tx->res->json->{alerts} }, status =>  $code ? $code : 500);
				 }else{
				  	$self->render(json => { alerts => [{ type => 'danger', msg => $err }] }, status =>  $code ? $code : 500);
				  	
				 }
		 	}
		}
		
  	});	
    
}

sub delete_object {
    my $self = shift;  	 
    my $pid = $self->stash('pid');

    my $url = Mojo::URL->new;
	$url->scheme('https');		
	my @base = split('/', $self->app->config->{'phaidra-temp'}->{apibaseurl});

	$url->host($base[0]);
	if(exists($base[1])){
		$url->path($base[1]."/object/$pid");
	}else{
		$url->path("/object/$pid");
	}		    
	
	my $temp_token = $self->load_token;
	$self->app->log->debug('using token: '.$temp_token);
  	$self->ua->delete($url => {$self->app->config->{authentication}->{phaidra_api_token_header} => $temp_token} => sub { 	
  		my ($ua, $tx) = @_;

	  	if (my $res = $tx->success) {
	  		$self->render(json => $res->json, status => 200 );
	  	}else {
		 	my ($err, $code) = $tx->error;
		 	if($tx->res->json){	  
			  	if(exists($tx->res->json->{alerts})) {
				 	$self->render(json => { alerts => $tx->res->json->{alerts} }, status =>  $code ? $code : 500);
				 }else{
				  	$self->render(json => { alerts => [{ type => 'danger', msg => $err }] }, status =>  $code ? $code : 500);
				  	
				 }
		 	}
		}
		
  	});	
    
}

1;