# Schedule::Connect.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project and under a BSD type license.

package Schedule::Connect;
use File::Spec;
#use Term::ANSIColor; # not mandatory but recommended: fallback to no color
#use Crypt::Rijndael; # needed for password protection
#use Digest::SHA;     # needed for password protection
#use POSIX;           # needed for --detach

use strict;
use warnings;
use integer;

use Getopt::Long;
use Pod::Usage;

use Schedule::Helpers qw(/./);

use Exporter qw(import);

our $VERSION = '3.1';

sub new {
	my ($class, $name, $ver) = @_;
	$0 = $name;
	my $s = bless {
		name => $name,
		daemon => undef,
		tcp => 1,
		addr => '127.0.0.1',
		timeout => 10,
		port => 8471,
		password => undef,
		file => undef,
		stdout_term => undef,
		stderr_term => undef,
		color_stdout => undef,
		color_stderr => undef,
		color_force => undef,
		quiet => '0'
	}, $class;
	$s->fatal("$name version $ver differs from Schedule::Connect version $VERSION")
		if(defined($ver) && ($ver ne $VERSION));
	my $helpers = Schedule::Helpers->VERSION;
	$s->fatal("Schedule::Helpers $helpers differs from Schedule.pm version $VERSION")
		if($helpers ne $VERSION);
	$s
}

sub version {
	$VERSION
}

sub name {
	my $s = shift();
	$s->{name}
}

sub daemon {
	my $s = shift();
	@_ ? ($s->{daemon} = shift()) : $s->{daemon}
}

sub tcp {
	my $s = shift();
	@_ ? ($s->{tcp} = shift()) : $s->{tcp}
}

sub addr {
	my $s = shift();
	@_ ? ($s->{addr} = shift()) : $s->{addr}
}

sub timeout {
	my $s = shift();
	@_ ? ($s->{timeout} = shift()) : $s->{timeout}
}

sub port {
	my $s = shift();
	@_ ? ($s->{port} = shift()) : $s->{port}
}

sub password {
	my $s = shift();
	@_ ? ($s->{password} = shift()) : $s->{password}
}

sub file {
	my $s = shift();
	@_ ? ($s->{file} = shift()) : $s->{file}
}

sub quiet {
	my $s = shift();
	@_ ? ($s->{quiet} = shift()) : $s->{quiet}
}

sub stdout_term {
	my $s = shift();
	$s->{stdout_term} // ($s->{stdout_term} = (-t STDOUT))
}

sub stderr_term {
	my $s = shift();
	$s->{stderr_term} // ($s->{stderr_term} = (-t STDERR))
}

sub color_force {
	my $s = shift();
	@_ ? ($s->{color_force} = shift()) : $s->{color_force}
}

sub color_stdout {
	my $s = shift();
	my $ret = $s->{color_stdout};
	return $ret if(defined($ret));
	my $force = $s->color_force();
	$s->{stdout_term} = (($force // $s->stdout_term())
		? &use_ansicolor() : '')
}

sub color_stderr {
	my $s = shift();
	my $ret = $s->{color_stderr};
	return $ret if(defined($ret));
	my $force = $s->color_force();
	$s->{stderr_term} = (($force // $s->stderr_term())
		? &use_ansicolor() : '')
}

sub fatal {
	&error(@_);
	exit(1)
}

sub error {
	my $s = shift();
	my $name = $s->name();
	my $namecol = '';
	my $errcol = '';
	my $reset = '';
	if($s->color_stderr()) {
		$namecol = &my_color('bold');
		$errcol = &my_color('bold red');
		$reset = &my_color('reset');
	}
	print(STDERR $namecol . $name . $reset . ': ' .
		$errcol . 'error' . $reset . ': ',
		join("\n" . (' ' x (length($name) + 9)), @_), "\n");
}

sub warning {
	my $s = shift();
	my $name = $s->name();
	my $namecol = '';
	my $warncol = '';
	my $reset = '';
	if($s->color_stderr()) {
		$namecol = &my_color('bold');
		$warncol = &my_color('bold cyan');
		$reset = &my_color('reset');
	}
	print(STDERR $namecol . $name . $reset . ': ' .
		$warncol . 'warning' . $reset . ': ',
		join("\n" . (' ' x (length($name) + 11)), @_), "\n")
}

sub get_options {
	my $s = shift();
	my @passfile = ();
	my $quiet = 0;
	Getopt::Long::Configure(qw(bundling gnu_compat no_permute));
	GetOptions(
	'tcp|t', sub { $s->tcp(1) },
	'local|l', sub { $s->tcp('') },
	'password|y=s', sub { $s->password($_[1]) },
	'passfile|Y=s', \@passfile,
	'color|F', sub { $s->color_force(1) },
	'no-color|nocolor|p', sub { $s->color_force('') },
	'port|P=i', sub { $s->tcp(1); $s->port($_[1]) },
	'addr|A=s', sub { $s->tcp(1); $s->addr($_[1]) },
	'file|f=s', sub { $s->tcp(''); $s->file($_[1]) },
	'timeout|T=i', sub { $s->timeout($_[1]) },
	'background|bg|b', sub { $s->daemon(0) },
	'daemon|B', sub { $s->daemon(1) },
	'detach|E', sub { $s->daemon(-1) },
	'quiet|q+', \$s->{quiet},
	'help|h', sub { pod2usage(1) },
	'man|?', sub { pod2usage(-verbose => 2) },
	'version|V', sub { print($s->name(), " $VERSION\n"); exit(0) },
	@_) or pod2usage(2);
	if(@ARGV) {
		if($ARGV[0] =~ m/^man/i) {
			pod2usage(verbose => 2)
		} elsif($ARGV[0] =~ m/^help/i) {
			pod2usage(0)
		}
	}
	# Read password file before dropping permissions
	for my $passfile (@passfile) {
		next unless(open(my $fh, '<', $passfile));
		my $pw = <$fh>;
		close($fh);
		chomp($pw);
		$s->password($pw) if(&is_nonempty($pw))
	}
	1
}

sub check_options {
	my $s = shift();
	my $timeout = $s->timeout();
	$s->fatal("illegal timeout $timeout")
		unless(&is_nonnegative($timeout));
	my $port = $s->port();
	$s->fatal("illegal port $port")
		unless(&is_nonnegative($port) && ($port <= 0xFFFF));
	if(($s->daemon() // 0) < 0) {
		eval {
			require POSIX;
			POSIX->import()
		};
		$s->fatal('you might need to install perl module POSIX', $@)
			if($@)
	}
	return unless(defined($s->password()));
	eval {
		require Crypt::Rijndael;
		Crypt::Rijndael->import()
	};
	$s->fatal('you might need to install perl module Crypt::Rijndael', $@)
		if($@);
	eval {
		require Digest::SHA;
		Digest::SHA->import(qw(sha256));
	};
	$s->fatal('you might need to install perl module Digest::SHA', $@)
		if($@);
	my $hash = sha256($s->password());
	my $p = Crypt::Rijndael->new($hash, Crypt::Rijndael::MODE_CFB());
	$p->set_iv('a' x 16);
	$s->password($p)
}

sub forking {
	my $s = shift();
	return 1 unless(defined(my $d = $s->daemon()));
	my $pid = fork();
	$s->error('forking failed; running in foreground')
		unless(defined($pid));
	exit(0) if($pid);
	return 1 unless($d);
	if(($d < 0) && (POSIX::setsid() < 0)) {
		$s->warning('cannot detach from controlling terminal');
		return ''
	}
	my $ret = close(STDIN);
	$ret = '' unless(close(STDOUT));
	$ret = '' unless(($d > 0) || close(STDERR));
	my $devnull = File::Spec->devnull();
	$ret = '' unless(open(STDIN, '<', $devnull));
	$ret = '' unless(open(STDOUT, '+>', $devnull));
	(($d > 0) || open(STDERR, '+>', $devnull)) && $ret
}

sub default_filename {
	my $s = shift();
	return '' if(defined($s->file()));
	$s->file(File::Spec->catfile(File::Spec->tmpdir(),
		'schedule-' . &my_user(), 'server'));
	1
}

sub decode_range {
	my $s = shift();
	return undef unless(($_[0] // '') =~
		m{^\/?(?:\@(\d+))?([+-]?\d+)?(?:([:_])(?:\@(\d+))?([+-]?(\d+))?)?$});
	my ($atbeg, $beg, $sep) = (($1 // ''), ($2 // ''), ($3 // ''));
	my ($atend, $end) = (($4 // ''), ($5 // ''));
	$beg =~ s{^\+}{};
	return ($atbeg, $beg, '') if($sep eq '');
	$end =~ s{^\+}{};
	if($sep eq '_') {
		if(($atbeg eq '') || ($atend eq '')) {
			return undef
		}
		if($beg eq '') {
			$beg = $end
		} elsif($end eq '') {
			$end = $beg
		} elsif($beg != $end) {
			return undef
		}
	}
	$beg = 1 if(($sep eq ':') && ($atbeg eq '') && ($beg eq ''));
	($atbeg, $beg, $sep, $atend, $end)
}

sub conn_send_raw {
	my ($s, $conn, $data) = @_;
	defined($conn->send($data))
}

sub conn_recv_raw {
	my $s = shift();
	my $conn = shift();
	#  data = $_[0]
	my $len = $_[1];
	my $timeout = $_[2];
	if($timeout && !IO::Select->new($conn)->can_read($timeout)) {
		$s->error('timeout when reading socket');
		return ''
	}
	unless(defined($conn->recv($_[0], $len))) {
		$s->error('cannot receive from socket: ' . $!);
		return ''
	}
	if($_[0] eq '') {
		$s->error('connection closed unexpectedly');
		return ''
	}
	1
}

sub conn_send_smart {
	my ($s, $conn, $data) = @_;
	my $len = length($data);
	$s->conn_send_raw($conn, $len . (' ' x (32 - length($len))) . $data)
}

sub conn_recv_smart {
	my $s = shift();
	my $conn = shift();
	my $timeout = $_[1];
	my $len;
	$s->conn_recv_raw($conn, $len, 32, ($timeout // $s->timeout())) &&
		$len =~ m{^(\d+) +$} &&
		$s->conn_recv_raw($conn, $_[0], $1,
			(($timeout // 0) || $s->timeout()))
}

sub conn_send {
	my $s = shift();
	my $p = ($s->password());
	$s->conn_send_smart($_[0],
		(defined($p) ? &my_encrypt($p, $_[1]) : $_[1]))
}

sub conn_recv {
	my $s = shift();
	return '' unless($s->conn_recv_smart(@_));
	my $p = ($s->password());
	(!defined($p)) || &my_decrypt($p, $_[1])
}

sub my_encrypt {
	my $p = shift();
	$p->encrypt(&padding($_[0]))
}

sub my_decrypt {
	my $p = shift();
	return '' if(length($_[0]) % 16);
	$_[0] = $p->decrypt($_[0]);
	&unpadding($_[0]) || ($_[0] = '')
}

sub padding {
	my $str = sha256(rand() . rand() . rand() . rand()) . shift() . '17';
	my $mod = (length($str) & 0x0F);
	$mod ? ($str . ("z" x (16 - $mod))) : $str
}

sub unpadding {
	return '' if(length($_[0]) <= 32);
	$_[0] = substr($_[0], 32);
	$_[0] =~ s{17z*$}{}
}

1;
