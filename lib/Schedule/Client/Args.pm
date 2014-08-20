# Schedule::Client::Args.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Args;

use strict;
use warnings;
use integer;
use Exporter qw(import);

use Schedule::Common::Helpers qw(join_quoted);

our $VERSION = '4.0';

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

# Check whether @ARGV (resp. passed array reference) are valid job
# specifications.
# Let @ARGV = (':') if there are none (unless array reference is passed).

sub validate_args {
	my ($array) = @_;
	unless(defined($array)) {
		unless(@ARGV) {
			@ARGV = (':');
			return
		}
		$array = \@ARGV
	}
	for my $i (@$array) {
		my ($valid) = $s->decode_range($i);
		$s->fatal('invalid job specification: ' . &join_quoted($i))
			unless(defined($valid))
	}
}

'EOF'
