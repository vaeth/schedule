# Schedule::Client::Cmd::Insert.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Cmd::Insert;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);

our $VERSION = '5.1';

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

'EOF'
