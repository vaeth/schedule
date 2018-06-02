# Schedule::Client::Cmd::Remove.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Cmd::Remove v8.0.0;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);

# Global variables:

my $s;

#
# Functions
#

sub remove_init {
	$s = &client_globals();
	$s->check_version();
	&args_init($s)
}

sub remove {
	&remove_init();
	my $cancel = shift();
	my $stop = ($_[0] // '');
	&validate_args();
	return '' unless (&openclient() &&
		&client_send($stop ? "stop\c@$cancel" :
			("remove\c@$cancel\c@" . join(' ', @ARGV))) &&
		&client_recv(my $fail));
	my @fail = split("\c@", $fail);
	pop(@fail);
	if (@fail) {
		&set_exitstatus(1) unless ($stop);
		$s->error('jobs failed to close: ' . join(' ', @fail))
			unless ($s->quiet())
	}
	1
}

1;
