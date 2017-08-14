#! perl -wt

use Test::More;
use Schedule::LongSteps;

my $do_break_stuff_fails = 1;
{

    package MyProcess;
    use Moose;
    extends qw/Schedule::LongSteps::Process/;

    use DateTime;

    sub build_first_step {
        my ($self) = @_;
        return $self->new_step(
            { what => 'do_setup_state_step', run_at => DateTime->now() } );
    }

    sub do_setup_state_step {
        my ($self) = @_;
        return $self->new_step(
            {
                what   => 'do_break_stuff',
                run_at => DateTime->now(),
                state =>
                  { %{ $self->state() }, n_tries => 10, sandwich => 'toast' }
            }
        );
    }

    sub revive_do_break_stuff {
        my ($self) = @_;
        return { %{ $self->state() }, n_tries => 0 }
    }


    sub do_break_stuff {
        my ($self) = @_;
        die 'something went wrong' if $self->state()->{n_tries} > 9 ;
        return $self->new_step(
            { what => 'do_final_step', run_at => DateTime->now() } );
    }

    sub do_final_step {
        my ($self) = @_;
        return $self->final_step( { state => { the => 'final', state => 1 } } );
    }
}

ok( my $long_steps = Schedule::LongSteps->new() );

ok(
    my $process = $long_steps->instantiate_process(
        'MyProcess', undef, { beef => 'saussage' }
    )
);
ok( $process->id() );

is( $process->what(), 'do_setup_state_step' );
is_deeply( $process->state(), { beef => 'saussage' } );

# Time to run!
ok( $long_steps->run_due_processes(), 'run set up state' );
ok( $long_steps->run_due_processes(), 'run do_break_stuff' );
is( $process->what(), 'do_break_stuff' );
like( $process->error(), qr(something went wrong), 'something did go wrong' );

# this should return undef, as there is no do_the_hoff
is( $long_steps->revive( $process->id(), 'do_the_hoff' ),
    undef, 'revive to an incorrect function' );

is( $long_steps->revive( $process->id() ), 1, 'Process was revived' );
is( $process->error(),  undef,    'revived process error was undef' );
is( $process->status(), "paused", 'revived process status is paused' );

ok( $long_steps->run_due_processes(), 'run the revived step' );

# And check the step properties have been
ok( $long_steps->run_due_processes(), 'run the final step' );
is_deeply( $process->state(), { the => 'final', state => 1 } );
is( $process->status(), 'terminated' );
is( $process->run_at(), undef );

# Check no due step have run again
ok( !$long_steps->run_due_processes() );

done_testing();
