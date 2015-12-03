package Schedule::LongSteps::Storage::DBI;

use Moose;
extends qw/Schedule::LongSteps::Storage/;

use DBI::Const::GetInfoType;

=head1 NAME

Schedule::LongSteps::Storage::DBI - Plain DBI based storage.

=head2 SYNOPSIS

 my $storage = Schedule::LongSteps::Storage::DBI->new({ get_dbh => sub{ ... return a valid dbh } });

=cut

has 'get_dbh' => ( is => 'ro', isa => 'CodeRef', required => 1 );

=head2 prepare_due_steps

See L<Schedule::LongSteps::Storage>

=cut

sub prepare_due_steps{
    my ($self) = @_;
    my $dbh = $self->get_dbh()->();

    # We want run_at lower than now and status 'paused'

    my $select_sql = q/
SELECT id, status, what, run_at, state
FROM longsteps_step
WHERE run_at < ? AND status = ?/;

    # TODO.
}


=head2 deploy_sql

Returns the SQL statement required to deploy this feature in your database.

TODO: Document what the table looks like to support all types of DBs.

=cut

{
    my %DEPLOY_SQL = (
        SQLite =>
            q/CREATE TABLE longsteps_step( id INTEGER PRIMARY KEY AUTOINCREMENT,
                                           status TEXT NOT NULL DEFAULT 'pending',
                                           what TEXT NOT NULL,
                                           run_at TEXT DEFAULT NULL,
                                           state TEXT NOT NULL DEFAULT '{}'
)
/
    );

    sub deploy_sql{
        my ($self) = @_;
        my $db_name = $self->get_dbh()->()->get_info( $GetInfoType{SQL_DBMS_NAME} );
        return $DEPLOY_SQL{$db_name} || confess("No Deployment sql for DB '$db_name'. Read the doc and create such a table yourself maybe?");
    }
}


__PACKAGE__->meta->make_immutable();
