# Schedule::Server::Serverfuncs.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Server::Serverfuncs;

use strict;
use warnings;
use integer;
use Exporter qw(import);
use IO::Socket (); # INET or UNIX, depending on user's choice

use Schedule::Helpers qw(:IS join_quoted signals);

our $VERSION = '4.0';

my @export_funcs = qw(
	server_globals
	form_unique
	send_exit
	send_remove
	send_finish
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
	($s, $socket, $joblist)
}

sub form_unique {
	$serverid . ($_[0] // $unique)
}

sub signal_handler {
	&signals();
	&send_exit(7);
	&closeserver();
	unlink($s->file()) unless($s->tcp());
	exit(130)
}

sub openserver {
	$socket = ($s->tcp() ? new IO::Socket::INET(
		LocalAddr => $s->addr(),
		LocalPort => $s->port(),
		Type => IO::Socket::SOCK_STREAM(),
		Listen => IO::Socket::SOMAXCONN(),
		Reuse => 1
	) : new IO::Socket::UNIX(
		Local => $s->file(),
		Type => IO::Socket::SOCK_STREAM(),
		Listen => IO::Socket::SOMAXCONN(),
		Reuse => 1
	));
	unless(defined($socket)) {
		$s->fatal('unable to setup socket: ' . $!,
			($s->tcp() ? () : 'maybe you should remove ' .
				$s->file()));
		return ''
	}
	&signals(\&signal_handler);
	1
}

sub closeserver {
	my $ret = 1;
	$ret = '' if(defined($socket) && !($socket->close()));
	unlink($s->file()) unless($s->tcp() || !(-S $s->file()));
	$ret
}

sub send_exit {
	my ($stat) = @_;
	my @fail = ();
	for(my $i = 0; $i < @$joblist; ++$i) {
		my $job = $joblist->[$i];
		push(@fail, &indexname($i)) unless(&send_remove($job, $stat));
		&send_finish($job, $stat)
	}
	@fail
}

sub send_remove {
	my ($job, $stat) = @_;
	return 1 if(defined(&get_status($job)));
	&set_status($job, $stat);
	my $ret = 1;
	my $conn = &get_conn($job);
	$ret = '' unless($s->conn_send($conn, $stat));
	$conn->close() && $ret
}

sub send_finish {
	my ($job, $stat) = @_;
	while(defined(my $conn = &shift_wait($job))) {
		$s->conn_send($conn, $stat);
		close($conn)
	}
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
	my $i = &index_from_unique(@_);
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
	for(my $i = 0; $i < @$joblist; ++$i) {
		return $i if(&get_unique($joblist->[$i]) == $u)
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
	[$conn, $data, $stat, ++$unique, []]
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

'EOF'
