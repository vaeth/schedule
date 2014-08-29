# Schedule::Client::Cmd::Test.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Cmd::Test;

use strict;
use warnings;
use integer;

use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Client::Testarg;
use Schedule::Helpers qw(is_nonnegative);

our $VERSION = '4.2';

#
# Functions
#

sub test_init {
	my $s = &client_globals();
	$s->check_version();
	&testarg_init($s)
}

sub test {
	&test_init();
	my ($tests, $num) = @_;
	my $type = $tests->[$num];
	if(@ARGV) {
		push(@$type, @ARGV);
		&test_empty($tests)
	} elsif(&test_empty($tests)) {
		push(@$type, ':')
	}
	return '' unless(&openclient() &&
		&client_send('test' . &test_args($tests)) &&
		&client_recv(my $reply));
	return '' unless(&is_nonnegative($reply));
	&set_exitstatus($reply);
	1
}

'EOF'
