package Minion;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Config;
use Minion::Job;
use Minion::Worker;
use Mojo::Loader 'load_class';
use Mojo::Server;
use Scalar::Util 'weaken';

has app => sub { Mojo::Server->new->build_app('Mojo::HelloWorld') };
has 'backend';
has backoff => sub { \&_backoff };
has job_class     => 'Minion::Job';
has missing_after => 1800;
has remove_after  => 172800;
has tasks         => sub { {} };
has worker_class  => 'Minion::Worker';

our $VERSION = '6.06';

sub add_task { ($_[0]->tasks->{$_[1]} = $_[2]) and return $_[0] }

sub enqueue {
  my $self = shift;
  my $id   = $self->backend->enqueue(@_);
  $self->emit(enqueue => $id);
  return $id;
}

sub job {
  my ($self, $id) = @_;

  return undef unless my $job = $self->backend->job_info($id);
  return $self->job_class->new(
    args    => $job->{args},
    id      => $job->{id},
    minion  => $self,
    retries => $job->{retries},
    task    => $job->{task}
  );
}

sub new {
  my $self = shift->SUPER::new;

  my $class = 'Minion::Backend::' . shift;
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "$class" missing} if $e;

  $self->backend($class->new(@_));
  weaken $self->backend->minion($self)->{minion};

  return $self;
}

sub perform_jobs {
  my ($self, $options) = @_;
  my $worker = $self->worker;
  while (my $job = $worker->register->dequeue(0, $options)) { $job->perform }
  $worker->unregister;
}

sub repair { shift->_delegate('repair') }
sub reset  { shift->_delegate('reset') }

sub stats { shift->backend->stats }

sub worker {
  my $self = shift;

  # No fork emulation support
  croak 'Minion workers do not support fork emulation' if $Config{d_pseudofork};

  my $worker = $self->worker_class->new(minion => $self, @_);
  $self->emit(worker => $worker);
  return $worker;
}

sub _backoff { (shift()**4) + 15 }

sub _delegate {
  my ($self, $method) = @_;
  $self->backend->$method;
  return $self;
}

1;

=encoding utf8

=head1 NAME

Minion - Job queue

=head1 SYNOPSIS

  use Minion;

  # Connect to backend
  my $minion = Minion->new(Pg => 'postgresql://postgres@/test');

  # Add tasks
  $minion->add_task(something_slow => sub {
    my ($job, @args) = @_;
    sleep 5;
    say 'This is a background worker process.';
  });

  # Enqueue jobs
  $minion->enqueue(something_slow => ['foo', 'bar']);
  $minion->enqueue(something_slow => [1, 2, 3] => {priority => 5});

  # Perform jobs for testing
  $minion->enqueue(something_slow => ['foo', 'bar']);
  $minion->perform_jobs;

  # Build more sophisticated workers
  my $worker = $minion->repair->worker;
  while (int rand 2) {
    if (my $job = $worker->register->dequeue(5)) { $job->perform }
  }
  $worker->unregister;

=head1 DESCRIPTION

L<Minion> is a job queue for the L<Mojolicious|http://mojolicious.org> real-time
web framework, with support for multiple named queues, priorities, delayed jobs,
job dependencies, job results, retries with backoff, statistics, distributed
workers, parallel processing, autoscaling, remote control, resource leak
protection and multiple backends (such as
L<PostgreSQL|http://www.postgresql.org>).

Job queues allow you to process time and/or computationally intensive tasks in
background processes, outside of the request/response lifecycle. Among those
tasks you'll commonly find image resizing, spam filtering, HTTP downloads,
building tarballs, warming caches and basically everything else you can imagine
that's not super fast.

  use Mojolicious::Lite;

  plugin Minion => {Pg => 'postgresql://sri:s3cret@localhost/test'};

  # Slow task
  app->minion->add_task(poke_mojo => sub {
    my $job = shift;
    $job->app->ua->get('mojolicious.org');
    $job->app->log->debug('We have poked mojolicious.org for a visitor');
  });

  # Perform job in a background worker process
  get '/' => sub {
    my $c = shift;
    $c->minion->enqueue('poke_mojo');
    $c->render(text => 'We will poke mojolicious.org for you soon.');
  };

  app->start;

Background worker processes are usually started with the command
L<Minion::Command::minion::worker>, which becomes automatically available when
an application loads the plugin L<Mojolicious::Plugin::Minion>.

  $ ./myapp.pl minion worker

Jobs can be managed right from the command line with
L<Minion::Command::minion::job>.

  $ ./myapp.pl minion job

To manage background worker processes with systemd, you can use a unit
configuration file like this.

  [Unit]
  Description=My Mojolicious application workers
  After=postgresql.service

  [Service]
  Type=simple
  ExecStart=/home/sri/myapp/myapp.pl minion worker -m production
  KillMode=process

  [Install]
  WantedBy=multi-user.target

Every job can fail or succeed, but not get lost, the system is eventually
consistent and will preserve job results for as long as you like, depending on
L</"remove_after">. While individual workers can fail in the middle of
processing a job, the system will detect this and ensure that no job is left in
an uncertain state, depending on L</"missing_after">.

=head1 GROWING

And as your application grows, you can move tasks into application specific
plugins.

  package MyApp::Task::PokeMojo;
  use Mojo::Base 'Mojolicious::Plugin';

  sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(poke_mojo => sub {
      my $job = shift;
      $job->app->ua->get('mojolicious.org');
      $job->app->log->debug('We have poked mojolicious.org for a visitor');
    });
  }

  1;

Which are loaded like any other plugin from your application.

  # Mojolicious
  $app->plugin('MyApp::Task::PokeMojo');

  # Mojolicious::Lite
  plugin 'MyApp::Task::PokeMojo';

=head1 EVENTS

L<Minion> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 enqueue

  $minion->on(enqueue => sub {
    my ($minion, $id) = @_;
    ...
  });

Emitted after a job has been enqueued, in the process that enqueued it.

  $minion->on(enqueue => sub {
    my ($minion, $id) = @_;
    say "Job $id has been enqueued.";
  });

=head2 worker

  $minion->on(worker => sub {
    my ($minion, $worker) = @_;
    ...
  });

Emitted in the worker process after it has been created.

  $minion->on(worker => sub {
    my ($minion, $worker) = @_;
    my $id = $worker->id;
    say "Worker $$:$id started.";
  });

=head1 ATTRIBUTES

L<Minion> implements the following attributes.

=head2 app

  my $app = $minion->app;
  $minion = $minion->app(MyApp->new);

Application for job queue, defaults to a L<Mojo::HelloWorld> object.

=head2 backend

  my $backend = $minion->backend;
  $minion     = $minion->backend(Minion::Backend::Pg->new);

Backend, usually a L<Minion::Backend::Pg> object.

=head2 backoff

  my $cb  = $minion->backoff;
  $minion = $minion->backoff(sub {...});

A callback used to calculate the delay for automatically retried jobs, defaults
to C<(retries ** 4) + 15> (15, 16, 31, 96, 271, 640...), which means that
roughly C<25> attempts can be made in C<21> days.

  $minion->backoff(sub {
    my $retries = shift;
    return ($retries ** 4) + 15 + int(rand 30);
  });

=head2 job_class

  my $class = $minion->job_class;
  $minion   = $minion->job_class('MyApp::Job');

Class to be used by L</"job">, defaults to L<Minion::Job>. Note that
this class needs to have already been loaded before L</"job"> is called.

=head2 missing_after

  my $after = $minion->missing_after;
  $minion   = $minion->missing_after(172800);

Amount of time in seconds after which workers without a heartbeat will be
considered missing and removed from the registry by L</"repair">, defaults to
C<1800> (30 minutes).

=head2 remove_after

  my $after = $minion->remove_after;
  $minion   = $minion->remove_after(86400);

Amount of time in seconds after which jobs that have reached the state
C<finished> and have no unresolved dependencies will be removed automatically by
L</"repair">, defaults to C<172800> (2 days).

=head2 tasks

  my $tasks = $minion->tasks;
  $minion   = $minion->tasks({foo => sub {...}});

Registered tasks.

=head2 worker_class

  my $class = $minion->worker_class;
  $minion   = $minion->worker_class('MyApp::Worker');

Class to be used by L</"worker">, defaults to L<Minion::Worker>. Note that
this class needs to have already been loaded before L</"worker"> is called.

=head1 METHODS

L<Minion> inherits all methods from L<Mojo::EventEmitter> and implements the
following new ones.

=head2 add_task

  $minion = $minion->add_task(foo => sub {...});

Register a task.

  # Job with result
  $minion->add_task(add => sub {
    my ($job, $first, $second) = @_;
    $job->finish($first + $second);
  });
  my $id = $minion->enqueue(add => [1, 1]);
  my $result = $minion->job($id)->info->{result};

=head2 enqueue

  my $id = $minion->enqueue('foo');
  my $id = $minion->enqueue(foo => [@args]);
  my $id = $minion->enqueue(foo => [@args] => {priority => 1});

Enqueue a new job with C<inactive> state. Arguments get serialized by the
L</"backend"> (often with L<Mojo::JSON>), so you shouldn't send objects and be
careful with binary data, nested data structures with hash and array references
are fine though.

These options are currently available:

=over 2

=item attempts

  attempts => 25

Number of times performing this job will be attempted, with a delay based on
L</"backoff"> after the first attempt, defaults to C<1>.

=item delay

  delay => 10

Delay job for this many seconds (from now), defaults to C<0>.

=item parents

  parents => [$id1, $id2, $id3]

One or more existing jobs this job depends on, and that need to have
transitioned to the state C<finished> before it can be processed.

=item priority

  priority => 5

Job priority, defaults to C<0>. Jobs with a higher priority get performed first.

=item queue

  queue => 'important'

Queue to put job in, defaults to C<default>.

=back

=head2 job

  my $job = $minion->job($id);

Get a job object without making any changes to the actual job or
return C<undef> if job does not exist.
The object is based on L</"job_class"> (which is usually L<Minion::Job>).

  # Check job state
  my $state = $minion->job($id)->info->{state};

  # Get job result
  my $result = $minion->job($id)->info->{result};

=head2 new

  my $minion = Minion->new(Pg => 'postgresql://postgres@/test');

Construct a new L<Minion> object.

=head2 perform_jobs

  $minion->perform_jobs;
  $minion->perform_jobs({queues => ['important']});

Perform all jobs with a temporary worker, very useful for testing.

  # Longer version
  my $worker = $minion->worker;
  while (my $job = $worker->register->dequeue(0)) { $job->perform }
  $worker->unregister;

These options are currently available:

=over 2

=item queues

  queues => ['important']

One or more queues to dequeue jobs from, defaults to C<default>.

=back

=head2 repair

  $minion = $minion->repair;

Repair worker registry and job queue if necessary.

=head2 reset

  $minion = $minion->reset;

Reset job queue.

=head2 stats

  my $stats = $minion->stats;

Get statistics for jobs and workers.

  # Check idle workers
  my $idle = $minion->stats->{inactive_workers};

These fields are currently available:

=over 2

=item active_jobs

  active_jobs => 100

Number of jobs in C<active> state.

=item active_workers

  active_workers => 100

Number of workers that are currently processing a job.

=item delayed_jobs

  delayed_jobs => 100

Number of jobs in C<inactive> state that are scheduled to run at specific time
in the future or have unresolved dependencies. Note that this field is
EXPERIMENTAL and might change without warning!

=item enqueued_jobs

  enqueued_jobs => 100000

Rough estimate of how many jobs have ever been enqueued. Note that this field is
EXPERIMENTAL and might change without warning!

=item failed_jobs

  failed_jobs => 100

Number of jobs in C<failed> state.

=item finished_jobs

  finished_jobs => 100

Number of jobs in C<finished> state.

=item inactive_jobs

  inactive_jobs => 100

Number of jobs in C<inactive> state.

=item inactive_workers

  inactive_workers => 100

Number of workers that are currently not processing a job.

=back

=head2 worker

  my $worker = $minion->worker;

Build a worker object based on L</"worker_class">
(which is usually L<Minion::Worker>).

=head1 REFERENCE

This is the class hierarchy of the L<Minion> distribution.

=over 2

=item * L<Minion>

=item * L<Minion::Backend>

=over 2

=item * L<Minion::Backend::Pg>

=back

=item * L<Minion::Command::minion>

=item * L<Minion::Command::minion::job>

=item * L<Minion::Command::minion::worker>

=item * L<Minion::Job>

=item * L<Minion::Worker>

=item * L<Mojolicious::Plugin::Minion>

=back

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>.

=head1 CREDITS

In alphabetical order:

=over 2

Andrey Khozov

Brian Medley

Joel Berger

Paul Williams

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2017, Sebastian Riedel and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/kraih/minion>, L<Mojolicious::Guides>,
L<http://mojolicious.org>.

=cut
