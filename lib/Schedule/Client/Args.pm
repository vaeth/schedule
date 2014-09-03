# Schedule::Client::Args.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Args;

use strict;
use warnings;
use integer;
use Exporter qw(import);

use Schedule::Helpers qw(join_quoted);

our $VERSION = '5.1';

our @EXPORT = qw(
	args_init
	validate_args
);

# Global variables:

my $s;

#
# Functions
#

sub args_init {
	$s = $_[0];
	$s->check_version()
}

# Normalize @ARGV (resp. passed array reference) and check whether it consists
# of valid job specifications.
# Let @ARGV = (':') if there are none (unless array reference is passed).
# Return true if result is nonempty.

sub validate_args {
	my ($array) = @_;
	my $colon_if_empty = '';
	unless(defined($array)) {
		$colon_if_empty = 1;
		$array = \@ARGV
	}
	@$array = split(' ', join(' ', @$array));
	unless(@$array) {
		return '' unless($colon_if_empty);
		@$array = (':');
		return 1
	}
	for my $i (@$array) {
		my ($valid) = $s->decode_range($i);
		$s->fatal('invalid job specification: ' . &join_quoted($i))
			unless(defined($valid))
	}
	1
}

'EOF'
