# Schedule::Client::Clientfuncs.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Clientfuncs;

use strict;
use warnings;
use integer;
use Exporter qw(import);
use IO::Socket (); # INET or UNIX, depending on user's choice

use Schedule::Helpers qw(is_nonempty);

our $VERSION = '4.2';

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

{ # A static variable:
	my $checked = '';
sub openclient {
	$socket = ($s->tcp() ? new IO::Socket::INET(
		PeerAddr => $s->addr(),
		PeerPort => $s->port(),
		Type => IO::Socket::SOCK_STREAM()
	) : new IO::Socket::UNIX(
		Peer => $s->file(),
		Type => IO::Socket::SOCK_STREAM()
	));
	unless(defined($socket)) {
		my $silence = (shift() // '');
		$s->error("unable to setup socket: $!",
			'maybe you should run first: schedule-server --daemon')
			unless($silence);
		return ''
	}
	return 1 if($checked);
	my $ver;
	if(&client_send('version') && &client_recv($ver) &&
		&is_nonempty($ver)) {
		unless($ver eq ('schedule-server ' . $s->version())) {
			$s->error($ver .
				' does not match schedule ' . $s->version());
			return ''
		}
	} else {
		$s->error('cannot connect to socket');
		return ''
	}
	$checked = 1
}}

sub closeclient {
	return 1 unless(defined($socket));
	my $ret = ($socket->close());
	$socket = undef;
	return 1 if($ret);
	my $silence = (shift() // '');
	$s->error("failed to close socket: $!") unless($silence);
	''
}

sub client_send {
	$s->conn_send($socket, @_)
}

sub client_recv {
	return 1 if($s->conn_recv($socket, @_));
	&closeclient(1);
	exit($exitstatus = 7)
}

# increase exitstatus to argument

sub set_exitstatus {
	my ($stat) = @_;
	$exitstatus = $stat if($exitstatus < $stat)
}

sub client_exit {
	$exitstatus = 7 unless(&closeclient() && $_[0]);
	exit($exitstatus)
}

'EOF'
