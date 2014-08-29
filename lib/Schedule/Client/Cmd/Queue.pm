# Schedule::Client::Cmd::Queue.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Cmd::Queue;

use strict;
use warnings;
use integer;
use Cwd ();

use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Helpers qw(:IS :SYSQUERY signals);
#use Schedule::Client::Testarg;

our $VERSION = '4.2';

# Global variables:

my $s;

# Local variables:

my $exitstatus = 0;
my $unique = undef;
my $cancel;
my $destjob;

#
# Functions
#

sub queue_init {
	$s = &client_globals();
	$s->check_version()
}

sub queue {
	&queue_init();
	(my $runmode, $destjob, $cancel, my $keepdir, my $tests) = @_;
	my $query = ($runmode eq 'start-or-queue');
	if($query) {
		require Schedule::Client::Testarg;
		Schedule::Client::Testarg->import();
		&testarg_init($s);
		my $finished = ($tests->[1]);
		push(@$finished, ':') if(&test_empty($tests));
		$runmode .= &test_args($tests)
	}
	return '' unless(&openclient());
	&signals();
	my $success = &client_send(join("\c@", $runmode, $destjob, &my_user(),
		&my_hostname(), &my_hosttext(), &my_cwd($keepdir), @ARGV));
	$success = '' unless(&client_recv($unique));
	if($query) {
		$unique =~ m{^([^\c@]*)\c@(.*)};
		$runmode = $1;
		$unique = $2
	}
	my $job = 'job';
	if($unique =~ m{(\d+)$}) {
		$job .= ' @' . $1
	}
	&signals(\&cancel_job);
	return '' unless($success);
	if($runmode eq 'queue') {
		$s->forking();
		&client_recv(my $stat, 0);
		unless(($stat // '') eq 'run') {
			$exitstatus = (&is_nonnegative($stat) ? $stat : $cancel);
			&set_exitstatus($exitstatus);
			return 1
		}
	}
	return '' unless(&closeclient());
	my $sys = system(@ARGV);
	if($sys < 0) {
		$s->error($job . ' could not be executed') unless($s->quiet());
		$sys = 127
	} elsif($sys & 127) {
		$s->error($job . ' died with signal ' . ($sys & 127) .
			(($sys & 128) ? '' : ' (core dumped)'))
				unless($s->quiet());
		$sys = 127
	} else {
		$sys >>= 8;
		&jobinfo($job, $sys)
	}
	$exitstatus = $sys;
	&set_exitstatus($sys);
	&send_status($sys)
}

sub jobinfo {
	my ($job, $status) = @_;
	return if($s->quiet() || !$s->stdout_term());
	my $name = $s->name();
	my $stat = $status;
	if($s->color_stdout()) {
		$name = $s->incolor(0, $name);
		$stat = $s->incolor(2, $status) if($status)
	}
	if($status) {
		print("$name: $job exited with status $stat\n")
	} else {
		print("$name: $job finished\n")
	}
}

# Cancel a job (if "schedule queue" is interrupted by a signal):

sub cancel_job {
	&signals();
	&closeclient(1);
	#&send_status($cancel);
	&openclient(1) &&
		&client_send("cancel\c@$cancel\c@" . ($unique // $destjob)) &&
		&client_recv(my $reply) &&
		&client_send('close');
	exit($cancel)
}

sub send_status {
	# Sending exitstatus must not cause errors/warnings:
	&client_send("end\c@$unique\c@$exitstatus") if(&openclient(1));
	&closeclient(1);
	1
}

{ my $hostname = undef; # a static closure
sub my_hostname {
	return $hostname if(defined($hostname));
	$hostname = $ENV{'HOSTNAME'};
	unless(&is_nonempty($hostname)) {
		eval {
			require File::Which;
			File::Which->import();
			$hostname = hostname()
		};
		$hostname = '' unless($@ && defined($hostname));
		$hostname =~ s{\c@.*$}{}
	}
	$hostname
}}

{ my $hosttext = undef; # a static closure
sub my_hosttext {
	$hosttext //= $ENV{'HOSTTEXT'};
	return $hosttext if(defined($hosttext));
	my $olderr = undef;
	$olderr = undef unless(open($olderr, '>&', \*STDERR)
		&& open(STDERR, '>', File::Spec->devnull()));
	$hosttext = (`uname -m` // '');
	open(STDERR, '>&', $olderr) if(defined($olderr));
	chomp($hosttext);
	$hosttext =~ s{\c@.*$}{};
	$hosttext
}}

{ my $cwd = undef; # a static closure
sub my_cwd {
	return $cwd if(defined($cwd));
	$cwd = (Cwd::getcwd() // '');
	unless($_[0]) {
		my $home = ($ENV{'HOME'} // (getpwuid($<))[7]);
		if(&is_nonempty($home)) {
			if($home eq $cwd) {
				$cwd = '~'
			} else {
				$cwd =~ s{^\Q$home\E\/}{\~\/}o
			}
		}
	}
	$cwd =~ s{\c@.*$}{};
	$cwd
}}

'EOF'
