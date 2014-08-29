# Schedule::Client::Cmd::List.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Cmd::List;

use strict;
use warnings;
use integer;

use Schedule::Client::Args;
use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Client::Iterator;
use Schedule::Helpers qw(is_nonnegative join_quoted my_color);

our $VERSION = '4.2';

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
my $col_host;
my $col_dir = undef;

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
	my ($type, $nouser, $nohost, $nodir, $nocommand) = @_;
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
					$stat = ($1 // '')
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
			if($use_color) {
				print($jobspace, $col_job, $job, $reset,
				$addrspace, $col_addr, $addr, $reset,
				$statspace, $col_meta, '(', $stat,
				$col_meta, ')', $reset, $cmd, "\n")
			} else {
				print($jobspace, $job, $addrspace, $addr,
				$statspace, '(', $stat, ')', $cmd, "\n")
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
	if($use_color) {
		unless($nouser || defined($col_user)) {
			$col_user = &my_color('yellow');
			$col_host = &my_color('green')
		}
		unless($nopwd || defined($col_dir)) {
			$col_dir = &my_color('bold green')
		}
	}
	my $reply = ($use_color ? (' ' . $col_meta . '[') : ' [');
	$reply .= ($use_color ? ($col_user . $user . $col_meta . '@' .
		$col_host . $host . $col_meta) : ($user . '@' . $host)) .
		(($nohost || ($hosttext eq '')) ? ($nopwd ? '' : ':' )
		: ('(' . $hosttext . ')')) unless($nouser);
	$reply .= ($use_color ? ($col_dir . $dir . $col_reset . $col_meta)
		: $dir) unless($nopwd);
	$reply .= ']';
	$reply .= $col_reset if($use_color);
	$reply . $cmd
}

'EOF'
