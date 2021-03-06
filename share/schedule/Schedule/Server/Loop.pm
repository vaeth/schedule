# Schedule::Server::Loop.pm
#
# Copyright Martin V\"ath <martin at mvath.de>.
# SPDX-License-Identifier: BSD-3-Clause
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Server::Loop v8.0.0;

use strict;
use warnings;
use integer;

use Schedule::Helpers qw(is_nonnegative);
use Schedule::Server::Serverfuncs qw(:FUNCS);

# Global variables:

my $s;
my $socket;
my $joblist;
my $log;

# Constant variables:

my $have_re = qr{([^\c@]*)\c@([^\c@]*)\c@([^\c@]*)\c@?};

# Variables local to this module:

my $will_close;
my $cmd;
my $data;
my $conn;
my $pausing;
my @stored;

#
# Functions
#

sub loop_init {
	($log) = @_;
	($s, $socket, $joblist) = &server_globals($log);
	$pausing = '';
	@stored = ();
	$s->check_version()
}

sub serverloop {
	&loop_init;
	my $new_conn = 1;
	while (&loop_getcmd($new_conn)) {
		$new_conn = $will_close = 1;
		if ($cmd eq 'test') {
			&loop_tests()
		} elsif (($cmd eq 'list') || ($cmd eq 'status')) {
			if (&loop_list()) {
				$new_conn = '';
				next
			}
		} elsif ($cmd eq 'close') {
			# Sort according to expected frequency
		} elsif ($cmd eq 'version') {
			if (&loop_version()) {
				$new_conn = '';
				next
			}
		} elsif (($cmd eq 'queue') || ($cmd eq 'start') || ($cmd eq 'start-or-queue')) {
			&loop_queue()
		} elsif ($cmd eq 'end') {
			next if (&loop_pausing());
			&loop_end()
		} elsif (($cmd eq 'run') || ($cmd eq 'wait')) {
			next if (&loop_pausing());
			&loop_run()
		} elsif (($cmd eq 'bg') || ($cmd eq 'unique')) {
			next if (&loop_pausing());
			if (&loop_bg()) {
				$new_conn = '';
				next
			}
		} elsif ($cmd eq 'cancel') {
			next if (&loop_pausing());
			if (&loop_cancel()) {
				$new_conn = '';
				next
			}
		} elsif ($cmd eq 'insert') {
			&loop_insert()
		} elsif ($cmd eq 'remove') {
			&loop_remove()
		} elsif ($cmd eq 'test-pausing') {
			&loop_success($pausing ? '1' : '0')
		} elsif ($cmd eq 'pause') {
			$pausing = 1;
			&loop_success()
		} elsif ($cmd eq 'continue') {
			$pausing = '';
			&loop_success()
		} elsif ($cmd eq 'stop') {
			$pausing = '';
			return &loop_stop()
		} else {
			$s->warning('protocol violation') unless ($s->quiet())
		}
		$conn->close() if ($will_close)
	}
	''
}

sub loop_getcmd {
	my ($new_conn) = @_;
	if (!$new_conn && &loop_getcmd_recv()) {
		return 1
	}
	if (!$pausing && @stored) {
		my $stored = shift(@stored);
		($conn, $cmd, $data) = @$stored;
		return 1
	}
	while (defined($conn = $socket->accept())) {
		return 1 if (&loop_getcmd_recv())
	}
	''
}

sub loop_getcmd_recv {
	if ($s->conn_recv($conn, $data)) {
		$data =~ s{^([^\c@]*)\c@?}{};
		$cmd = ($1 // '');
		return 1
	}
	$s->warning('broken connection attempt') unless ($s->quiet());
	$conn->close();
	$log->log('warning', 'broken connection attempt') if (defined($log));
	''
}

sub loop_pausing {
	return '' unless ($pausing);
	push(@stored, [$conn, $cmd, $data]);
	1
}

sub loop_version {
	$s->conn_send($conn, 'schedule-server ' . $s->version())
}

sub loop_success {
	$s->conn_send($conn, shift() // '1')
}

sub loop_queue {
	my $send;
	if ($cmd eq 'start-or-queue') {
		$data =~ s{$have_re}{};
		$cmd = (&test_jobs($1, $2, $3) ? 'queue' : 'start');
		$send = $cmd . "\c@"
	} else {
		$send = ''
	}
	$data =~ s{^([^\c@]*)\c@}{};
	my $index = &my_index($1, 1);
	$index = scalar(@$joblist) unless (&is_nonnegative($index));
	my $stat = (($cmd eq 'start') ? '' : undef);
	$log->log('info', "$cmd " . ($index + 1), $data) if (defined($log));
	splice(@$joblist, $index, 0, &new_job($conn, $data, $stat));
	$s->conn_send($conn, $send . &form_unique());
	$will_close = '' unless (defined($stat))
}

sub loop_run {
	my $i = &my_index($data);
	my $reply = &indexname($i);
	if ($reply eq '0') {
		$s->conn_send($conn, $reply);
		return
	}
	my $job = $joblist->[$i];
	my $stat = &loop_bgjob($job, ($cmd eq 'wait'));
	$log->log('info', $cmd . ' ' . $reply, &get_cmd($job))
		if (defined($log));
	$s->conn_send($conn, $reply . "\c@" . ($stat // '') . "\c@");
	return 1 if (&is_nonnegative($stat));
	&push_wait($job, $conn);
	$will_close = ''
}

sub loop_bg {
	my $index = &my_index($data);
	my $reply = &indexname($index);
	if ($reply ne '0') {
		my $job = $joblist->[$index];
		$log->log('info', $cmd . ' ' . $reply, &get_cmd($job))
			if (defined($log));
		$reply = &form_unique(&get_unique($job));
		$reply .= "\c@" . &loop_bgjob($job) . "\c@" if ($cmd eq 'bg')
	}
	$s->conn_send($conn, $reply)
}

sub loop_bgjob {
	my ($job, $check_only) = @_;
	my $stat = &get_status($job);
	return $stat if (defined($stat) || ($check_only // ''));
	&set_status($job, '');
	&send_run($job);
	''
}

sub loop_end {
	$data =~ s{^([^\c@]*)\c@?}{};
	my $j = &job_from_unique($1);
	return unless (defined($j));
	my $stat = (&is_nonnegative($data) ? $data : 7);
	$log->log('info', 'finished (' . $stat . ')', &get_cmd($j))
		if (defined($log));
	&set_status($j, $stat);
	&send_finish($j, $stat)
}

sub loop_cancel {
	$data =~ s{^(\d+)\c@?}{};
	my $stat = ($1 // 0);
	my $index = &my_index($data);
	my $reply = &indexname($index);
	if ($reply ne '0') {
		my $job = $joblist->[$index];
		$log->log('info', 'cancel job ' . $reply, &get_cmd($job))
			if (defined($log));
		$reply .= "\c@-" unless (&send_remove($job, $stat));
		&set_status($job, $stat);
		&send_finish($job, $stat)
	}
	$s->conn_send($conn, $reply)
}

sub loop_list {
	my $i = &my_index($data);
	my $reply = &indexname($i);
	if ($reply ne '0') {
		my $job = $joblist->[$i];
		$reply .= "\c@\@" . &get_unique($job);
		$reply .= "\c@" . (&get_status($job) // '-');
		if ($cmd eq 'list') {
			$reply .= "\c@" . &get_qtime($job) .
				"\c@" . &get_stime($job) .
				"\c@" . &get_etime($job) .
				"\c@" . &get_cmd($job)
		}
	}
	$s->conn_send($conn, $reply)
}

sub loop_tests {
	$data =~ m{$have_re};
	$s->conn_send($conn, &test_jobs($1, $2, $3))
}

sub loop_insert {
	$data =~ s{([^\c@]*)\c@?}{};
	my $index = &my_index($1, 1);
	return unless (defined($index));
	$log->log('notice', 'reorder jobs') if (defined($log));
	my @insert = ();
	for my $i (&unique_indices($data)) {
		push(@insert, $joblist->[$i]);
		$joblist->[$i] = undef
	}
	my @oldlist = @$joblist;
	@$joblist = ();
	for my $j (@oldlist) {
		next unless (defined($j));
		if ($index == @$joblist) {
			push(@$joblist, @insert);
			@insert = ()
		}
		push(@$joblist, $j)
	}
	push(@$joblist, @insert)
}

sub loop_remove {
	$data =~ s{^(\d+)\c@?}{};
	my $stat = ($1 // 0);
	my @fail = ();
	$log->log('notice', 'remove job') if (defined($log));
	for my $i (&unique_indices($data)) {
		my $job = $joblist->[$i];
		push(@fail, &indexname($i)) unless (&send_remove($job, $stat));
		&send_finish($job, $stat);
		$joblist->[$i] = undef
	}
	my @oldlist = @$joblist;
	@$joblist = ();
	for my $j (@oldlist) {
		push(@$joblist, $j) if (defined($j))
	}
	$s->conn_send($conn, join("\c@", @fail, '-'))
}

sub loop_stop {
	$log->log('info', 'stop') if (defined($log));
	$data =~ m{^(\d+)};
	my $stat = ($1 // 0);
	my @fail = &send_exit($stat);
	my $ret = $s->conn_send($conn, join("\c@", @fail, '-'));
	$ret = '' if (@fail);
	$conn->close() && $ret
}

1;
