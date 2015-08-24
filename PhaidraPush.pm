package PhaidraPush;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;
use Mojolicious::Plugin::I18N;
use Mojolicious::Plugin::Authentication;
use Mojolicious::Plugin::Session;
use Mojo::Loader;
use PhaidraPush::Model::Session::Store::Mongo;

# This method will run once at server start
sub startup {
  my $self = shift;

  my $config = $self->plugin( 'JSONConfig' => { file => 'PhaidraPush.json' } );
  $self->config($config);
  $self->mode($config->{mode});
  $self->secrets([$config->{secret}]);

  # init log
  $self->log(Mojo::Log->new(path => $config->{log_path}, level => $config->{log_level}));

  unless($config->{'phaidra'}){
    $self->log->error("Cannot find phaidra api config");
  }

  unless($config->{'phaidra-temp'}){
    $self->log->error("Cannot find phaidra-temp api config");
  }

    # init auth
    $self->plugin(authentication => {
    load_user => sub {
      my $self = shift;
      my $username  = shift;

      my $ldkey = 'logindata_'.$username;
      my $login_data = $self->app->chi->get($ldkey);

      unless($login_data){

        my $login_data;
        $self->app->log->debug("[cache miss] $username");

        my $url = Mojo::URL->new;
        $url->scheme('https');    
        $url->userinfo($self->app->config->{directory_user}->{username}.":".$self->app->config->{directory_user}->{password});
        my @base = split('/',$self->app->config->{phaidra}->{apibaseurl});
        $url->host($base[0]);
        $url->path($base[1]."/directory/user/$username/data") if exists($base[1]); 
        my $tx = $self->ua->get($url); 
        if (my $res = $tx->success) {
          $login_data =  $tx->res->json->{user_data};        
          $self->app->log->info("Loaded user: ".$self->app->dumper($login_data));
          $self->app->chi->set($ldkey, $login_data, '1 day');
          # keep this here, the set method may change the structure a bit so we better read it again
          $login_data = $self->app->chi->get($ldkey);        
        }else {
            
          my ($err, $code) = $tx->error;
          $code = 'Not defined code!' if not defined $code;
          $self->app->log->info("Loading logig data failed for user $username. Error code: $code, Error: $err");
          if($tx->res->json && exists($tx->res->json->{alerts})){   
            $self->stash({phaidra_auth_result => { alerts => $tx->res->json->{alerts}, status  =>  $code ? $code : 500 }});             
          }else{
            $self->stash({phaidra_auth_result => { alerts => [{ type => 'danger', msg => $err }], status  =>  $code ? $code : 500 }});
          }
            
          return undef;
        }  

      }else{
          $self->app->log->debug("[cache hit] $username");
      }
             
      return $login_data;
    },
    validate_user => sub {
      my ($self, $username, $password, $extradata) = @_;
      $self->app->log->info("Validating user: ".$username);
      
      my $url = Mojo::URL->new;
      $url->scheme('https');    
      $url->userinfo($username.":".$password);
      my @base = split('/',$self->app->config->{phaidra}->{apibaseurl});
      $url->host($base[0]);
      $url->path($base[1]."/signin") if exists($base[1]); 
        my $tx = $self->ua->get($url); 
    
      if (my $res = $tx->success) {
            
            # save token
            my $token = $tx->res->cookie($self->app->config->{authentication}->{token_cookie})->value;  
      
            my $session = $self->stash('mojox-session');
          $session->load;
          unless($session->sid){    
            $session->create;   
          } 
          $self->save_token($token);
            
            $self->app->log->info("User $username successfuly authenticated");
            $self->stash({phaidra_auth_result => { token => $token , alerts => $tx->res->json->{alerts}, status  =>  200 }});
            
            return $username;
       }else {
          
          my ($err, $code) = $tx->error;
          $code = 'Not defined code!' if not defined $code;
          $self->app->log->info("Authentication failed for user $username. Error code: $code, Error: $err");
          if($tx->res->json && exists($tx->res->json->{alerts})){   
            $self->stash({phaidra_auth_result => { alerts => $tx->res->json->{alerts}, status  =>  $code ? $code : 500 }});             
          }else{
            $self->stash({phaidra_auth_result => { alerts => [{ type => 'danger', msg => $err }], status  =>  $code ? $code : 500 }});
          }
          
          return undef;
      }       
      
    }
    
  });

  $self->attr(_mango_phaidrapush => sub { return Mango->new('mongodb://'.$config->{mongodb_phaidrapush}->{username}.':'.$config->{mongodb_phaidrapush}->{password}.'@'.$config->{mongodb_phaidrapush}->{host}.'/'.$config->{mongodb_phaidrapush}->{database}) });
  $self->helper(mango_phaidrapush => sub { return shift->app->_mango_phaidrapush});

  # we might possibly save a lot of data to session
  # so we are not going to use cookies, but a database instead
  $self->plugin(
    session => {
      stash_key     => 'mojox-session',
      store  => PhaidraPush::Model::Session::Store::Mongo->new(
        mango => $self->mango_phaidrapush,
            'log' => $self->log
        ),
      transport => MojoX::Session::Transport::Cookie->new(name => 'b_'.$config->{installation_id}),
      expires_delta => $config->{session_expiration},
      ip_match      => 1
    }
  );

  $self->hook('before_dispatch' => sub {
    my $self = shift;

    my $session = $self->stash('mojox-session');
    $session->load;
    if($session->sid){
      # we need mojox-session only for signed-in users
      if($self->signature_exists){
        $session->extend_expires;
        $session->flush;
      }else{
        # this will set expire on cookie as well as in store
        $session->expire;
        $session->flush;
      }
    }else{
      if($self->signature_exists){
        $session->create;
      }
    }

  });

  $self->hook('after_dispatch' => sub {
    my $self = shift;
    my $json = $self->res->json;
    if($json){
      if($json->{alerts}){
        if(scalar(@{$json->{alerts}}) > 0){
          $self->app->log->debug("Alerts:\n".$self->dumper($json->{alerts}));
        }
      }
    }
  });

  $self->sessions->default_expiration($config->{session_expiration});
  # 0 if the ui is not running on https, otherwise the cookies won't be sent and session won't work
  $self->sessions->secure($config->{secure_cookies});
  $self->sessions->cookie_name('a_'.$config->{installation_id});

    $self->helper(save_token => sub {
      my $self = shift;
    my $token = shift;

    my $session = $self->stash('mojox-session');
    $session->load;
    unless($session->sid){
      $session->create;
    }

    $session->data(token => $token);
    });

    $self->helper(load_token => sub {
      my $self = shift;

      my $session = $self->stash('mojox-session');
      $session->load;
      unless($session->sid){
        return undef;
      }

      return $session->data('token');
    });

    # init I18N
    $self->plugin(charset => {charset => 'utf8'});

    # init cache
    $self->plugin(CHI => {
      default => {
          driver		=> 'Memory',
          global => 1,
      },
    });

    # if we are proxied from base_apache/ui eg like
    # ProxyPass /ui http://localhost:3000/
    # then we have to add /ui/ to base of every req url
    # (set $config->{proxy_path} in config)
    if($config->{proxy_path}){
      $self->hook('before_dispatch' => sub {
    my $self = shift;
          push @{$self->req->url->base->path->trailing_slash(1)}, $config->{proxy_path};
      });
    }

    my $r = $self->routes;
    $r->namespaces(['PhaidraPush::Controller']);

    $r->route('')             ->via('get')   ->to('main#home');
    $r->route('signin') 			->via('get')   ->to('authentication#signin');
    $r->route('signout') 			->via('get')   ->to('authentication#signout');

    # if not authenticated, users will be redirected to login page
    my $auth = $r->under('/')->to('authentication#check');
    $auth->route('objects')   ->via('get')   ->to('proxy#search_owner');
    $auth->route('delete/:pid')   ->via('get')   ->to('proxy#delete_object');
    #$auth->route('push/:pid')   ->via('get')   ->to('main#push');

    return $self;
}

1;

__END__
