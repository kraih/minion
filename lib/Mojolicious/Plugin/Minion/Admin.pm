package Mojolicious::Plugin::Minion::Admin;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::File 'path';

sub register {
  my ($self, $app, $config) = @_;

  # Config
  my $prefix = $config->{route} // $app->routes->any('/minion');
  $prefix->to(return_to => $config->{return_to} // '/');

  # Static files
  my $resources = path(__FILE__)->sibling('resources');
  push @{$app->static->paths}, $resources->child('public')->to_string;

  # Templates
  push @{$app->renderer->paths}, $resources->child('templates')->to_string;

  # Routes
  $prefix->get('/')->to(template => 'minion/dashboard', format => 'html')
    ->name('minion_dashboard');
  $prefix->get('/stats' => \&_stats)->name('minion_stats');
  $prefix->get('/jobs'  => \&_list_jobs)->name('minion_jobs');
  $prefix->patch('/jobs' => \&_manage_jobs)->name('minion_manage_jobs');
  $prefix->get('/locks' => \&_list_locks)->name('minion_locks');
  $prefix->delete('/locks' => \&_unlock)->name('minion_unlock');
  $prefix->get('/workers' => \&_list_workers)->name('minion_workers');
}

sub _list_jobs {
  my $c = shift;

  my $validation = $c->validation;
  $validation->optional('id');
  $validation->optional('limit')->num;
  $validation->optional('offset')->num;
  $validation->optional('queue');
  $validation->optional('state')->in(qw(active failed finished inactive));
  $validation->optional('task');
  my $options = {};
  $options->{$_} = $validation->param($_) for qw(queue state task);
  $options->{ids} = $validation->every_param('id')
    if $validation->is_valid('id');
  my $limit  = $validation->param('limit')  || 10;
  my $offset = $validation->param('offset') || 0;

  my $results = $c->minion->backend->list_jobs($offset, $limit, $options);
  $c->render(
    'minion/jobs',
    format => 'html',
    jobs   => $results->{jobs},
    total  => $results->{total},
    limit  => $limit,
    offset => $offset
  );
}

sub _list_locks {
  my $c = shift;

  my $validation = $c->validation;
  $validation->optional('limit')->num;
  $validation->optional('offset')->num;
  $validation->optional('name');
  my $options = {name => $validation->param('name')};
  my $limit  = $validation->param('limit')  || 10;
  my $offset = $validation->param('offset') || 0;

  my $results = $c->minion->backend->list_locks($offset, $limit, $options);
  $c->render(
    'minion/locks',
    format => 'html',
    locks  => $results->{locks},
    total  => $results->{total},
    limit  => $limit,
    offset => $offset
  );
}

sub _list_workers {
  my $c = shift;

  my $validation = $c->validation;
  $validation->optional('id');
  $validation->optional('limit')->num;
  $validation->optional('offset')->num;
  my $limit  = $validation->param('limit')  || 10;
  my $offset = $validation->param('offset') || 0;
  my $options = {};
  $options->{ids} = $validation->every_param('id')
    if $validation->is_valid('id');

  my $results = $c->minion->backend->list_workers($offset, $limit, $options);
  $c->render(
    'minion/workers',
    format  => 'html',
    workers => $results->{workers},
    total   => $results->{total},
    limit   => $limit,
    offset  => $offset
  );
}

sub _manage_jobs {
  my $c = shift;

  my $validation = $c->validation;
  $validation->required('id');
  $validation->required('do')->in('remove', 'retry', 'stop');

  $c->redirect_to('minion_jobs') if $validation->has_error;

  my $minion = $c->minion;
  my $ids    = $validation->every_param('id');
  my $do     = $validation->param('do');
  if ($do eq 'retry') {
    my $fail = grep { $minion->job($_)->retry ? () : 1 } @$ids;
    if   ($fail) { $c->flash(danger  => "Couldn't retry all jobs.") }
    else         { $c->flash(success => 'All selected jobs retried.') }
  }
  elsif ($do eq 'remove') {
    my $fail = grep { $minion->job($_)->remove ? () : 1 } @$ids;
    if   ($fail) { $c->flash(danger  => "Couldn't remove all jobs.") }
    else         { $c->flash(success => 'All selected jobs removed.') }
  }
  elsif ($do eq 'stop') {
    $minion->broadcast(stop => [$_]) for @$ids;
    $c->flash(info => 'Trying to stop all selected jobs.');
  }

  $c->redirect_to($c->url_for('minion_jobs')->query(id => $ids));
}

sub _stats {
  my $c = shift;
  $c->render(json => $c->minion->stats);
}

sub _unlock {
  my $c = shift;

  my $validation = $c->validation;
  $validation->required('name');

  $c->redirect_to('minion_locks') if $validation->has_error;

  my $names  = $validation->every_param('name');
  my $minion = $c->minion;
  $minion->unlock($_) for @$names;
  $c->flash(success => 'All selected named locks released.');

  $c->redirect_to('minion_locks');
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Minion::Admin - Admin UI

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Minion::Admin');

  # Mojolicious::Lite
  plugin 'Minion::Admin';

  # Secure access to the admin ui with Basic authentication
  my $under = $self->routes->under('/minion' =>sub {
    my $c = shift;
    return 1 if $c->req->url->to_abs->userinfo eq 'Bender:rocks';
    $c->res->headers->www_authenticate('Basic');
    $c->render(text => 'Authentication required!', status => 401);
    return undef;
  });
  $self->plugin('Minion::Admin' => {route => $under});

=head1 DESCRIPTION

L<Mojolicious::Plugin::Minion::Admin> is a L<Mojolicious> plugin providing an
admin ui for the L<Minion> job queue.

=head1 OPTIONS

L<Mojolicious::Plugin::Minion::Admin> supports the following options.

=head2 return_to

  # Mojolicious::Lite
  plugin 'Minion::Admin' => {return_to => 'some_route'};

Name of route or path to retrurn to when leaving the admin ui, defaults to C</>.

=head2 route

  # Mojolicious::Lite
  plugin 'Minion::Admin' => {route => app->routes->any('/admin')};

L<Mojolicious::Routes::Route> object to attach the admin ui to, defaults to
generating a new one with the prefix C</minion>.

=head1 METHODS

L<Mojolicious::Plugin::Minion::Admin> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Minion>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
