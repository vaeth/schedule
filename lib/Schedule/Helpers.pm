# Schedule::Helpers.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project and under a BSD type license.

package Schedule::Helpers;
#use Term::ANSIColor; # not mandatory but recommended: fallback to no color

use strict;
use warnings;
use integer;
use Carp;

use Exporter qw(import);

our @EXPORT_OK = qw(
	signals
	my_user
	use_ansicolor
	my_color
	is_nonnegative
	is_nonempty
	split_quoted
	env_to_array
);
our $VERSION = '1.1';

sub signals {
	$SIG{INT} = $SIG{HUP} = $SIG{TERM} = ((@_) ? $_[0] : sub {1})
}

{ my $user = undef; # static closure
sub my_user {
	return $user if(defined($user));
	my $user = getpwuid($<);
	$user = $< unless(&is_nonempty($user));
	$user =~ s{\W}{}g;
	$user
}}

{ my $ansicolor = undef; # A closure static variable
sub use_ansicolor {
	return $ansicolor if(defined($ansicolor));
	eval {
		require Term::ANSIColor;
		Term::ANSIColor->import()
	};
	$ansicolor = !$@
}}

sub my_color {
	&use_ansicolor() ? color(@_) : ''
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
	while($arg ne '') {
		my $add;
		if(($arg =~ s{\A([^\"\'\s\$\\]+)}{}m) ||
			($arg =~ s{\A\\(.)}{}m) || ($arg =~ s{^(\\)$}{}) ||
			($arg =~ s{\A\'((?:[^\'])*)\'?}{}m)) {
			$add = $1;
		} elsif($arg =~ s{\A(\s+)}{}m) {
			$add = $1;
			unless($quoting) {
				if(defined($word)) {
					push(@res, $word);
					$word = undef
				}
				next
			}
		} elsif($arg =~ s{^\"}{}) {
			$quoting = !$quoting;
			next
		} elsif(($arg =~ s{^\$([a-zA-Z_]\w*)}{}) ||
			($arg =~ s{^\$\{([a-zA-Z_]\w*)\}}{})) {
			my $var = $1;
			$add = ($ENV{$var} // '');
			unless($quoting) {
				croak('infinite recursion suspected: $' . $var
					. 'expanded too often')
					if(($used{$var} = ($used{$var} // 0) + 1) > 99999);
				$arg = $add . $arg;
				next
			}
		} else {
			$arg =~ s{^\$}{};
			$add = '$'
		}
		if(defined($word)) {
			$word .= $add
		} else {
			$word = $add
		}
	}
	push(@res, $word) if(defined($word));
	@res
}

sub env_to_array {
	&split_quoted($ENV{$_[0]} // '')
}

1;
