# Schedule::Client::Clientfuncs.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

BEGIN { require 5.012 }
package Schedule::Client::Clientfuncs v8.0.0;

use strict;
use warnings;
use integer;
use feature 'state';

use Exporter qw(import);
use IO::Socket 1.19 (); # INET or UNIX, depending on user's choice

use Schedule::Helpers qw(is_nonempty);

my @export_funcs = qw(
	client_globals
	openclient
	closeclient
	client_send
	client_recv
	set_exitstatus
);

my @export_init = qw(
	client_init
	client_exit
);

our @EXPORT_OK = (@export_funcs, @export_init);
our %EXPORT_TAGS = (
	INIT => [@export_init],
	FUNCS => [@export_funcs]
);

# Global variables:

my $s;

# Static variables:

my $socket = undef;
my $exitstatus = 0;

#
# Functions
#

sub client_init {
	$s = $_[0];
	$s->check_version()
}

sub client_globals {
	$s
}

sub openclient {
	$socket = $s->timeout($s->tcp() ? sub { IO::Socket::INET->new(
		PeerAddr => $s->addr(),
		PeerPort => $s->port(),
		Type => IO::Socket::SOCK_STREAM()
	)} : sub { IO::Socket::UNIX->new(
		Peer => $s->file(),
		Type => IO::Socket::SOCK_STREAM()
	)});
	if ($@ eq 'timeout') {
		my $silence = (shift() // '');
		$s->error('timeout when setting up socket') unless ($silence);
		return ''
	}
	unless (defined($socket)) {
		my $silence = (shift() // '');
		$s->error("unable to setup socket: $!",
			'maybe you should run first: schedule-server --daemon')
			unless ($silence);
		return ''
	}
	state $checked = '';
	return 1 if ($checked);
	my $ver;
	if (&client_send('version') && &client_recv($ver) &&
		&is_nonempty($ver)) {
		&check_server_version($ver) || return ''
	} else {
		$s->error('cannot connect to socket');
		return ''
	}
	$checked = 1
}

sub check_server_version {
	my ($v) = @_;
	unless ($v =~ s{^schedule\-server }{}) {
		$s->error('schedule-server did not send its version');
		return ''
	}
	my $ver = undef;
	eval {
		$ver = version->parse($v)
	};
	if ((!defined($ver)) || $@) {
		$s->error('schedule-server sent invalid version');
		return ''
	}
	my $m = $s->servermin();
	if (defined($m) && ($ver < $m)) {
		$s->error('schedule-server ' . $ver->stringify() .
			' too old (at least ' .
			$m->stringify() . ' required)');
		return ''
	}
	$m = $s->serversup();
	return 1 unless (defined($m));
	if ($s->serversupallowed()) {
		if ($ver > $m) {
			$s->error('schedule-server ' . $ver->stringify() .
				' too new (at most ' .
				$m->stringify() . ' supported)');
			return ''
		}
	} elsif ($ver >= $m) {
		$s->error('schedule-server ' . $ver->stringify() .
			' too new (must be before ' . $m->stringify() . ')');
		return ''
	}
	1
}

sub closeclient {
	return 1 unless (defined($socket));
	my $ret = ($socket->close());
	$socket = undef;
	return 1 if ($ret);
	my $silence = (shift() // '');
	$s->error("failed to close socket: $!") unless ($silence);
	''
}

sub client_send {
	$s->conn_send($socket, @_)
}

sub client_recv {
	return 1 if ($s->conn_recv($socket, @_));
	&closeclient(1);
	exit($exitstatus = 7)
}

# increase exitstatus to argument

sub set_exitstatus {
	my ($stat) = @_;
	$exitstatus = $stat if ($exitstatus < $stat)
}

sub client_exit {
	$exitstatus = 7 unless (&closeclient() && $_[0]);
	exit($exitstatus)
}

1;
