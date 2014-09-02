# Schedule::Client::Cmd::Parallel.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Cmd::Parallel;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Client::Iterator;
use Schedule::Client::Runner;

our $VERSION = '5.0';

# Global variables:

my $s;

#
# Functions
#

sub parallel_init {
	$s = &client_globals();
	$s->check_version();
	&args_init($s);
	&iterator_init($s);
	&runner_init($s)
}

sub parallel {
	&parallel_init();
	my ($waiting) = @_;
	&validate_args();
	return '' unless(&openclient());
	my %unique_ids = ();
	my $last = undef;
	for my $a (@ARGV) {
		for(my $iter = Schedule::Client::Iterator->new($a, \$last);
			$iter->unfinished(); $iter->increase()) {
			return '' unless(&runner("bg\c@" . $iter->current(),
				my $job, my $stat));
			if($job eq '0') {
				last unless($iter->cond_error());
				&set_exitstatus(1);
				next
			}
			next unless($waiting);
			if($stat eq '') {
				$unique_ids{$job} = undef
			} elsif($stat) {
				&set_exitstatus($stat)
			}
		}
	}
	&client_send('close');
	return '' unless(&closeclient());
	return 1 unless($waiting);
	if(!$s->did_alpha()) {
		my $ret = $s->exec_alpha();
		exit($ret) if($ret);
		$s->forking()
	}
	for my $id (keys(%unique_ids)) {
		return '' unless(&runner("wait\c@$id", my $job, my $stat, 1));
		&set_exitstatus($stat) if(($job ne '0') && $stat)
	}
	1
}

'EOF'
