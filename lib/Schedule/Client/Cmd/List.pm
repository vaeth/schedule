# Schedule::Client::Cmd::List.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

require 5.012;
package Schedule::Client::Cmd::List v6.3.0;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Client::Iterator;
use Schedule::Helpers qw(is_nonnegative join_quoted my_color);

# Global variables:

my $s;

# Static variables:

my $col_reset = undef;
my $col_waiting = undef;
my $col_running = undef;
my $col_nojob = undef;
my $col_ok = undef;
my $col_failed = undef;
my $col_meta = undef;
my $col_job;
my $col_addr;
my $col_user = undef;
my $col_root = undef;
my $col_host = undef;
my $col_xhost = undef;
my $col_dir = undef;
my $hosttextsave = undef;

#
# Functions
#

sub list_init {
	$s = &client_globals();
	$s->check_version();
	&args_init($s);
	&iterator_init($s)
}

sub list {
	&list_init();
	my ($type, $nouser, $nohost, $nodir, $nocommand, @timeformat) = @_;
	&validate_args();
	my $last = undef;
	my $is_open = '';
	my $send = $type;
	$send = 'status' if($type ne 'list');
	$send .= "\c@";
	for my $a (@ARGV) {
		for(my $iter = Schedule::Client::Iterator->new($a, \$last, \$is_open);
			$iter->unfinished(); $iter->increase()) {
			return '' unless($is_open || &openclient());
			$is_open = 1;
			my $reply;
			return '' unless(&client_send($send . $iter->current()) &&
				&client_recv($reply) &&
				($reply =~ s{^(\d+)\c@?}{}));
			my $job = $1;
			my ($addr, $stat, $found);
			my $quiet = ($s->quiet());
			my @times = ();
			if($job eq '0') {
				$found = '';
				my $no_error = (($type eq 'number') ||
					($type eq 'address') ||
					(($type eq 'status') && !$quiet));
				last unless($iter->cond_error($quiet ||
					$no_error));
				unless($no_error) {
					&set_exitstatus(1);
					next
				}
			} else {
				$found = 1;
				$reply =~ s{^([^\c@]*)\c@?}{};
				$addr = ($1 // '');
				if($type ne 'list') {
					$stat = $reply
				} else {
					$reply =~ s{^([^\c@]*)\c@?}{};
					$stat = ($1 // '');
					for(my $i = 0; $i < 3; ++$i) {
						$reply =~ s{^([^\c@]*)\c@?}{};
						push(@times, &format_time($timeformat[$i], $1))
					}
				}
				if($quiet) {
					&set_exitstatus($stat) if($stat &&
						($type eq 'status'));
					next
				}
			}
			my $use_color = $s->color_stdout();
			my $reset = ($use_color ?
				($col_reset //= &my_color('reset')) : '');
			my $statspace = ' ';
			if(!$found) {
				$statspace = (' ' x 7);
				$stat = '-';
				if($use_color) {
					$col_nojob //= &my_color('bold red');
					$stat = $col_nojob . $stat . $reset
				}
			} elsif($stat eq '-') {
				$stat = ($use_color ? ($col_waiting //=
					&my_color('bold blue')) : '')
					. 'waiting' . $reset
			} elsif($stat eq '') {
				$stat = ($use_color ? ($col_running //=
					&my_color('bold yellow')) : '')
					. 'running' . $reset
			} elsif(&is_nonnegative($stat)) {
				$statspace = (' ' x (8 - length($stat)));
				$stat = ($stat ? ($col_failed //=
					&my_color('bold red')) :
					($col_ok //= &my_color('bold green')))
					. $stat . $reset if($use_color)
			} else {
				$s->fatal('strange server reply');
				return ''
			}
			if($type eq 'status') {
				print($stat . "\n");
				next
			}
			if($use_color && !defined($col_meta)) {
				$col_meta = &my_color('cyan');
				$col_job = &my_color('bold');
				$col_addr = &my_color('bold cyan')
			}
			if($type eq 'address') {
				if($use_color) {
					print(($found ? $col_addr : $col_nojob),
						$addr, $reset, "\n")
				} else {
					print($addr, "\n")
				}
				next
			}
			if($type eq 'number') {
				if($use_color) {
					print(($found ? $col_job : $col_nojob),
						$job, $reset, "\n")
				} else {
					print($job, "\n")
				}
				next
			}
			my $jobspace = ((length($job) < 3) ?
				(' ' x (3 - length($job))) : '');
			my $addrspace = ((length($addr) < 4) ?
				(' ' x (4 - length($addr))) : '');
			my $cmd = &format_cmd(1, $reply, $nouser, $nohost, $nodir, $nocommand);
			my $times = &format_times($use_color, @times);
			if($use_color) {
				print($jobspace, $col_job, $job, $reset,
				$addrspace, $col_addr, $addr, $reset,
				$statspace, $col_meta, '(', $stat,
				$col_meta, ')', $reset, $cmd, $times, "\n")
			} else {
				print($jobspace, $job, $addrspace, $addr,
				$statspace, '(', $stat, ')', $cmd, $times, "\n")
			}
		}
	}
	return 1 unless($is_open);
	&client_send('close')
}

# In case $use_color, the variables $col_reset, $col_meta are expected.

sub format_cmd {
	my ($use_color, $data, $nouser, $nohost, $nodir, $nocommand) = @_;
	my ($user, $host, $hosttext, $dir, @cmd) = split("\c@", $data);
	return ($nocommand ? '' : $data) unless(defined($dir));
	my $cmd = (($nocommand || !@cmd) ? '' : ' ' . &join_quoted(@cmd));
	my $nopwd = ($nodir || ($dir eq ''));
	return $cmd if($nouser && $nopwd);
	$nohost = 1 if(($hosttext eq '') || $nouser);
	my $color_user;
	my $color_xhost = '';
	my $color_meta = '';
	if($use_color) {
		$color_meta = $col_meta;
		unless($nohost) {
			$hosttextsave //= ($ENV{'HOSTTEXTSAVE'} // '');
			$color_xhost = ((($hosttextsave ne '') &&
				($hosttextsave ne $hosttext)) ?
				($col_xhost //= &my_color('red')) : $col_meta)
		}
	}
	my $reply = ($use_color ? (' ' . $col_meta . '[') : ' [');
	$reply .= ($use_color ? ((($user eq 'root') ?
			($col_root //= &my_color('bold cyan')) :
			($col_user //= &my_color('yellow')))
			. $user . $col_reset . $col_meta . '@' .
			($col_host //= &my_color('green')) . $host ) :
			($user . '@' . $host)) .
		($nohost? ($nopwd ? '' : ($color_meta . ':')) :
			($color_xhost . '(' . $hosttext . ')'))
			unless($nouser);
	$reply .= ($use_color ? (($col_dir //= &my_color('bold green'))
		. $dir . $col_reset . $col_meta)
		: $dir) unless($nopwd);
	$reply .= ']';
	$reply .= $col_reset if($use_color);
	$reply . $cmd
}

# In case $use_color, the variables $col_reset, $col_meta are expected.

sub format_times {
	my $use_color = shift();
	my $ret = '';
	for(; @_; shift()) {
		next if($_[0] eq '');
		if($ret eq '') {
			$ret = ($use_color ? (' ' . $col_meta . '[' . $col_reset)
				: ' [')
		} else {
			$ret .= ($use_color ? ($col_meta . ',' . $col_reset . ' ')
				: ', ')
		}
		$ret .= $_[0]
	}
	($ret eq '') ? '' :
		($use_color ? ($ret . $col_meta . ']' . $col_reset) : ']')
}

sub twodigit {
	my ($digit) = @_;
	($digit < 10 ? ('0' . "$digit") : "$digit")
}

sub format_time {
	my ($format, $time) = @_;
	return '' if((($format // '') eq '') ||
		(!&is_nonnegative($time)) || ($time eq 0));
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) =
		localtime($time);
	my $replace = sub {
		my ($c) = @_;
		return &twodigit($hour) . ':' . &twodigit($min) . ':' . &twodigit($sec)
			if($c eq 'T');
		return &twodigit($hour) . ':' . &twodigit($min) . ':' . &twodigit($sec)
			if($c eq 'R');
		return &twodigit($sec) if($c eq 'S');
		return &twodigit($min) if($c eq 'M');
		return &twodigit($hour) if($c eq 'H');
		return &twodigit($mday) if($c eq 'd');
		return &twodigit($mon + 1) if($c eq 'm');
		return &twodigit($year % 100) if($c eq 'y');
		return $year if($c eq 'Y');
		return ($wday ? $wday : 7) if($c eq 'u');
		return $wday if($c eq 'w');
		if($c eq 'j') {
			++$yday;
			return ($yday < 100 ? ('0' . &twodigit($yday)) : "$yday")
		}
		return $time if($c eq 's');
		$c
	};
	$format =~ s{\%([TRSMHdmyYuwjs\%])}{$replace->($1)}ge;
	$format
}

1;
