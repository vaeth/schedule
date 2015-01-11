# Schedule::Connect.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

# This is the "main" file of the schedule project, containing the
# common parts of schedule and schedule-server which are always needed

require 5.012;
package Schedule::Connect v7.0.2;

use strict;
use warnings;
use integer;
use Getopt::Long 2.24 ();
use File::Spec ();
use IO::Select ();
use version 0.77 ();
#use Crypt::Rijndael (); # needed for password protection
#use Digest::SHA ();     # needed for password protection
#use POSIX (); # needed for --detach (and recommended for --bg, --daemon)
#use Pod::Usage (); # optional, but no manpage or help without this

use Schedule::Helpers qw(:COLOR :IS :SYSQUERY);

our $VERSION; # auto-initialized to the version of Schedule::Connect

# The default minimal/maximal/exact accepted versions for the modules/programs.
# If undefined, no corresponding restriction is required.

my $minversion = version->declare('v7.0.0');
my $maxversion = $VERSION;
my $extversion = undef;

# The client accepts servers in the followin interval:

my $servermin = $minversion;
my $serversup = version->declare('v8.0.0');
my $serversupallowed = '';

# Exceptions overriding the above global rules.
# Each file is referred to by the module name appearing on top of the file.
# (For files in lib/* this is * without .pm and with / replaced by ::, e.g.
# this file lib/Schedule/Connect.pm is referred to as Schedule::Connect
# The files bin/schedule and bin/schedule-server are referred to as
# Schedule and ScheduleServer).
# For modules not appearing here, the above defaults apply.
# If "undefined", no corresponding restriction is required.

my %minversion = (
# temporary:

# Keep the following always:
	'Schedule::Connect' => undef
);

my %maxversion = (
# Keep the following always:
	'Schedule::Connect' => undef
);

my %extversion = (
# Keep the following always:
	'Schedule::Connect' => undef
);

# Static variables:

my $have_posix = undef;

sub new {
	my ($class, $name, $ver) = @_;
	$0 = $name;
	my $s = bless({
		name => $name,
		check => '',
		alpha => [],
		alpha_ignore => '',
		did_alpha => '',
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
	}, $class);
	$s->check_version($name, $ver);
	$s->check_version('Schedule::Helpers');
	$s
}

sub version {
	$VERSION
}

sub name {
	my $s = shift();
	$s->{name}
}

sub check {
	my $s = shift();
	@_ ? ($s->{check} = shift()) : $s->{check}
}

sub daemon {
	my $s = shift();
	@_ ? ($s->{daemon} = shift()) : $s->{daemon}
}

sub alpha {
	my $s = shift();
	@_ ? ($s->{alpha} = shift()) : $s->{alpha}
}

sub did_alpha {
	my $s = shift();
	@_ ? ($s->{did_alpha} = shift()) : $s->{did_alpha}
}

sub alpha_ignore {
	my $s = shift();
	@_ ? ($s->{alpha_ignore} = shift()) : $s->{alpha_ignore}
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

sub servermin {
	$servermin
}

sub serversup {
	$serversup
}

sub serversupallowed {
	$serversupallowed
}

sub fatal {
	&error(@_);
	exit(1)
}

sub error {
	my $s = shift();
	my $name = $s->name();
	my $error = 'error';
	my $colon = ': ';
	my $len = length($name) + length($error) + (2 * length($colon));
	if($s->color_stderr()) {
		$name = $s->incolor(0, $name);
		$error = $s->incolor(2, $error)
	}
	print(STDERR $name, $colon, $error, $colon,
		join("\n" . (' ' x $len), @_), "\n")
}

sub warning {
	my $s = shift();
	my $name = $s->name();
	my $warning = 'warning';
	my $colon = ': ';
	my $len = length($name) + length($warning) + (2 * length($colon));
	if($s->color_stderr()) {
		$name = $s->incolor(0, $name);
		$warning = $s->incolor(2, $warning)
	}
	print(STDERR $name, $colon, $warning, $colon,
		join("\n" . (' ' x $len), @_), "\n")
}

{ # some static closures
	my $reset_col = undef;
	my $name_col = undef;
	my $warn_col = undef;
	my $err_col = undef;
sub incolor {
	my $s = shift();
	my $mode = shift();
	$reset_col //= &my_color('reset');
	return (($name_col //= &my_color('bold')) . $_[0] . $reset_col)
		unless($mode);
	($mode == 1) ?
		(($warn_col //= &my_color('bold cyan')) . $_[0] . $reset_col) :
		(($err_col //= &my_color('bold red')) . $_[0] . $reset_col)
}}

sub check_version {
	my $s = shift();
	my $name = (@_ ? shift() : caller());
	my $ver;
	if(@_) {
		$ver = $_[0]
	} else {
		no strict 'refs';
		$ver = ${"$name\::VERSION"}
	}
	my $m = (exists($minversion{$name}) ? $minversion{$name} : $minversion);
	$s->fatal($name . ' ' . $ver->stringify() .
		' too old (at least ' . $m->stringify() . ' required)')
		if(defined($m) && ($ver < $m));
	$m = (exists($maxversion{$name}) ? $maxversion{$name} : $maxversion);
	$s->fatal($name . ' ' . $ver->stringify() .
		' too new (at most ' . $m->stringify() . ' supported)')
		if(defined($m) && ($ver > $m));
	$m = (exists($extversion{$name}) ? $extversion{$name} : $extversion);
	$s->fatal($name . ' ' . $ver->stringify() .
		' wrong version (' . $m->stringify() . ' required)')
		if(defined($m) && ($ver != $m))
}

sub check_queue {
	my $s = shift();
	$s->usage('only supported: queue, start, start-or-queue, help, man')
		if($s->check())
}

sub usage {
	my $s = shift();
	my $o = ((scalar(@_) <= 1) ? ($_[0] // 1) : {@_});
	$o = (&is_nonnegative($o) ? {-exitval => $o} : {-message => $o})
		unless(ref($o) eq 'HASH');
	my @name;
	if($s->check()) {
		require Schedule::Client::Tmuxman;
		&Schedule::Client::Tmuxman::man_tmux_init($s);
		@name = qw(Schedule Client Tmuxman.pm)
	} elsif(($s->name()) =~ m{serv}i) {
		require Schedule::Server::Serverman;
		&Schedule::Server::Serverman::man_server_init($s);
		@name = qw(Schedule Server Serverman.pm)
	} else {
		require Schedule::Client::Scheduleman;
		&Schedule::Client::Scheduleman::man_schedule_init($s);
		@name = qw(Schedule Client Scheduleman.pm)
	}
	$o->{'-input'} = File::Spec->catfile(@name);
	$o->{'-pathlist'} = \@INC;
	require Pod::Usage;
	Pod::Usage::pod2usage($o)
}

sub get_options {
	my $s = shift();
	my @passfile = ();
	my $quiet = 0;
	Getopt::Long::Configure(qw(
		bundling
		gnu_compat
		no_getopt_compat
		no_ignore_case
		require_order
	));
	Getopt::Long::GetOptions(
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
	'alpha|a=s', $s->alpha(),
	'alpha-ignore|J', sub { $s->alpha_ignore(1) },
	'background|bg|b', sub { $s->daemon(0) },
	'daemon|B', sub { $s->daemon(1) },
	'detach|E', sub { $s->daemon(-1) },
	'quiet|q+', \$s->{quiet},
	'check', sub { $s->check(1) },
	'help|h', sub { $s->usage(1) },
	'man|?', sub { $s->usage(-verbose => 2) },
	'version|V', sub { print($s->name(), ' ', $VERSION->stringify(), "\n");
		exit(0) },
	@_) or $s->usage(2);
	if(@ARGV) {
		if($ARGV[0] =~ m/^man/i) {
			$s->usage(-verbose => 2)
		} elsif($ARGV[0] =~ m/^help/i) {
			$s->usage(0)
		}
	}
	# Read password file before dropping permissions
	for my $passfile (@passfile) {
		next unless(open(my $fh, '<', $passfile));
		binmode($fh);
		my $pw = do { local $/; <$fh> }; # slurp!
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
	my $daemon = $s->daemon();
	if(defined($daemon) && !defined($have_posix)) {
		eval {
			require POSIX
		};
		if($@) {
			my @err=('you might need to install perl module POSIX',
				$@);
			if($daemon < 0) {
				$s->fatal(@err)
			} else {
				$s->warning(@err) unless($s->quiet())
			}
			$have_posix = ''
		} else {
			$have_posix = 1
		}
	}
	return unless(defined($s->password()));
	eval {
		require Crypt::Rijndael
	};
	$s->fatal('you might need to install perl module Crypt::Rijndael', $@)
		if($@);
	eval {
		require Digest::SHA
	};
	$s->fatal('you might need to install perl module Digest::SHA', $@)
		if($@);
	my $hash = Digest::SHA::sha256($s->password());
	my $p = Crypt::Rijndael->new($hash, Crypt::Rijndael::MODE_CFB());
	$p->set_iv('a' x 16);
	$s->password($p)
}

sub exec_alpha {
	my $s = shift();
	$s->did_alpha(1);
	my $alpha = $s->alpha();
	return 0 unless(@$alpha);
	my $sys = system(@$alpha);
	my $errtext;
	if($sys < 0) {
		$errtext = 'alpha-command could not be executed';
		$sys = 127
	} elsif($sys & 127) {
		$errtext = 'alpha-command died with signal ' . ($sys & 127) .
			(($sys & 128) ? '' : ' (core dumped)');
		$sys = 127
	} else {
		$sys >>= 8;
		return 0 unless($sys);
		$errtext = 'alpha-command exited with status ' . $sys
	}
	if($s->alpha_ignore()) {
		$s->warning($errtext) unless($s->quiet());
		return 0
	}
	$s->error($errtext);
	$sys
}

sub forking {
	my $s = shift();
	return 1 unless(defined(my $d = $s->daemon()));
	my $pid = fork();
	$s->error('forking failed; running in foreground')
		unless(defined($pid));
	if($pid) {
		if($have_posix) {
			POSIX::_exit(0)
		} else {
			exit(0)
		}
	}
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
	my $str = Digest::SHA::sha256(rand() . rand() . rand() . rand()) . shift() . '17';
	my $mod = (length($str) & 0x0F);
	$mod ? ($str . ("z" x (16 - $mod))) : $str
}

sub unpadding {
	return '' if(length($_[0]) <= 32);
	$_[0] = substr($_[0], 32);
	$_[0] =~ s{17z*$}{}
}

1;
