# Schedule::Server::Serverfuncs.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Server::Serverfuncs v7.5.0;

use strict;
use warnings;
use integer;
use Exporter qw(import);
use IO::Socket 1.19 (); # INET or UNIX, depending on user's choice

use Schedule::Helpers qw(:IS join_quoted signals);

my @export_funcs = qw(
	server_globals
	form_unique
	send_exit
	send_remove
	send_finish
	send_run
	test_jobs
	job_from_unique
	unique_indices
	indexname
	my_index
	new_job
	get_conn
	get_cmd
	get_status
	set_status
	get_unique
	get_qtime
	get_stime
	get_etime
	push_wait
);

my @export_init = qw(
	server_init
	openserver
	closeserver
);

our @EXPORT_OK = (@export_funcs, @export_init);
our %EXPORT_TAGS = (
	INIT => [@export_init],
	FUNCS => [@export_funcs]
);

# Global variables:

my $s;
my $socket = undef;
my $joblist = [];
my $log;

# Static variables:

my $serverid = rand() . '(' . $$ . ')';
$serverid =~ s{^\s*\d*[.,]}{u};

# Variables local to this module:

my $unique = 0;

#
# Functions
#

sub server_init {
	$s = $_[0];
	$s->check_version()
}

sub server_globals {
	($log) = @_;
	($s, $socket, $joblist)
}

sub form_unique {
	$serverid . ($_[0] // $unique)
}

sub signal_handler {
	&signals();
	$log->log('info', 'stop-signal') if(defined($log));
	&send_exit(7);
	&closeserver();
	unlink($s->file()) unless($s->tcp());
	$log->log('info', 'exit (130)') if(defined($log));
	exit(130)
}

sub openserver_standard {
	$socket = $s->timeout($s->tcp() ? sub { IO::Socket::INET->new(
		LocalAddr => $s->addr(),
		LocalPort => $s->port(),
		Type => IO::Socket::SOCK_STREAM(),
		Listen => IO::Socket::SOMAXCONN(),
		Reuse => 1
	)} : sub { IO::Socket::UNIX->new(
		Local => $s->file(),
		Type => IO::Socket::SOCK_STREAM(),
		Listen => IO::Socket::SOMAXCONN(),
		Reuse => 1
	)});
	$s->fatal('timeout when setting up socket') if($@ eq 'timeout');
	defined($socket) || $s->fatal('unable to setup socket: ' . $!,
		($s->tcp() ? () : 'maybe you should remove ' . $s->file()))
}

sub openserver_fd {
	$socket = ($s->tcp() ? IO::Socket::INET->new() :
		IO::Socket::UNIX->new());
	$s->fatal('cannot allocate socket: ' . $!) unless(defined($socket));
	$socket->fdopen($_[0], 'r') ||
		$s->fatal('cannot open file descriptor ' . $_[0])
}

sub openserver {
	my ($fd) = @_;
	if(&is_nonnegative($fd)) {
		$s->file(undef);
		&openserver_fd($fd)
	} else {
		&openserver_standard()
	}
	&signals(\&signal_handler);
	1
}

sub closeserver {
	my $ret = 1;
	$ret = '' if(defined($socket) && !($socket->close()));
	unlink($s->file()) unless($s->tcp() || (!defined $s->file()) || !(-S $s->file()));
	$ret
}

sub send_exit {
	my ($stat) = @_;
	my @fail = ();
	while(my ($i, $job) = each(@$joblist)) {
		push(@fail, &indexname($i)) unless(&send_remove($job, $stat));
		&send_finish($job, $stat)
	}
	@fail
}

sub send_remove {
	my ($job, $stat) = @_;
	return 1 if(defined(&get_status($job)));
	my $ret = 1;
	my $conn = &get_conn($job);
	$ret = '' unless($s->conn_send($conn, $stat));
	$conn->close() && $ret
}

sub send_finish {
	my ($job, $stat) = @_;
	&set_etime($job);
	while(defined(my $conn = &shift_wait($job))) {
		$s->conn_send($conn, $stat);
		close($conn)
	}
}

sub send_run {
	my ($job) = @_;
	&set_stime($job);
	$s->conn_send(&get_conn($job), 'run');
}

# return whether all jobs are ok, finished, started

sub test_jobs {
	my ($ok, $finished, $started) = @_;
	my $ret = 0;
	for my $i (&unique_indices($ok)) {
		my $s = &get_status($joblist->[$i]);
		$s = 1 unless(&is_nonempty($s));
		$ret = $s if($s > $ret);
	}
	return $ret if($ret);
	for my $i (&unique_indices($finished)) {
		my $s = &get_status($joblist->[$i]);
		return 1 unless(&is_nonempty($s))
	}
	for my $i (&unique_indices($started)) {
		my $s = &get_status($joblist->[$i]);
		return 1 unless(defined($s))
	}
	0
}

# return job corresponding to unique identifier

sub job_from_unique {
	my $i = &index_from_unique;
	defined($i) ? $joblist->[$i] : undef
}

# return index in $joblist corresponding to unique identifier

sub index_from_unique {
	my ($u) = @_;
	return undef unless(substr($u, $[, length($serverid)) eq $serverid);
	&index_from_at(substr($u, length($serverid) + $[))
}

sub index_from_at {
	my ($u) = @_;
	return undef unless(&is_nonnegative($u));
	while(my ($i, $job) = each(@$joblist)) {
		if(&get_unique($job) == $u) {
			keys(@$joblist);  # reset "each" counter
			return $i
		}
	}
	undef
}

sub index_from_pair {
	my $ret = &index_from_at($_[0]);
	my $add = $_[1];
	(defined($ret) && ($add ne '')) ? ($ret + $add) : $ret
}

# return unique list of internal indices corresponding to index names

sub unique_indices {
	return () unless((my $max = @$joblist) > 0);
	my %have = ();
	my @ret = ();
	my $s_valid = sub {
		my ($i) = @_;
		&is_nonnegative($i) && ($i < $max)
	};
	my $s_push = sub {
		my ($i) = @_;
		return unless($s_valid->($i) && !exists($have{$i}));
		$have{$i} = 1;
		push(@ret, $i)
	};
	my $s_pair = sub {
		my $a = shift();
		return &index_from_pair($a, $_[0]) if($a ne '');
		$a = shift();
		$a = 0 if($a eq '');
		(--$a >= 0) ? $a : ($a + $max)
	};
	for my $name (split(' ', ($_[0] // ''))) {
		my ($atbeg, $beg, $sep, $atend, $end) = $s->decode_range($name);
		unless(defined($atbeg)) {
			$s->warning('invalid job specification: ' .
				&join_quoted($name)) unless($s->quiet());
			next
		}
		if($sep eq '_') {
			for(; $atbeg <= $atend; ++$atbeg) {
				$s_push->(&index_from_pair($atbeg, $beg))
			}
			next
		}
		my $i = $s_pair->($atbeg, $beg);
		if($sep eq '') {
			$s_push->($i);
			next
		}
		next unless($s_valid->($i));
		my $e = $s_pair->($atend, $end);
		next unless($s_valid->($e));
		for(; $i <= $e; ++$i) {
			$s_push->($i)
		}
	}
	(@ret)
}

# return name corresponding to internal index $i

sub indexname {
	my ($i) = @_;
	return '0' unless(&is_nonnegative($i) && ($i < @$joblist));
	++$i;
	"$i"
}

# return internal index of array corresponding to arg.
# If second parameter is 1, let 0 count from end of list + 1,
# and prefer 0 (instead of undef).
# The return value may anyway be undefined, e.g. if the specifier is not known

sub my_index {
	my $arg = (shift() // '');
	return &index_from_unique($arg) if($arg =~ m{^u});
	my $end = (shift() // '');
	if($arg eq '') {
		return undef unless($end);
		$arg = '0'
	}
	my ($at, $num) = $s->decode_range($arg);
	unless(defined($at)) {
		$s->warning('invalid job specification: ' . &join_quoted($arg))
			unless($s->quiet());
		return undef
	}
	if($at ne '') {
		$num = &index_from_pair($at, $num);
		return undef unless(defined($num));
		return ($end ? 0 : undef) if($num < 0)
	} elsif($num <= 0) {
		$num += @$joblist;
		--$num unless($end);
		return ($end ? 0 : undef) if($num < 0)
	} else {
		--$num
	}
	($num < @$joblist) ? $num : ($end ? scalar(@$joblist) : undef)
}

#
# Helper functions to the job entries
#

sub new_job {
	my ($conn, $data, $stat) = @_;
	my $time = time();
	[$conn, $data, $stat, ++$unique, [],
		$time, (defined($stat) ? $time : ''), '']
}

sub get_conn {
	$_[0]->[0]
}

sub get_cmd {
	$_[0]->[1]
}

sub get_status {
	$_[0]->[2]
}

sub set_status {
	$_[0]->[2] = $_[1]
}

sub get_unique {
	$_[0]->[3]
}

sub shift_wait {
	my $wait = $_[0]->[4];
	shift(@$wait)
}

sub push_wait {
	my ($j, $p) = @_;
	my $wait = $j->[4];
	push(@$wait, $p)
}

sub get_qtime {
	$_[0]->[5]
}

sub get_stime {
	$_[0]->[6]
}

sub set_stime {
	$_[0]->[6] = time()
}

sub get_etime {
	$_[0]->[7]
}

sub set_etime {
	$_[0]->[7] = time() unless($_[0]->[7] ne '')
}

1;
