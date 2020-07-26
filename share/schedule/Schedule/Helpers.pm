# Schedule::Helpers.pm
#
# Copyright Martin V\"ath <martin at mvath.de>.
# SPDX-License-Identifier: BSD-3-Clause
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Helpers v8.0.0;

use strict;
use warnings;
use integer;
use feature 'state';

use Exporter qw(import);

my @export_is = qw(
	is_nonnegative
	is_nonempty
);

my @export_color = qw(
	use_ansicolor
	my_color
);

my @export_sysquery = qw(
	my_user
);

my @export_rest = qw(
	nohup
	signals
	split_quoted
	join_quoted
	env_to_array
	with_timeout
);

our @EXPORT_OK = (@export_is, @export_color, @export_sysquery, @export_rest);
our %EXPORT_TAGS = (
	IS => [@export_is],
	COLOR => [@export_color],
	SYSQUERY => [@export_sysquery]
);

sub nohup {
	$SIG{HUP} = $SIG{PIPE} = $SIG{USR1} = $SIG{USR2} = 'IGNORE';
}

sub signals {
	$SIG{INT} = $SIG{TERM} = ((@_) ? $_[0] : 'IGNORE')
}

sub my_user {
	state $user;
	return $user if (defined($user));
	$user = getpwuid($<);
	$user = $< unless (&is_nonempty($user));
	$user
}

sub use_ansicolor {
	state $ansicolor;
	return $ansicolor if (defined($ansicolor));
	eval {
		require Term::ANSIColor
	};
	$ansicolor = !$@
}

sub my_color {
	&use_ansicolor() ? Term::ANSIColor::color(@_) : ''
}

sub is_nonnegative {
	(shift() // '') =~ m{^\d+$}
}

sub is_nonempty {
	(shift() // '') ne ''
}

# Split shell-quoted string into words, substituting environment variables

sub split_quoted {
	my %used = ();
	my ($arg) = @_;
	my @res = ();
	my $word = undef;
	my $quoting = '';
	while ($arg ne '') {
		my $add;
		if (($arg =~ s{\A([^\"\'\s\$\\]+)}{}m) ||
			($arg =~ s{\A\\(.)}{}m) || ($arg =~ s{^(\\)$}{}) ||
			($arg =~ s{\A\'((?:[^\'])*)\'?}{}m)) {
			$add = $1
		} elsif ($arg =~ s{\A(\s+)}{}m) {
			$add = $1;
			unless ($quoting) {
				if (defined($word)) {
					push(@res, $word);
					$word = undef
				}
				next
			}
		} elsif ($arg =~ s{^\"}{}) {
			$quoting = !$quoting;
			next
		} elsif (($arg =~ s{^\$([a-zA-Z_]\w*)}{}) ||
			($arg =~ s{^\$\{([a-zA-Z_]\w*)\}}{})) {
			my $var = $1;
			$add = ($ENV{$var} // '');
			unless ($quoting) {
				croak('infinite recursion suspected: $' . $var
					. 'expanded too often')
					if (($used{$var} = ($used{$var} // 0) + 1) > 99999);
				$arg = $add . $arg;
				next
			}
		} else {
			$arg =~ s{^\$}{};
			$add = '$'
		}
		if (defined($word)) {
			$word .= $add
		} else {
			$word = $add
		}
	}
	push(@res, $word) if (defined($word));
	@res
}

# like join(' ', @_), but shell-quote arguments

sub join_quoted {
	my @r;
	for my $i (@_) {
		my $a = $i;
		$a =~ s{\'}{\'\\\'\'}g;
		$a = "'$a'";
		$a =~ s{(\A|[^\\])\'([\w\-\,\.\:\/]*)\'}{$1$2}gm;
		push(@r, ($a ne '') ? $a : "''")
	}
	join(' ', @r)
}

sub env_to_array {
	&split_quoted($ENV{$_[0]} // '')
}

# with_timeout($timeout => sub { code } [, args] )
# If code is canceled, return value is undef, and $@ is 'timeout'
# The implementation of this function is inspired by Time::Out 0.11
sub with_timeout {
	my $timeout = shift();
	my $code = shift();
	return $code->(@_) unless ($timeout);
	my $prev_alarm = alarm(0);
	my $prev_time = ($prev_alarm ? time() : undef);
	my @ret = ();
	my $at = '';
	my $overrun = '';
	my $wantarray = wantarray();
	{
		# Disable alarm to prevent possible race between end of eval and alarm(0)
		local $SIG{ALRM} = sub {};
		@ret = eval {
			local $SIG{ALRM} = sub { die $code };
			alarm(($prev_alarm && ($prev_alarm < $timeout)) ?
				$prev_alarm : $timeout);
			my @r = ();
			if ($wantarray) {
				@r = $code->(@_)
			} else {
				$r[0] = $code->(@_)
			}
			alarm(0);
			@r
		};
		alarm(0);
		$at = ($@ // '')
	}
	if ($at) {
		if ((ref($at) eq 'CODE') && ($at eq $code)) {
			$overrun = 1
		} else {
			if (!ref($at)){
				chomp($at);
				die($at . "\n")
			} else {
				croak($at)
			}
		}
	}
	if ($prev_alarm) {
		my $new_alarm = $prev_alarm - (time() - $prev_time);
		if ($new_alarm >= 0) {
			alarm($new_alarm)
		} else {
			kill('ALRM', $$)
		}
	}
	if ($overrun) {
		$@ = 'timeout';
		return undef
	}
	$wantarray ? (@ret) : $ret[0]
}

1;
