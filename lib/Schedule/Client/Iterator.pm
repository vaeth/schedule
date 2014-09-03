# Schedule::Client::Iterator.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Iterator;

use strict;
use warnings;
use integer;
use Exporter qw(import);

use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Helpers qw(is_nonnegative);

our $VERSION = '5.1';

our @EXPORT = qw(
	iterator_init
);

# Global variables:

my $s;

# Static variables:

my %known_ats = ();

#
# Functions
#

sub iterator_init {
	$s = $_[0];
	$s->check_version()
}

#
# Methods
#

# Schedule::Client::Iterator constructor:
# Get job specification according to passed string.
# For nonpositive numbers use the second argument as the largest job number
# instead of querying the server.
# The second argument can also be a reference in which case the result
# (if queried) is stored in that variable.
# If querying, open a new connection if the third argument is true or
# a reference with a false value. In the former case close the connection
# again, in the latter case set the reference to true.
# The return value is a class of type Schedule::Client::Iterator with subsequent methods

sub new {
	my $class = shift();
	my $a = shift();
	my $self = bless({
		finished => '',
		atbeg => undef,
		beg => undef,
		sep => '',
		atend => undef,
		end => undef
	}, $class);
	if($a =~ m{^u}) {
		$self->{atbeg} = '';
		($self->{beg}, $self->{atend}, $self->{end}) = split(m{\c@}, $a);
		return $self
	}
	my ($atbeg, $beg, $sep, $atend, $end) = $s->decode_range($a);
	unless(defined($atbeg)) {
		$self->{finished} = 1;
		return $self
	}
	($self->{atbeg}, $self->{beg}, $self->{sep}) = ($atbeg, $beg, $sep);
	return $self if($sep eq '');
	($self->{atend}, $self->{end}) = ($atend, $end);
	return $self if($sep eq '_');
	my $beglast = (($atbeg eq '') && ($beg <= 0));
	my $endlast = (($atend eq '') && ($end ne '') && ($end <= 0));
	return $self unless($beglast || $endlast ||
		($atbeg ne '') || ($atend ne ''));
	my ($lastref, $openref) = @_;
	my $last = undef;
	my $is_open = undef;
	my $noclose = 1;
	my $s_open = sub {
		return $is_open if(defined($is_open));
		$openref = '' unless(defined($openref));
		if(ref($openref) eq '') {
			$is_open = $noclose = !$openref
		} else {
			$is_open = ($$openref // '');
			$$openref = $noclose = 1
		}
		unless($is_open || &openclient()) {
			$noclose = 1;
			return ''
		}
		$is_open = 1
	};
	my $s_close = sub {
		return if($noclose);
		&client_send('close');
		&closeclient();
		$noclose = 1
	};
	my $s_last = sub {
		return &is_nonnegative($last) if(defined($last));
		$last = ((ref($lastref) eq '') ? $lastref : $$lastref);
		return 1 if(&is_nonnegative($last));
		return '' unless($s_open->());
		&client_send("status\c@0") &&
			&client_recv($last) &&
			($last //= '') &&
			($last =~ s{^(\d+).*}{$1});
		$last //= '';
		&is_nonnegative($last)
	};
	my $s_at = sub {
		my ($at) = @_;
		my $ret = $known_ats{$at};
		return $ret if(defined($ret));
		return '' unless($s_open->());
		return '' unless(&client_send("status\c@\@$at") &&
			&client_recv($ret) &&
			$ret =~ m{^(\d+)});
		$known_ats{$at} = $1;
	};
	my $s_add = sub {
		my ($at, $addref) = @_;
		my $ret = $s_at->($at);
		$s->warning('nonexistent job address: @' . $at)
			if(($ret ne '') && !$ret);
		if($ret && ($$addref ne '')) {
			$$addref += $ret
		} else {
			$$addref = $ret
		}
		$ret
	};
	my $s_error = sub {
		$self->{finished} = 1;
		$s_close->();
		return $self
	};
	if($beglast || $endlast) {
		return $s_error->() unless($s_last->());
		$self->{beg} = $beg += $last if($beglast);
		$self->{end} = $end += $last if($endlast)
	}
	if($atbeg ne '') {
		return $s_error->() unless($s_add->($atbeg, \$beg));
		$self->{atbeg} = '';
		$self->{beg} = $beg
	}
	if($atend ne '') {
		return $s_error->() unless($s_add->($atend, \$end));
		$self->{atend} = '';
		$self->{end} = $end
	}
	if(($beg <= 0) || (($end ne '') && ($end <= 0))) {
		$s->warning('job number out of range: ' . $a);
		$self->{beg} = 1 if($beg <= 0);
		return $s_error->() if(($end ne '') && ($end <= 0))
	}
	$s_close->();
	$self
}

# Schedule::Client::Iterator method to check whether a current value is available.

sub unfinished {
	my $self = shift();
	return '' if($self->{finished});
	my $ret;
	my $sep = $self->{sep};
	if($sep eq '') {
		$ret = 1
	} elsif($sep eq '_') {
		$ret = ($self->{atbeg} <= $self->{atend})
	} else {
		my $end = $self->{end};
		$ret = (($end eq '') || ($self->{beg} <= $end))
	}
	$self->{finished} = !$ret;
	$ret
}

# Schedule::Client::Iterator method to increase the current value in a range.
# Also single values are considered as ranges.
# When the end is reached, the method current can no longer be used.

sub increase {
	my $self = shift();
	return $self if($self->{finished});
	my $sep = $self->{sep};
	if($sep eq '') {
		$self->{finished} = 1
	} elsif($sep eq '_') {
		++($self->{atbeg})
	} else {
		++($self->{beg})
	}
	$self
}

# Schedule::Client::Iterator method to return the current value,
# with true argument in a human-readable form, otherwise appropriate for
# passage to schedule-server.
# This method requires that the unfinished method returns true.

sub current {
	my $self = shift();
	return undef if($self->{finished});
	my $atbeg = $self->{atbeg};
	my $beg = $self->{beg};
	if($atbeg eq '') {
		return $beg unless(($_[0] // '') && ($self->{sep} eq '') &&
			($atbeg eq '') && ($beg =~ m{^u}));
		my ($here, $all) = ('/' . $self->{atend}, $self->{end});
		return (($here eq $all) ? $here : $here . ' (' . $all . ')')
	}
	$atbeg = '@' . $atbeg;
	return $atbeg unless($beg);
	$beg = '+' . $beg if($beg > 0);
	$atbeg . $beg
}

# Schedule::Client::Iterator method to output the error that a job is unavailable.
# Do not output (and return '' if it is the "normal" end of an open-ended
# range ("x:"); otherwise return true.
# The actual output is omitted if the true argument is passed.
# If no argument is passed, $s->quit() is used.

sub cond_error {
	my $self = shift();
	my $sep = $self->{sep};
	return '' if(($sep eq ':') && ($self->{end} eq ''));
	$s->error('unavailable job ' . $self->current(1))
		unless($_[0] // $s->quiet());
	1
}

'EOF'
