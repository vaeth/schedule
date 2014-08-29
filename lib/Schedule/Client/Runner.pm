# Schedule::Client::Runner.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Runner;

use strict;
use warnings;
use integer;
use Exporter qw(import);

use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Helpers qw(is_nonnegative);

our $VERSION = '4.2';

our @EXPORT = qw(
	runner_init
	runner
);

#
# Functions
#

sub runner_init {
	$_[0]->check_version()
}

sub runner {
	my $send = shift();
	my $nowait = !($_[2] // '');
	return '' unless($nowait || &openclient());
	my $reply;
	my $ret = (&client_send($send) &&
		&client_recv($reply) &&
		($reply =~ m{^([^\c@]*)\c@?(\d*)\c@?}));
	$_[0] = my $num = $1;
	my $stat = $2;
	unless($nowait || ($num eq '0') || &is_nonnegative($stat)) {
		$ret = '' unless(&client_recv($stat, 0) &&
			(($stat eq '') || &is_nonnegative($stat)))
	}
	$_[1] = $stat;
	($nowait || &closeclient()) && $ret
}

'EOF'
