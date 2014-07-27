# Schedule::Connect.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project and under a BSD type license.

package Schedule::Connect;
#use Term::ANSIColor; # not mandatory but recommended: fallback to no color

use strict;
use warnings;
use integer;

use Getopt::Long;
use Pod::Usage;

use Schedule::Helpers qw(/./);

use Exporter qw(import);

our $VERSION = '0.12';

sub new {
	my ($class, $name, $ver) = @_;
	$0 = $name;
	my $s = bless {
		name => $name,
		tcp => 1,
		addr => '127.0.0.1',
		timeout => 10,
		port => 8471,
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

sub file {
	my $s = shift();
	@_ ? $s->{file} = shift() : $s->{file}
}

sub stdout_term {
	my $s = shift();
	my $ret = $s->{stdout_term};
	defined($ret) ? $ret : ($s->{stdout_term} = (-t STDOUT))
}

sub stderr_term {
	my $s = shift();
	my $ret = $s->{stderr_term};
	defined($ret) ? $ret : ($s->{stderr_term} = (-t STDERR))
}

sub force_color {
	my $s = shift();
	@_ ? $s->{force_color} = shift() : $s->{force_color}
}

sub color_stdout {
	my $s = shift();
	my $ret = $s->{color_stdout};
	return $ret if(defined($ret));
	my $force = $s->force_color();
	$s->{stdout_term} = ((defined($force) ? $force : ($s->stdout_term()))
		? &use_ansicolor() : '')
}

sub color_stderr {
	my $s = shift();
	my $ret = $s->{color_stderr};
	return $ret if(defined($ret));
	my $force = $s->force_color();
	$s->{stderr_term} = ((defined($force) ? $force : ($s->stderr_term()))
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
	Getopt::Long::Configure(qw(bundling gnu_compat no_permute));
	GetOptions(
	'help|h', sub { pod2usage(1) },
	'man|?', sub { pod2usage(-verbose => 2) },
	'version|V', sub { print($s->name(), " $VERSION\n"); exit(0) },
	'tcp|t', sub { $s->tcp(1) },
	'local|l', sub { $s->tcp('') },
	'color|F', sub { $s->color_force(1) },
	'no-color|nocolor|p', sub { $s->color_force('') },
	'port|P=i', sub { $s->tcp(1); $s->port($_[1]) },
	'addr|A=s', sub { $s->tcp(1); $s->addr($_[1]) },
	'file|f=s', sub { $s->tcp(''); $s->file($_[1]) },
	'timeout|T=i', sub { $s->timeout($_[1]) },
	@_) or pod2usage(2);
	return unless(@ARGV);
	if($ARGV[0] =~ m/^man/i) {
		pod2usage(verbose => 2)
	} elsif($ARGV[0] =~ m/^help/i) {
		pod2usage(0)
	}
}

sub check_options {
	my $s = shift();
	my $timeout = $s->timeout();
	$s->fatal("illegal timeout $timeout")
		unless(&is_nonnegative($timeout));
	my $port = $s->port();
	$s->fatal("illegal port $port")
		unless(&is_nonnegative($port) && ($port <= 0xFFFF))
}

sub default_filename {
	my $s = shift();
	return '' if(defined($s->file()));
	$s->file(File::Spec->catfile(File::Spec->tmpdir(),
		'schedule-' . &my_user(), 'server'));
	1
}

sub conn_recv {
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

sub conn_send {
	my ($s, $conn, $data) = @_;
	defined($conn->send($data))
}

1;
