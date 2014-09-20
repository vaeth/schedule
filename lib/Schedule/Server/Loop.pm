# Schedule::Server::Loop.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

require 5.012;
package Schedule::Server::Loop v6.0.2;

use strict;
use warnings;
use integer;

use Schedule::Helpers qw(is_nonnegative);
use Schedule::Server::Serverfuncs qw(:FUNCS);

# Global variables:

my $s;
my $socket;
my $joblist;

# Constant variables:

my $have_re = qr{([^\c@]*)\c@([^\c@]*)\c@([^\c@]*)\c@?};

# Variables local to this module:

my $will_close;
my $cmd;
my $data;
my $conn;

#
# Functions
#

sub loop_init() {
	($s, $socket, $joblist) = &server_globals();
	$s->check_version()
}

sub serverloop {
	&loop_init();
	while(defined($conn = $socket->accept())) {
		unless($s->conn_recv($conn, $data)) {
			$s->warning('broken connection attempt')
				unless($s->quiet());
			$conn->close();
			next
		}
		$will_close = 1;
		$data =~ s{^([^\c@]*)\c@?}{};
		$cmd = ($1 // '');
		if($cmd eq 'test') {
			&loop_tests()
		} elsif(($cmd eq 'list') || ($cmd eq 'status')) {
			redo if &loop_list()
		} elsif($cmd eq 'close') {
			# Sort according to expected frequency
		} elsif($cmd eq 'version') {
			redo if &loop_version()
		} elsif(($cmd eq 'queue') || ($cmd eq 'start') || ($cmd eq 'start-or-queue')) {
			&loop_queue()
		} elsif($cmd eq 'end') {
			&loop_end()
		} elsif(($cmd eq 'run') || ($cmd eq 'wait')) {
			&loop_run()
		} elsif(($cmd eq 'bg') || ($cmd eq 'unique')) {
			redo if(&loop_bg())
		} elsif($cmd eq 'cancel') {
			redo if &loop_cancel()
		} elsif($cmd eq 'insert') {
			&loop_insert()
		} elsif($cmd eq 'remove') {
			&loop_remove()
		} elsif($cmd eq 'stop') {
			return &loop_stop()
		} else {
			$s->warning('protocol violation') unless($s->quiet())
		}
		$conn->close() if($will_close)
	}
	''
}

sub loop_version {
	$s->conn_send($conn, 'schedule-server ' . $s->version())
}

sub loop_queue {
	my $send;
	if($cmd eq 'start-or-queue') {
		$data =~ s{$have_re}{};
		$cmd = (&test_jobs($1, $2, $3) ? 'queue' : 'start');
		$send = $cmd . "\c@"
	} else {
		$send = ''
	}
	$data =~ s{^([^\c@]*)\c@}{};
	my $index = &my_index($1, 1);
	$index = scalar(@$joblist) unless(&is_nonnegative($index));
	my $stat = (($cmd eq 'start') ? '' : undef);
	splice(@$joblist, $index, 0, &new_job($conn, $data, $stat));
	$s->conn_send($conn, $send . &form_unique());
	$will_close = '' unless(defined($stat))
}

sub loop_run {
	my $i = &my_index($data);
	my $reply = &indexname($i);
	if($reply eq '0') {
		$s->conn_send($conn, $reply);
		return
	}
	my $job = $joblist->[$i];
	my $stat = &loop_bgjob($job, ($cmd eq 'wait'));
	$s->conn_send($conn, $reply . "\c@" . ($stat // '') . "\c@");
	return 1 if(&is_nonnegative($stat));
	&push_wait($job, $conn);
	$will_close = ''
}

sub loop_bg {
	my $index = &my_index($data);
	my $reply = &indexname($index);
	if($reply ne '0') {
		my $job = $joblist->[$index];
		$reply = &form_unique(&get_unique($job));
		$reply .= "\c@" . &loop_bgjob($job) . "\c@" if($cmd eq 'bg')
	}
	$s->conn_send($conn, $reply)
}

sub loop_bgjob {
	my ($job, $check_only) = @_;
	my $stat = &get_status($job);
	return $stat if(defined($stat) || ($check_only // ''));
	&set_status($job, '');
	$s->conn_send(&get_conn($job), 'run');
	''
}

sub loop_end() {
	$data =~ s{^([^\c@]*)\c@?}{};
	my $j = &job_from_unique($1);
	return unless(defined($j));
	my $stat = (&is_nonnegative($data) ? $data : 7);
	&set_status($j, $stat);
	&send_finish($j, $stat)
}

sub loop_cancel() {
	$data =~ s{^(\d+)\c@?}{};
	my $stat = ($1 // 0);
	my $index = &my_index($data);
	my $reply = &indexname($index);
	if($reply ne '0') {
		my $job = $joblist->[$index];
		$reply .= "\c@-" unless(&send_remove($job, $stat));
		&set_status($job, $stat);
		&send_finish($job, $stat)
	}
	$s->conn_send($conn, $reply)
}

sub loop_list() {
	my $i = &my_index($data);
	my $reply = &indexname($i);
	if($reply ne '0') {
		my $job = $joblist->[$i];
		$reply .= "\c@\@" . &get_unique($job);
		$reply .= "\c@" . (&get_status($job) // '-');
		$reply .= "\c@" . &get_cmd($job) if($cmd eq 'list')
	}
	$s->conn_send($conn, $reply)
}

sub loop_tests() {
	$data =~ m{$have_re};
	$s->conn_send($conn, &test_jobs($1, $2, $3))
}

sub loop_insert() {
	$data =~ s{([^\c@]*)\c@?}{};
	my $index = &my_index($1, 1);
	return unless(defined($index));
	my @insert = ();
	for my $i (&unique_indices($data)) {
		push(@insert, $joblist->[$i]);
		$joblist->[$i] = undef
	}
	my @oldlist = @$joblist;
	@$joblist = ();
	for(my $i = 0; $i < @oldlist; ++$i) {
		if($index == @$joblist) {
			push(@$joblist, @insert);
			@insert = ()
		}
		my $j = $oldlist[$i];
		push(@$joblist, $j) if(defined($j))
	}
	push(@$joblist, @insert)
}

sub loop_remove() {
	$data =~ s{^(\d+)\c@?}{};
	my $stat = ($1 // 0);
	my @fail = ();
	for my $i (&unique_indices($data)) {
		my $job = $joblist->[$i];
		push(@fail, &indexname($i)) unless(&send_remove($job, $stat));
		&send_finish($job, $stat);
		$joblist->[$i] = undef
	}
	my @oldlist = @$joblist;
	@$joblist = ();
	for(my $i = 0; $i < @oldlist; ++$i) {
		my $j = $oldlist[$i];
		push(@$joblist, $j) if(defined($j))
	}
	$s->conn_send($conn, join("\c@", @fail, '-'))
}

sub loop_stop() {
	$data =~ m{^(\d+)};
	my $stat = ($1 // 0);
	my @fail = &send_exit($stat);
	my $ret = $s->conn_send($conn, join("\c@", @fail, '-'));
	$ret = '' if(@fail);
	$conn->close() && $ret
}

1;
