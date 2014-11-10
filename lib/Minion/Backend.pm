package Minion::Backend;
use Mojo::Base -base;

use Carp 'croak';
use Sys::Hostname 'hostname';

has 'minion';

sub dequeue      { croak 'Method "dequeue" not implemented by subclass' }
sub enqueue      { croak 'Method "enqueue" not implemented by subclass' }
sub fail_job     { croak 'Method "fail_job" not implemented by subclass' }
sub finish_job   { croak 'Method "finish_job" not implemented by subclass' }
sub job_info     { croak 'Method "job_info" not implemented by subclass' }
sub list_jobs    { croak 'Method "list_jobs" not implemented by subclass' }
sub list_workers { croak 'Method "list_workers" not implemented by subclass' }

sub register_worker {
  croak 'Method "register_worker" not implemented by subclass';
}

sub remove_job { croak 'Method "remove_job" not implemented by subclass' }
sub repair     { croak 'Method "repair" not implemented by subclass' }
sub reset      { croak 'Method "reset" not implemented by subclass' }
sub retry_job  { croak 'Method "retry_job" not implemented by subclass' }
sub stats      { croak 'Method "stats" not implemented by subclass' }

sub unregister_worker {
  croak 'Method "unregister_worker" not implemented by subclass';
}

sub worker_info { croak 'Method "worker_info" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Minion::Backend - Backend base class

=head1 SYNOPSIS

  package Minion::Backend::MyBackend;
  use Mojo::Base 'Minion::Backend';

  sub dequeue           {...}
  sub enqueue           {...}
  sub fail_job          {...}
  sub finish_job        {...}
  sub job_info          {...}
  sub list_jobs         {...}
  sub list_workers      {...}
  sub register_worker   {...}
  sub remove_job        {...}
  sub repair            {...}
  sub reset             {...}
  sub retry_job         {...}
  sub stats             {...}
  sub unregister_worker {...}
  sub worker_info       {...}

=head1 DESCRIPTION

L<Minion::Backend> is an abstract base class for L<Minion> backends.

=head1 ATTRIBUTES

L<Minion::Backend> implements the following attributes.

=head2 minion

  my $minion = $backend->minion;
  $backend   = $backend->minion(Minion->new);

L<Minion> object this backend belongs to.

=head1 METHODS

L<Minion::Backend> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 dequeue

  my $job_info = $backend->dequeue($worker_id, 0.5);

Wait for job, dequeue it and transition from C<inactive> to C<active> state or
return C<undef> if queue was empty. Meant to be overloaded in a subclass.

=head2 enqueue

  my $job_id = $backend->enqueue('foo');
  my $job_id = $backend->enqueue(foo => [@args]);
  my $job_id = $backend->enqueue(foo => [@args] => {priority => 1});

Enqueue a new job with C<inactive> state. Meant to be overloaded in a
subclass.

These options are currently available:

=over 2

=item delay

  delay => 10

Delay job for this many seconds from now.

=item priority

  priority => 5

Job priority, defaults to C<0>.

=back

=head2 fail_job

  my $bool = $backend->fail_job($job_id);
  my $bool = $backend->fail_job($job_id, 'Something went wrong!');
  my $bool = $backend->fail_job($job_id, {msg => 'Something went wrong!'});

Transition from C<active> to C<failed> state. Meant to be overloaded in a
subclass.

=head2 finish_job

  my $bool = $backend->finish_job($job_id);
  my $bool = $backend->finish_job($job_id, 'All went well!');
  my $bool = $backend->finish_job($job_id, {msg => 'All went well!'});

Transition from C<active> to C<finished> state. Meant to be overloaded in a
subclass.

=head2 job_info

  my $job_info = $backend->job_info($job_id);

Get information about a job or return C<undef> if job does not exist. Meant to
be overloaded in a subclass.

=head2 list_jobs

  my $batch = $backend->list_jobs($offset, $limit);
  my $batch = $backend->list_jobs($offset, $limit, {state => 'inactive'});

Returns the same information as L</"job_info"> but in batches. Meant to be
overloaded in a subclass.

These options are currently available:

=over 2

=item state

  state => 'inactive'

List only jobs in this state.

=item task

  task => 'test'

List only jobs for this task.

=back

=head2 list_workers

  my $batch = $backend->list_workers($offset, $limit);

Returns the same information as L</"worker_info"> but in batches. Meant to be
overloaded in a subclass.

=head2 register_worker

  my $worker_id = $backend->register_worker;

Register worker. Meant to be overloaded in a subclass.

=head2 remove_job

  my $bool = $backend->remove_job($job_id);

Remove C<failed>, C<finished> or C<inactive> job from queue. Meant to be
overloaded in a subclass.

=head2 repair

  $backend->repair;

Repair worker registry and job queue if necessary. Meant to be overloaded in a
subclass.

=head2 reset

  $backend->reset;

Reset job queue. Meant to be overloaded in a subclass.

=head2 retry_job

  my $bool = $backend->retry_job($job_id);

Transition from C<failed> or C<finished> state back to C<inactive>. Meant to
be overloaded in a subclass.

=head2 stats

  my $stats = $backend->stats;

Get statistics for jobs and workers. Meant to be overloaded in a subclass.

=head2 unregister_worker

  $backend->unregister_worker($worker_id);

Unregister worker. Meant to be overloaded in a subclass.

=head2 worker_info

  my $worker_info = $backend->worker_info($worker_id);

Get information about a worker or return C<undef> if worker does not exist.
Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Minion>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
