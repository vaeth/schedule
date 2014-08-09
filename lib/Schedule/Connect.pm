# Schedule::Connect.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project and under a BSD type license.

package Schedule::Connect;
#use Term::ANSIColor; # not mandatory but recommended: fallback to no color
#use Crypt::Rijndael; # needed for password protection
#use Digest::SHA;     # needed for password protection

use strict;
use warnings;
use integer;

use Getopt::Long;
use Pod::Usage;

use Schedule::Helpers qw(/./);

use Exporter qw(import);

our $VERSION = '1.0';

sub new {
	my ($class, $name, $ver) = @_;
	$0 = $name;
	my $s = bless {
		name => $name,
		tcp => 1,
		addr => '127.0.0.1',
		timeout => 10,
		port => 8471,
		password => undef,
		stdout_term => undef,
		stderr_term => undef,
		color_stdout => undef,
		color_stderr => undef,
		color_force => undef,
		file => undef
	}, $class;
	$s->fatal("$name version $ver differs from Schedule.pm version $VERSION")
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

sub tcp {
	my $s = shift();
	@_ ? $s->{tcp} = shift() : $s->{tcp}
}

sub addr {
	my $s = shift();
	@_ ? $s->{addr} = shift() : $s->{addr}
}

sub timeout {
	my $s = shift();
	@_ ? $s->{timeout} = shift() : $s->{timeout}
}

sub port {
	my $s = shift();
	@_ ? $s->{port} = shift() : $s->{port}
}

sub password {
	my $s = shift();
	@_ ? $s->{password} = shift() : $s->{password}
}

sub file {
	my $s = shift();
	@_ ? $s->{file} = shift() : $s->{file}
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
	@_ ? $s->{color_force} = shift() : $s->{color_force}
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
	Getopt::Long::Configure(qw(bundling gnu_compat no_permute));
	GetOptions(
	'help|h', sub { pod2usage(1) },
	'man|?', sub { pod2usage(-verbose => 2) },
	'version|V', sub { print($s->name(), " $VERSION\n"); exit(0) },
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

sub default_filename {
	my $s = shift();
	return '' if(defined($s->file()));
	$s->file(File::Spec->catfile(File::Spec->tmpdir(),
		'schedule-' . &my_user(), 'server'));
	1
}

sub conn_recv_raw {
	my $s = shift();
	my $conn = shift();
	my $timeout = $_[1];
	my $len = $_[2];
	$timeout = $s->timeout() unless(&is_nonempty($timeout));
	if(&is_nonnegative($timeout) && $timeout &&
		!IO::Select->new($conn)->can_read($timeout)) {
		$s->error('timeout when reading socket');
		return ''
	}
	unless(defined($conn->recv($_[0],
		(&is_nonnegative($len) && length($len) < 9) ? $len : 0x2000))) {
		$s->error('cannot receive from socket: ' . $!);
		return ''
	}
	1
}

sub conn_send_raw {
	my ($s, $conn, $data) = @_;
	defined($conn->send($data))
}

sub conn_send {
	my $s = shift();
	my $p = ($s->password());
	defined($p) ? $s->conn_send_raw($_[0], &my_encrypt($p, $_[1])) :
		$s->conn_send_raw(@_)
}

sub conn_recv {
	my $s = shift();
	my $p = ($s->password());
	return $s->conn_recv_raw(@_) unless(defined($p));
	my $len = $_[3];
	$s->conn_recv_raw($_[0], $_[1], $_[2],
		((&is_nonnegative($len) && $len) ? ($len + 64) : $len))
		&& &my_decrypt($p, $_[1])
}

sub my_encrypt {
	my $p = shift();
	$p->encrypt(&padding($_[0]))
}

sub my_decrypt {
	my $p = shift();
	return '' if(length($_[0]) % 16);
	$_[0] = $p->decrypt($_[0]);
	&unpadding($_[0])
}

sub padding {
	my $str = sha256(rand() . rand() . rand() . rand()) . shift() . '17';
	my $mod = (length($str) & 0x0F);
	$mod ? ($str . ("z" x (16 - $mod))) : $str
}

sub unpadding {
	$_[0] = substr($_[0], 32);
	$_[0] =~ s{17z*$}{}
}

1;
