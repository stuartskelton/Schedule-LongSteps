package Schedule::LongSteps::Storage::DBIxClass;

use Moose;
extends qw/Schedule::LongSteps::Storage/;

use DateTime;
use Log::Any qw/$log/;
use Scope::Guard;
use Action::Retry;

has 'schema' => ( is => 'ro', isa => 'DBIx::Class::Schema', required => 1);
has 'resultset_name' => ( is => 'ro', isa => 'Str', required => 1);

has 'limit_per_tick' => ( is => 'ro', isa => 'Int', default => 50 );

sub _get_resultset{
    my ($self) = @_;
    return $self->schema()->resultset($self->resultset_name());
}

around [ 'prepare_due_processes', 'create_process' ] => sub{
    my ($orig, $self, @rest ) = @_;

    # Transfer the current autocommit nature of the DBH
    # as a transation might have been created on this DBH outside
    # of this schema. A transaction on DBI sets AutoCommit to false
    # on the DBH. transaction_depth is just a boolean on the storage.

    # First restore transaction depth as it was.
    my $pre_transaction_depth = $self->schema()->storage()->transaction_depth();
    my $guard = Scope::Guard->new(
        sub{
            $log->trace("Restoring transaction_depth = $pre_transaction_depth");
            $self->schema()->storage()->transaction_depth( $pre_transaction_depth );
        });

    my $current_transaction_depth = $self->schema()->storage()->dbh()->{AutoCommit} ? 0 : 1;
    $log->trace("Setting transaction_depth as NOT dbh AutoCommit = ".$current_transaction_depth);
    $self->schema()->storage()->transaction_depth( $current_transaction_depth );
    return $self->$orig( @rest );
};


=head1 NAME

Schedule::LongSteps::Storage::DBIxClass - DBIx::Class based storage.

=head1 SYNOPSIS

First instantiate a storage with your L<DBIx::Class::Schema> and the name
of the resultset that represent the stored process:

  my $storage = Schedule::LongSteps::Storage::DBIxClass->new({
                   schema => $dbic_schema,
                   resultset_name => 'LongstepsProcess'
                });

Then build and use a L<Schedule::LongSteps> object:

  my $long_steps = Schedule::LongSteps->new({ storage => $storage });

  ...

=head1 ATTRIBUTES

=over

=item schema

You DBIx::Class::Schema. Mandatory.

=item resultset_name

The name of the resultset holding the processes in your Schema. See section 'RESULTSET REQUIREMENTS'. Mandatory.

=item limit_per_tick

The maximum number of processes that will actually run each time you
call $longsteps->run_due_processes(). Use that to control how long it takes to run
a single call to $longsteps->run_due_processes().

Note that you can have an arbitrary number of processes all doing $longsteps->run_due_processes() AT THE SAME TIME.

This will ensure that no process step is run more than one time.

Default to 50.

=back

=head1 RESULTSET REQUIREMENTS

The resultset to use with this storage MUST contain the following columns, constraints and indices:

=over

=item id

A unique primary key auto incrementable identifier

=item process_class

A VARCHAR long enough to hold  your L<Schedule::LongSteps::Process> class names. NOT NULL.

=item what

A VARCHAR long enough to hold the name of one of your steps. Can be NULL.

=item status

A VARCHAR(50) NOT NULL, defaults to 'pending'

=item run_at

A Datetime (or timestamp with timezone in PgSQL). Will hold a UTC Timezoned date of the next run. Default to NULL.

Please index this so it is fast to select a range.

=item run_id

A CHAR or VARCHAR (at least 36). Default to NULL.

Please index this so it is fast to select rows with a matching run_id

=item state

A Reasonably long TEXT field (or JSON field in supporting databases) capable of holding
a JSON dump of pure Perl data. NOT NULL.

You HAVE to implement inflating and deflating yourself. See L<DBIx::Class::InflateColumn::Serializer::JSON>
or similar techniques.

See t/fullblown.t for a full blown working example.

=item error

A reasonably long TEXT field capable of holding a full stack trace in case something goes wrong. Defaults to NULL.

=back

=cut

=head2 prepare_due_processes

See L<Schedule::LongSteps::Storage::DBIxClass>

=cut

sub prepare_due_processes{
    my ($self, $options) = @_;
    $options ||= {};

    my $now = DateTime->now();
    my $rs = $self->_get_resultset();
    my $dtf = $self->schema()->storage()->datetime_parser();

    my $uuid = $options->{run_id} || $self->uuid()->create_str();
    $log->info("Creating batch ID $uuid");


    # Note that we do not use the SELECT FOR UPDATE technique here.
    # Instead this generates a single UPDATE statement like this one:
    # UPDATE longsteps_process SET run_id = ?, status = ? WHERE ( id IN ( SELECT me.id FROM longsteps_process me WHERE ( ( run_at <= ? AND run_id IS NULL ) ) LIMIT ? ) )
    my $stuff = sub{
        $rs->search({
            run_at => { '<=' => $dtf->format_datetime( $now ) },
            run_id => undef,
        }, {
            rows => $self->limit_per_tick(),
        } )
            ->update({
                run_id => $uuid,
                status => 'running'
            });
    };
    $stuff->();

    # And return them as individual results.
    return $self->retrieve_processes_by_run_id($uuid);
}

=head2 retrieve_processes_by_run_id

See L<Schedule::LongSteps::Storage>

=cut

sub retrieve_processes_by_run_id {
    my ($self, $run_id) = @_;
    return () unless $run_id;
    $log->info('Retrieving processes with '.$run_id );
    return $self->_get_resultset()->search({
        run_id => $run_id // '',
    })->all();
}

=head2 create_process

See L<Schedule::LongSteps::Storage>

This override adds retrying in case of deadlock detection.

=cut

sub create_process{
    my ($self, $process_properties) = @_;
    return $self->_retry_transaction(
        sub{
            return $self->_get_resultset()->create($process_properties);
        });
}

=head2 find_process

See L<Schedule::LongSteps::Storage>

=cut

sub find_process{
    my ($self, $process_id) = @_;
    return $self->_get_resultset()->find({ id => $process_id });
}

=head2 update_process

Overrides L<Schedule::LongSteps::Storage#update_process> to add
some retrying in case of DB deadlock detection.

=cut

override 'update_process' => sub{
    my ($self, $process, $properties) = @_;
    return $self->_retry_transaction( sub{
                                          $log->trace("Attempting to update process ".$process->id());
                                          $process->update( $properties );
                                      } );
};

sub _retry_transaction{
    my ($self, $code) = @_;

    my $retry = Action::Retry->new(
        attempt_code => $code,
        retry_if_code => sub{
            my $exception = $_[0];
            # The driver tells us to retry the transaction.
            # For instance: https://dev.mysql.com/doc/refman/5.6/en/innodb-deadlocks-handling.html

            # Note that if this is false, then the Action::Retry code
            # will set $@ to the last error and return whatever the code has returned (most
            # probably undef in this case.
            # This is managed by the error testing after the call to 'run'
            return !! ( ( $exception || '' )  =~ m/try restarting transaction/ );
        },
        strategy => 'Fibonacci',
    );
    my $ret = $retry->run();
    if( my $err = $@ ){
        confess($err);
    }
    return $ret;
}

__PACKAGE__->meta->make_immutable();
