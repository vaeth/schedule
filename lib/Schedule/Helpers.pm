# Schedule::Helpers.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Helpers;
use version 0.77 (); our $VERSION = version->declare('v6.0.0');

use strict;
use warnings;
use integer;
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
	signals
	split_quoted
	join_quoted
	env_to_array
);

our @EXPORT_OK = (@export_is, @export_color, @export_sysquery, @export_rest);
our %EXPORT_TAGS = (
	IS => [@export_is],
	COLOR => [@export_color],
	SYSQUERY => [@export_sysquery]
);

sub signals {
	$SIG{INT} = $SIG{HUP} = $SIG{TERM} = ((@_) ? $_[0] : sub {1})
}

{ my $user = undef; # static closure
sub my_user {
	return $user if(defined($user));
	my $user = getpwuid($<);
	$user = $< unless(&is_nonempty($user));
	$user
}}

{ my $ansicolor = undef; # A closure static variable
sub use_ansicolor {
	return $ansicolor if(defined($ansicolor));
	eval {
		require Term::ANSIColor
	};
	$ansicolor = !$@
}}

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
	while($arg ne '') {
		my $add;
		if(($arg =~ s{\A([^\"\'\s\$\\]+)}{}m) ||
			($arg =~ s{\A\\(.)}{}m) || ($arg =~ s{^(\\)$}{}) ||
			($arg =~ s{\A\'((?:[^\'])*)\'?}{}m)) {
			$add = $1
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

'EOF'
