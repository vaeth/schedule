# Schedule::Server::Loop.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Log v8.0.0;

use strict;
use warnings;
use integer;
use feature 'state';

#use Sys::Syslog (); # needed if --syslog is selected

use Schedule::Helpers qw(join_quoted);

#
# Functions
#

sub equal_arrays {
	my ($a, $b) = @_;
	return '' if (@$a != @$b);
	for (my $i = 0; $i < @$a; ++$i) {
		return '' if ($a->[$i] ne $b->[$i])
	}
	1
}

#
# Methods
#

sub new {
	my $class = shift();
	my ($s, $syslog, $file, $append) = @_;
	$s->check_version();
	bless({
		sp => $s,
		syslog => $syslog,
		file => $file,
		append => $append,
		is_open => '',
		fh => undef,
		prevmsg => [],
		count => 0
	}, $class)
}

sub sp {
	my $s = shift();
	$s->{sp}
}

sub syslog {
	my $s = shift();
	$s->{syslog}
}

sub file {
	my $s = shift();
	$s->{file}
}

sub append {
	my $s = shift();
	$s->{append}
}

sub is_open {
	my $s = shift();
	@_ ? ($s->{is_open} = shift()) : $s->{is_open}
}

sub fh {
	my $s = shift();
	@_ ? ($s->{fh} = shift()) : $s->{fh}
}

sub prevmsg {
	my $s = shift();
	@_ ? ($s->{prevmsg} = shift()) : $s->{prevmsg}
}

sub count {
	my $s = shift();
	@_ ? ($s->{count} = shift()) : $s->{count}
}

sub open_internal {
	my $s = shift();
	state $syslog;
	if (defined($syslog) || $s->syslog()) {
		eval {
			require Sys::Syslog
		};
		my $err = $@;
		$syslog = !$err;
		$s->sp()->fatal('perl module Sys::Syslog (for --syslog) not available',
			$err) unless ($syslog)
	}
	my $file = $s->file();
	if ($file ne '') {
		if (open(my $fh, ($s->append() ? '>>' : '>'), $file)) {
			select((select($fh), $|=1)[0]);
			$s->fh($fh)
		} else {
			$s->sp()->fatal("cannot open $file for writing", $!)
		}
	}
	$s->is_open(1)
}

sub log_internal {
	my $s = shift();
	$s->open_internal() unless ($s->is_open());
	my $severe = shift();
	my $string = shift();
	$string .= ': ' . &join_quoted(split(/\c@/, $_[0])) if (@_);
	Sys::Syslog::syslog($severe, '%s', $string) if ($s->syslog());
	my $fh = $s->fh();
	return unless (defined($fh));
	my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
	printf($fh '%s/%02d/%02d %02d:%02d:%02d %s' . "\n",
		$year + 1900, $mon + 1, $mday, $hour, $min, $sec, $string)
}

sub log {
	my $s = shift();
	my @args = @_;
	my $p = $s->prevmsg();
	if (&equal_arrays(\@args, $p)) {
		++($s->{count});
		return
	}
	my $count = $s->count();
	if ($count) {
		$s->count(0);
		my $lastsevere = $s->prevmsg()->[0];
		$s->log_internal($lastsevere,
			'[last message repeated ' . $count . ' times]')
	}
	$s->prevmsg(\@args);
	$s->log_internal(@_)
}

1;
