# Schedule::Client::Cmd::Cancel.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Cmd::Cancel;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Client::Iterator;

our $VERSION = '4.0';

# Global variables:

my $s;

#
# Functions
#

sub cancel_init {
	$s = &client_globals();
	$s->check_version();
	&args_init($s);
	&iterator_init($s)
}

sub cancel {
	&cancel_init();
	my ($cancel) = @_;
	&validate_args();
	my $last = undef;
	my $is_open = '';
	for my $a (@ARGV) {
		for(my $iter = Schedule::Client::Iterator->new($a, \$last, \$is_open);
			$iter->unfinished(); $iter->increase()) {
			return '' unless($is_open || &openclient());
			$is_open = 1;
			my $reply;
			return '' unless(&client_send("cancel\c@$cancel\c@" .
				$iter->current()) && &client_recv($reply));
			$reply =~ s{^([^\c@]*)\c@?}{};
			my $job = $1;
			if($job eq '0') {
				last unless($iter->cond_error());
				&set_exitstatus(1);
				next
			}
			next unless($reply);
			&set_exitstatus(1);
			next if($s->quiet());
			my $jobtext = $iter->current(1);
			$jobtext .= (' (' . $job . ')') if($job ne $jobtext);
			$s->error("job $jobtext failed to close")
		}
	}
	return 1 unless($is_open);
	&client_send('close')
}

'EOF'
