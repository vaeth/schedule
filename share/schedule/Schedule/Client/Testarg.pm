# Schedule::Client::Testarg.pm
#
# Copyright Martin V\"ath <martin at mvath.de>.
# SPDX-License-Identifier: BSD-3-Clause
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Testarg v8.0.0;

use strict;
use warnings;
use integer;
use Exporter qw(import);

use Schedule::Client::Args;

our @EXPORT = qw(
	testarg_init
	test_empty
	test_args
);

#
# Functions
#

sub testarg_init {
	my $s = $_[0];
	$s->check_version();
	&args_init($s)
}

# Normalize and validate the value of --ok, --finished, --started.
# Return true if all values are nonempty.

sub test_empty {
	my ($tests) = @_;
	my $ret = 1;
	for my $a (@$tests) {
		$ret = '' if (&validate_args($a))
	}
	$ret
}

# Return passed string for the value of --ok, --finished, --started

sub test_args {
	my ($tests) = @_;
	my $ret = '';
	for my $a (@$tests) {
		$ret .= "\c@" . join(' ', @$a)
	}
	$ret
}

1;
