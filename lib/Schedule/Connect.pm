# Schedule::Connect.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project and under a BSD type license.

package Schedule::Connect;

use strict;
use warnings;
use integer;

use Getopt::Long;
use Pod::Usage;

use Schedule::Helpers qw(is_nonnegative);

use Exporter qw(import);

our $VERSION = '0.8';

sub new {
	my ($class, $name, $ver) = @_;
	my $s = bless {
		name => $name,
		tcp => 1,
		addr => '127.0.0.1',
		timeout => 10,
		port => 8471,
		file => undef
	}, $class;
	$s->fatal("$name version $ver differs from Schedule.pm version $VERSION")
		if(defined($ver) && ($ver ne $VERSION));
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

sub fatal {
	my $s = shift();
	my $name = $s->name();
	print(STDERR "$name: error: ",
		join("\n" . (' ' x (length($name) + 9)), @_), "\n");
	exit(1)
}

sub error {
	my $s = shift();
	my $name = $s->name();
	print(STDERR "$name: error: ",
		join("\n" . (' ' x (length($name) + 9)), @_), "\n")
}

sub warning {
	my $s = shift();
	my $name = $s->name();
	print(STDERR "$name: warning: ",
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
	return 1 if(defined($s->file()));
	my $user = getpwuid($<);
	$user = $< unless(defined($user) && ($user ne ''));
	$s->file(File::Spec->catfile(File::Spec->tmpdir(),
		'schedule-' . $user, 'server'))
}

sub conn_recv {
	my $s = shift();
	my $conn = shift();
	my $timeout = $_[1];
	my $len = $_[2];
	$timeout = $s->timeout() unless(defined($timeout) && ($timeout ne ''));
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
