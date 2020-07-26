# Schedule::Client::Cmd::Insert.pm
#
# Copyright Martin V\"ath <martin at mvath.de>.
# SPDX-License-Identifier: BSD-3-Clause
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Cmd::Insert v8.0.0;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);

#
# Functions
#

sub insert_init {
	my $s = &client_globals();
	$s->check_version();
	&args_init($s)
}

sub insert {
	&insert_init();
	my ($destjob) = @_;
	&validate_args();
	&openclient() &&
		&client_send("insert\c@$destjob\c@" . join(' ', @ARGV))
}

1;
