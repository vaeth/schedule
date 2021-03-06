# Schedule::Client::Runner.pm
#
# Copyright Martin V\"ath <martin at mvath.de>.
# SPDX-License-Identifier: BSD-3-Clause
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Runner v8.0.0;

use strict;
use warnings;
use integer;
use Exporter qw(import);

use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Helpers qw(is_nonnegative);

our @EXPORT = qw(
	runner_init
	runner
);

# Global variables:

my $s;

#
# Functions
#

sub runner_init {
	$s = $_[0];
	$s->check_version()
}

sub runner {
	my $send = shift();
	my $wait = ($_[2] // 0);
	return '' unless ((!$wait) || &openclient());
	my $reply;
	my $ret = &client_send($send);
	my ($num, $stat);
	if ($ret) {
		if (($wait < 0) && !$s->did_alpha()) {
			my $ret = $s->exec_alpha();
			exit($ret) if ($ret);
			$s->forking()
		}
		if (&client_recv($reply) &&
			($reply =~ m{^([^\c@]*)\c@?(\d*)\c@?})) {
			$_[0] = $num = $1;
			$stat = $2
		}
	}
	unless ((!$wait) || ($num eq '0') || &is_nonnegative($stat)) {
		$ret = '' unless (&client_recv($stat, 0) &&
			(($stat eq '') || &is_nonnegative($stat)))
	}
	$_[1] = $stat;
	((!$wait) || &closeclient()) && $ret
}

1;
