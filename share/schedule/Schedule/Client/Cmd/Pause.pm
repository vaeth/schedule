# Schedule::Client::Cmd::Pause.pm
#
# Copyright Martin V\"ath <martin at mvath.de>.
# SPDX-License-Identifier: BSD-3-Clause
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Cmd::Pause v8.0.0;

use strict;
use warnings;
use integer;

use Schedule::Client::Clientfuncs qw(:FUNCS);

# Global variables:

my $s;

#
# Functions
#

sub pause_init {
	$s = &client_globals();
	$s->check_version();
}

sub pause {
	&pause_init();
	my $cmd = shift();
	my $retvalue = '';
	return '' unless(&openclient() &&
		&client_send($cmd) &&
		&client_recv($retvalue) &&
		(($retvalue eq '1') || ($retvalue eq '0')));
	print(@_) if ($retvalue eq '1');
	1
}

1;
