# Schedule::Client::Cmd::Queue.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

require 5.012;
package Schedule::Client::Cmd::Queue v7.0.0;

use strict;
use warnings;
use integer;
use Cwd ();

use Schedule::Client::Clientfuncs qw(:FUNCS);
use Schedule::Helpers qw(:IS :SYSQUERY signals join_quoted);
#use Schedule::Client::Testarg;

# Global variables:

my $s;

# Local variables:

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

{
	my ($status, $title, $text);
	my ($user, $host, $hosttext, $cwd, $job);
	my $jobtext;
sub queue {
	&queue_init();
	(my $runmode, $destjob, $cancel, my $ignore, my $immediate,
		my $keepdir, my $tests, $status, $title, $text) = @_;
	$s->fatal("illegal --ignore $ignore") if(defined($ignore) &&
		!(&is_nonnegative($ignore) && $ignore <= 0xFF));
	$s->fatal("illegal --immediate $immediate") if(defined($immediate) &&
		!(&is_nonnegative($immediate) && $immediate <= 0xFF));
	if($s->stdout_term()) {
		my $term = undef;
		$status //= (($term = ($ENV{'TERM'} // '')) =~
			m{^(?:xterm|screen|rxvt|aterm|konsole|gnome|Eterm|kterm|interix)});
		$title //= (($term // $ENV{'TERM'} // '') =~ m{^screen});
		if($status || $title) {
			$text //= '%a(%s)%u@%h%H:%c'
		} else {
			$text = undef
		}
	} else {
		$status = $title = '';
		$text = undef
	}
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
	($user, $host, $hosttext, $cwd) =
		(&my_user(), &my_hostname, &my_hosttext, &my_cwd($keepdir));
	my $success = &client_send(join("\c@", $runmode, $destjob, $user,
		$host, $hosttext, $cwd, @ARGV));
	$success = '' unless(&client_recv($unique));
	if($query) {
		$unique =~ m{^([^\c@]*)\c@(.*)};
		$runmode = $1;
		$unique = $2
	}
	if($unique =~ m{(\d+)$}) {
		$job = '@' . $1;
		$jobtext = 'job ' . $job
	} else {
		$job = '';
		$jobtext = 'job'
	}
	return '' unless($success);
	&signals(\&cancel_job);
	if($runmode eq 'queue') {
		if(!$s->did_alpha()) {
			my $ret = $s->exec_alpha();
			if($ret) {
				$cancel = $ret;
				&cancel_job()
			}
			$s->forking()
		}
		&statusbar('waiting');
		&client_recv(my $stat, 0);
		unless(($stat // '') eq 'run') {
			$stat = $cancel unless(&is_nonnegative($stat));
			&statusbar($stat);
			&set_exitstatus($stat);
			return 1
		}
	}
	return '' unless(&closeclient());
	my $ret;
	if(defined($immediate)) {
		$ret = &send_status($immediate);
		&signals()
	}
	&statusbar('running');
	my $sys = system(@ARGV);
	if($sys < 0) {
		$s->error($jobtext . ' could not be executed') unless($s->quiet());
		$sys = 127
	} elsif($sys & 127) {
		$s->error($jobtext . ' died with signal ' . ($sys & 127) .
			(($sys & 128) ? '' : ' (core dumped)'))
				unless($s->quiet());
		$sys = 127
	} else {
		$sys >>= 8;
		&jobinfo($sys)
	}
	&statusbar("$sys");
	&set_exitstatus($sys);
	unless(defined($immediate)) {
		$ret = &send_status($ignore // $sys);
		&signals()
	}
	$ret
}

sub jobinfo {
	my ($ret) = @_;
	return if($s->quiet() || !$s->stdout_term());
	my $name = $s->name();
	my $stat = $ret;
	if($s->color_stdout()) {
		$name = $s->incolor(0, $name);
		$stat = $s->incolor(2, $ret) if($ret)
	}
	if($ret) {
		print("$name: $jobtext exited with status $stat\n")
	} else {
		print("$name: $jobtext finished\n")
	}
}

# Cancel a job (if "schedule queue" is interrupted by a signal):

sub cancel_job {
	&signals();
	&closeclient(1);
	&statusbar($cancel);
	#&send_status($cancel);
	&openclient(1) &&
		&client_send("cancel\c@$cancel\c@" . ($unique // $destjob)) &&
		&client_recv(my $reply) &&
		&client_send('close');
	&closeclient(1);
	exit($cancel)
}

sub send_status {
	# Sending exitstatus must not cause errors/warnings:
	&client_send("end\c@$unique\c@" . $_[0]) if(&openclient(1));
	&closeclient(1);
	1
}

sub statusbar {
	return unless(defined(my $t = $text));
	my $stat = shift();
	my $replace = sub {
		my ($c) = @_;
		return $user if($c eq 'u');
		return $host if($c eq 'h');
		return ($hosttext eq '') ? '' : "($hosttext)" if($c eq 'H');
		return $cwd if($c eq 'd');
		return $job if($c eq 'a');
		return $stat if($c eq 's');
		if(($c eq 'c') || ($c eq 'C')) {
			return &join_quoted($ARGV[0]) if(@ARGV == 1);
			return $ARGV[0] if($c eq 'c');
			return &join_quoted(@ARGV)
		}
		$c
	};
	$t =~ s{\%([asuhHdcC\%])}{$replace->($1)}ge;
	$| = 1;
	print("\033]0;$t\007") if($status);
	print("\033k$t\033\\") if($title)
}
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

1;
