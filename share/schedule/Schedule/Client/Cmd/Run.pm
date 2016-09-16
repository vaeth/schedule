# Schedule::Client::Cmd::Run.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Cmd::Run v7.5.0;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Client::Iterator;
use Schedule::Client::Runner;

# Global variables:

my $s;

#
# Functions
#

sub run_init {
	$s = &client_globals();
	$s->check_version();
	&args_init($s);
	&iterator_init($s);
	&runner_init($s)
}

sub run {
	&run_init();
	my ($runmode) = @_;
	&validate_args();
	return '' unless(&static_argv());
	my $send = $runmode;
	$send = 'run' if($runmode eq 'exec');
	$send .= "\c@";
	for my $a (@ARGV) {
		for(my $iter = Schedule::Client::Iterator->new($a, undef, 1);
			$iter->unfinished(); $iter->increase()) {
			return '' unless(&runner($send . $iter->current(),
				my $job, my $status, -1));
			if($job eq '0') {
				last unless($iter->cond_error());
				&set_exitstatus(1);
				next
			}
			if($status) {
				&set_exitstatus($status);
				return 1 if($runmode eq 'exec')
			}
		}
	}
	1
}

sub static_argv {
	my @new = ();
	my %know = ();
	my $last = undef;
	my $is_open = '';
	my $have_static = '';
	for my $a (@ARGV) {
		unless($a =~ s{^\/}{}) {
			push(@new, $a);
			next
		}
		for(my $iter = Schedule::Client::Iterator->new($a, \$last, \$is_open);
			$iter->unfinished(); $iter->increase()) {
			my $i = $iter->current();
			my $result = $know{$i};
			unless(defined($result)) {
				unless($have_static) {
					return '' unless($is_open || &openclient());
					$have_static = $is_open = 1
				}
				return '' unless(&client_send("unique\c@$i") &&
					&client_recv($result));
				$know{$i} = $result
			}
			if($result eq '0') {
				last unless($iter->cond_error());
				&set_exitstatus(1);
				next
			}
			push(@new, $result . "\c@" . $i . "\c@" . $a)
		}
	}
	return ((!$is_open) || &closeclient()) unless($have_static);
	@ARGV = @new;
	&client_send('close') && &closeclient()
}

1;
