package Schedule::LongSteps::Storage::Memory;

use Moose;
extends qw/Schedule::LongSteps::Storage/;

use DateTime;

use Log::Any qw/$log/;

=head1 NAME

Schedule::LongSteps::Storage::DBIxClass - DBIx::Class based storage.

=head1 SYNOPSIS

  my $storage = Schedule::LongSteps::Storage::Memory->new();

Then build and use a L<Schedule::LongSteps> object:

  my $long_steps = Schedule::LongSteps->new({ storage => $storage });

  ...


=cut

has 'processes' => ( is => 'ro', isa => 'ArrayRef[Schedule::LongSteps::Storage::Memory::Process]', default => sub{ []; } );

=head2 prepare_due_processes

See L<Schedule::LongSteps::Storage>

=cut

sub prepare_due_processes{
    my ($self, $options) = @_;
    $options ||= {};

    my $now = DateTime->now();
    my $uuid = $options->{run_id} || $self->uuid()->create_str();
    $log->info("Creating batch ID $uuid");

    foreach my $process ( @{ $self->processes() } ){
        if( $process->run_at()
                && !$process->run_id()
                && ( DateTime->compare( $process->run_at(),  $now ) <= 0 ) ){
            $process->update({
                run_id => $uuid,
                status => 'running'
            });
        }
    }
    return $self->retrieve_processes_by_run_id($uuid);
}

=head2 retrieve_processes_by_run_id

See L<Schedule::LongSteps::Storage>

=cut

sub retrieve_processes_by_run_id {
    my ($self, $run_id) = @_;
    return () unless $run_id;
    $log->info('Retrieving processes with '.$run_id );
    return grep {($_->run_id() // '') eq $run_id } @{ $self->processes() };
}

=head2 find_process

See L<Schedule::LongSteps::Storage>

=cut

sub find_process{
    my ($self, $pid) = @_;
    $log->trace("Looking up process ID=$pid");
    my ( $match ) = grep{ $_->id() == $pid } @{$self->processes()};
    my $log_message = $match ? "Found: $match" : "Could not find a process for $pid";
    $log->trace($log_message);
    return $match;
}


=head2 create_process

See L<Schedule::LongSteps::Storage>

=cut

sub create_process{
    my ($self, $process_properties) = @_;
    my $process = Schedule::LongSteps::Storage::Memory::Process->new($process_properties);
    push @{$self->processes()} , $process;
    return $process;
}

__PACKAGE__->meta->make_immutable();

package Schedule::LongSteps::Storage::Memory::Process;

use Moose;

use DateTime;

my $IDSEQUENCE = 0;

has 'id' => ( is => 'ro', isa => 'Int', default => sub{ ++$IDSEQUENCE ; } );
has 'process_class' => ( is => 'rw', isa => 'Str', required => 1); # rw only for test. Should not changed ever.
has 'status' => ( is => 'rw', isa => 'Str', default => 'pending' );
has 'what' => ( is => 'rw' ,  isa => 'Str', required => 1);
has 'run_at' => ( is => 'rw', isa => 'Maybe[DateTime]', default => sub{ undef; } );
has 'run_id' => ( is => 'rw', isa => 'Maybe[Str]', default => sub{ undef; } );
has 'state' => ( is => 'rw', default => sub{ {}; });
has 'error' => ( is => 'rw', isa => 'Maybe[Str]', default => sub{ undef; } );

sub update{
    my ($self, $update_properties) = @_;
    defined($update_properties) or ( $update_properties = {} );

    # use Data::Dumper;
    # warn "Updating with ".Dumper($update_properties);

    while( my ( $key, $value ) = each %{$update_properties} ){
        $self->$key( $value );
    }
}

__PACKAGE__->meta->make_immutable();
