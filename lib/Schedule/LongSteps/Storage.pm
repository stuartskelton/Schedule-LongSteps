package Schedule::LongSteps::Storage;

use Moose;

=head1 NAME

Schedule::LongSteps::Storage - An abstract storage class for steps

=cut

use Data::UUID;

has 'uuid' => ( is => 'ro', isa => 'Data::UUID', lazy_build => 1);

sub _build_uuid{
    my ($self) = @_;
    return Data::UUID->new();
}



=head2 prepare_due_processes

Mark the processes that are due to run as 'running' and
returns an array of stored processes. A second options hashref parameter can be passed in,
please check the storage class for any specific requirements.

However all storage classes can take a 'run_id' as a hashref key and the value will be
used instead of the default uuid.

Users: Note that this is meant to be used by L<Schedule::LongSteps>, and not intended
to be called directly.

Implementors: You will have to implement this method should you wish to implement
a new process storage backend.

=cut

sub prepare_due_processes{
    my ($self, $options) = @_;
    die "Please implement this in $self";
}


=head2 retrieve_processes_by_run_id

Retrive procceses for a given run_id

=cut

sub retrieve_processes_by_run_id{
    my ($self, $run_id) = @_;
    die "Please implement this in $self";
}

=head2 create_process

Creates and return a new stored process.

=cut

sub create_process{
    my ($self, $properties) = @_;
    die "Please implement this in $self";
}

=head2 find_process

Returns a stored process based on the given ID, or undef if no such thing exists.

Usage:

 my $stored_process = $this->find_process( $pid );

=cut

sub find_process{
    my ($self, $pid) = @_;
    die "Please implement this in $self";
}


=head2 update_process

Updates the given stored process (as returned by 'find_process')
with the given properties.

Usage:

 $this->update_process( $process , { run_at => DateTime->now(), .. } );

=cut

sub update_process{
    my ($self, $process, $properties) = @_;
    $process->update( $properties );
}

__PACKAGE__->meta()->make_immutable();
