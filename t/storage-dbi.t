#! perl -wt

use Test::More;

use DBI;
use Schedule::LongSteps::Storage::DBI;

eval "use DBD::SQLite";
plan skip_all => "DBD::SQLite is required for this test."
    if $@;


my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', undef, undef, {
    AutoCommit => 1,
    RaiseError => 1
});

ok( my $storage = Schedule::LongSteps::Storage::DBI->new({ get_dbh => sub{ return $dbh; }}) );

ok( $storage->deploy_sql() );
$dbh->do( $storage->deploy_sql() );

done_testing();

