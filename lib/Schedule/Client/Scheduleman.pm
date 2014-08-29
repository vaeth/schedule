# Schedule::Client::Scheduleman.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

package Schedule::Client::Scheduleman;

use strict;
use warnings;
use integer;

our $VERSION = '4.2';

=head1 NAME

schedule - queue jobs for later execution and schedule them

=head1 SYNOPSIS

=over 8

=item B<schedule> [options] B<queue>|B<start>|B<start-or-queue> I<cmd> [I<args> ...]

=item B<schedule> [options] I<command> [I<jobs> ...]

=item B<schedule> [options] I<stop-server>

=back

I<command> is one of:

B<run>, B<exec>, B<bg>, B<parallel>, B<wait>, B<list>, B<status>,
B<ok>, B<finished>, B<started>, B<cancel>, B<remove>, B<insert>,
B<address>, B<number>

commands can be shortcut by the shortest sequence which makes them unique.
For instance, B<q> can be used instead of B<queue>, B<r> instead of B<run>.
B<s> (despite being non-unique) can be used instead of B<start>.
Moreover, B<start-or-queue> can be abbreviated as anything containing B<s>
and B<q>.

I<jobs> is either a job number, a job address (absolute or relative),
a job range, or a job address range, see the section B<SPECIFYING JOBS>.
Each I<jobs> can also start with a leading B</>
which indicates that the range (or value) is considered static.
If no I<jobs> arguments are given, the value B<:> is assumed
(which means to select all jobs).

The exit status is usually the largest exit status of the scheduled command.
In case of a fatal communication error (e.g. server not started) the
exit status 7 is returned.

Use B<schedule-server man> or B<schedule man> to get a verbose manpage
for the server or client, respectively.

=head1 DESCRIPTION

The idea of this project is that you can B<queue> jobs by "starting"
them e.g. in different shells (possibly with different users or in chroots)
and by using various commands.

The "queued" jobs are not immediately executed but only in the moment when
you B<run> them from some scheduler script.
This scheduler script is meant to be a very simple ad-hoc script and can
even be a single shell command like

=over 8

B<schedule run>

=back

(this example would simply execute all queued jobs sequentially).

=head1 EXAMPLE 1

To initialize the whole system you must run eventually B<schedule init>
(this can be run from your machines init system).

Then run in three different shells the three commands

=over 8

=item B<schedule start-or-queue emerge -NDu @world>

=item B<schedule start-or-queue revdep-rebuild>

=item B<schedule start-or-queue shutdown -h now>

=back

and then in a fourth shell B<schedule run>.
Then the above three commands will be executed in order.
If during the execution you realize that you want to cancel execution of the
last command, you just press Ctrl-C in the shell where you started the last
command and use other B<schedule> calls to e.g. insert something before the
last command. Then you invoke the above command again.

=head1 EXAMPLE 2

Run in different shells the following commands

=over 8

=item B<schedule calculate 1>

=item B<schedule calculate 2>

=item B<schedule calculate 3>

=item B<schedule shutdown -h now>

=back

and then in a further shell

=over 8

=item B<schedule run 1> && B<schedule parallel 2:3> && B<schedule run>

=back

This runs first B<calculate 1> and upon a succesfull finishing
B<calculate 2> and B<calculate 3> in parallel.
When both are succesfully finished, B<shutdown -h now> is executed.

=head1 COMMANDS

=over 8

=item B<queue> I<cmd> [I<args> ... I<args>]

Queue I<cmd> I<args> ... I<args> for execution.
The command will be executed using the shell.

The following environment variables are used for later output with
B<schedule list>:

=over 16

=item B<HOSTNAME>

If defined, this is used instead of the host name.

=item B<HOSTTEXT>

If B<HOSTTEXT> is nonempty, B<schedule list> will output it
in braces after the host name (unless B<--no-host> is used).
This can be used to distinguish e.g. different chroots on the same host.
If this variable is undefined, the output of B<uname -m> is used.

=item B<HOME>

Unless you specify B<--keep-dir>, this is used to shortcut the path of the
current directory.

=back

=item B<start> I<cmd> [I<args> ... I<args>]

As B<queue>, but start the command immediately without waiting for a
further signal through B<schedule>.

=item B<start-or-queue> I<cmd> [I<args> ... I<args>]

Act as B<start> if all jobs specified through the options
B<--ok>, B<--finished>, B<--started> meet the corresponding requirements;
otherwise act as B<queue>.
If none of the options B<--ok>, B<--finished>, or B<--started> is specified,
act as if B<--finished :> would have been specified, that is, B<start> is
executed only if there is not any unfinished job in the queue.

=item B<run> I<jobs>

Starts the selected jobs (sequentially) if they have not already
been started. The exit status is the largest exit status of all I<jobs>.
If a job has already been started, the command will wait for its finishing.
If it already has been finished it is not started again, but the exit status
is taken into account.

The command is not race-free, that is, it is somewhat similar to calling
B<schedule run> I<job> for each I<job> separately (for job ranges of the
type B<:> or I<start>B<:> the end being changed dynamically).

This is intentional so that modification of the job queue has effect
to the command while it is running. If you do not want this, see the details
in the section B<SPECIFYING JOBS>: Static job numbers or static job ranges
are not subject to this race condition, Also jobs addresses avoid this
race condition in a sense.

=item B<exec> I<jobs>

This is like B<schdeule run> but breaks further execution if a job exits
with nonzero status. Note that also finished jobs can have nonzero exit status.

Similarly to B<run>, this command is not race-free, but static jobs and
static job ranges are supported.

=item B<wait> I<jobs>

This waits until all specified jobs have been finished and
returns the largest exit status.

Similarly to B<run>, this command is not race-free, but static jobs and
static job ranges are supported.

=item B<bg> I<jobs>

This is similar to B<schedule run> but starts all non-started B<jobs> in
parallel without ever waiting (and then returns).
In contrast to the B<--bg> option, no process is forked.
In contrast to B<schedule run>, this command is not subject to a race
condition.

=item B<parallel> I<jobs>

This is similar to running B<schedule bg> followed by B<schedule wait>
where all arguments are interpreted as B<static> jobs/job ranges.
However, this would have a race (if the queue is modified between the two
commands) which is avoided with B<schedule parallel>.

In other words, B<parallel> starts the specified jobs in background and
waits for them to finish, even if the queue is extended or ordered differently
during the execution of these jobs.

Similarly to B<run> with static jobs there is one exception of this rule:
If commands are removed from the queue while the commands are running,
they are considered to be finished, and their exit status is assumed to be 0.

=item B<list> I<jobs>

Lists the queued jobs, their addresses, their exit status (or whether
they are waiting/running, respectively), the user/host/current directory and
command line of the scheduled commands. The output can be influenced
by the options B<--no-user>, B<--no-host>, B<--no-dir>, or B<--no-command>.

=item B<status> I<jobs>

This is a script-friendly variant of B<schedule list>:
It outputs only the exit status of the selected job (or "waiting" or
"running"), respectively, each output followed by a newline.
If a job is not in the queue, the value B<-> is output.

If used with B<--quiet>, nothing is output (except perhaps warnings/errors),
but the exit status is different: It is the largest exit status of all
finished I<jobs>. If used with B<--quiet>, it is an error if a job cannot
be found (and in this case the exit status is at least 1).

=item B<address> I<jobs>

This is a script-friendly variant of B<schedule list>:
This outputs the job addresses of the specified I<jobs>
(each output followed by a newline).
If a job cannot be found, the value B<0> is output.

=item B<number> I<jobs>

This is a script-friendly variant of B<schedule list>:
This outputs the number of the specified I<jobs> in the queue
(each output followed by a newline).
If a job cannot be found, the value B<0> is output.

For instance, B<schedule number 0> will effectively output the length of the
queue (since the last job number in the queue is its length, and B<0> is
output if there is no such job).

=item B<ok>|B<finished>|B<started>

This is a more script-friendly and race-free form of B<status>,
without any output (except in error cases):
It returns with exit status 0 if all jobs specified through the options
B<--ok>, B<--finished>, B<--started> meet the corresponding requirements.
(The I<jobs> arguments are quivalent to using the corresponding
B<--ok>, B<--finished>, or B<--started> options with these arguments,
respectively.)
If none of these options is specified and no I<jobs> argument is given,
the command acts as if the argument B<:> is given for I<jobs>.
If the exit status is nonzero, it is the maximum of B<1> and of all exit values
of jobs specified through B<--ok>.

=item B<remove> I<jobs>

Remove I<jobs> from the list of B<queued> jobs and let them exit (with the
exit status specified by B<--exit> if that value is nonzero).

Note that if the job is already started it is not stopped, but its exit status
cannot be queried through B<schedule> anymore.

=item B<insert> I<jobs>

The list of queued jobs is ordered differently by shifting all specified I<jobs>
to to the location specified with B<--job>. Thus, if B<--job=1>,
all I<jobs> are shifted to the beginning of the list (renumbering the
previously first jobs). The special value B<--job=0> (default)
means to shift to the end of the list, and negative numbers count from the
end of the list. For instance B<schedule --job=-1 insert :2> will shift the
first two jobs one command before the end of the list.

=item B<cancel> I<jobs>

All of the I<jobs> which are not yet started, they will exit
(with the value specified by B<--exit> if that value is nonzero).

After this command, the scheduler behaves as if I<jobs> have finished
with the value specified by B<--exit> (or B<0> if that option
is not given).

It is explicitly admissible to "cancel" finished jobs: As concerns B<schedule>,
this will change their exit status. For instance, if job 1 has failed, then
B<schedule cancel 1> will set its exit status to B<0> so that a subsequent
B<schedule exec> will "ignore" this job.

=back

=head1 OPTIONS

The default of the options is taken from the environment variable
B<SCHEDULE_OPTS>; shell-quoting in the value is supported.
Moreover, (unquoted) environment variable references of the form $VAR
or ${VAR} in it are (recursively) expanded.

=over 8

=item B<--tcp> or B<-t>

Use a tcp socket (port) for IPC with the client(s). This is the default.
This option exists so that you can override an earlier specified
(e.g. set in B<SCHEDULE>) option B<-l>.

=item B<--local> or B<-l>

Use a unix domain socket (file) for IPC with the server.

=item B<--file=>I<file> or B<-f> I<file>

Use I<file> as a unix domain socket filename for IPC.
The default is B<${TMPDIR}/schedule-${USER}/server>.
This option implies B<--local> (unless overridden later on).

=item B<--port=>I<port> or B<-P> I<port>

Use port number I<port>; default is B<8471>.
This option implies B<--tcp> (unless overridden later on).

=item B<--addr=>I<addr> or B<-A> I<addr>

Bind to I<addr>. The default is 127.0.0.1 (localhost only).
This option implies B<--tcp> (unless overridden later on).

=item B<--timeout=>I<seconds> or B<-T> I<seconds>

Time to wait in case of communication problems; the default is 10 B<seconds>.
The value B<0> means to skip the timeout.

=item B<--passfile=>I<passfile> or B<-Y> I<passfile>

Read the first line from I<passfile> (without the newline)
and use it as a password to encrypt communication between B<schedule>
and B<schedule-server>. Both programs must use the same password for a
succesfull communication.

This option can be used accumulatively:
The first existing I<password-file> with a nonempty first line is used.
If no such file is found, this option is tacitly ignored.
This is to make it safe to specify this option in B<SCHEDULE_OPTS>
or B<SCHEDULE_OPTS> if no corresponding file exists.

=item B<--password=>I<password> or B<-y> I<password>

This is like B<--passfile>, with the difference that you specify the
password directly. This option is dangerous, because many systems allow
other users to see the commandline/environment (hence the password is visible).

=item B<--job=>I<jobnr> or B<-j> I<jobnr>

This describes where the job(s) should be inserted into the queue.
The special number B<0> means the end of the queue
(which may be the number of the last queued job or one later, depending
on the selected action); negative numbers count from the end of the list.
The default is B<0>.

This means e.g. that B<schedule queue> will by default queue new jobs after
the end of the queue while e.g. B<schedule insert> will shift the selected
jobs (in their order of selection) to the end of the queue.

=item B<--ok=>I<jobs> or B<-o> I<jobs>

This option can be used repeatedly; all arguments are collected.
I<jobs> can be as in the normal argument list (space-separated).
If used with B<start-or-queue>, B<ok>, B<finished>, B<started>,
check whether the listed jobs have been finished with zero exit status.

=item B<--background> or B<--bg> or B<-b>

For commands which are expected to be waiting (B<queue>, B<start-or-queue>
if the condition for immediate start are not satisfied, B<exec>, B<run>)
fork into background and return before the actual waiting begins.
To use this option, your system must know fork(), of course.

This is similar to using the B<&> in a shell, but in contrast to the latter,
a sequence of such commands does not give a race condition.
For instance, if you use B<schedule queue command1 & schedule queue command2 &>
it is partially random whether B<command1> is indeed queued in fron of
B<command1>.
By using instead B<schedule --bg command1 && schedule --bg command2>
this cannot happen.

This option is ignored for B<schedule --bg parallel>, since
B<schedule bg> has a similar effect but does not need to fork.

=item B<--daemon> or B<-B>

This is like B<--background>, but it also partially detaches from terminal
and discards all subsequent standard input/output.

=item B<--detach> or B<-E>

This is like B<--daemon>, but fully detaches from terminal, discarding also
error output. To use this option, your perl must have a functioning POSIX.
To avoid unexpected issues with relatice paths, the current working directory
is kept (and thus remains occupied). Therefore you might want to change to the
root directory before using this option.

=item B<--finished=>I<jobs> or B<-x> I<jobs>

This option can be used repeatedly; all arguments are collected.
I<jobs> can be as in the normal argument list (space-separated).
If used with B<start-or-queue>, B<ok>, B<finished>, B<started>,
check whether the listed jobs have been finished, independent of their
exit status.

=item B<--started=>I<jobs> or B<-s> I<jobs>

This option can be used repeatedly; all arguments are collected.
I<jobs> can be as in the normal argument list (space-separated).
If used with B<start-or-queue>, B<ok>, B<finished>, B<started>,
check whether the listed jobs have been started (finished jobs
are considered as started).

=item B<--no-user> or B<--nouser> or B<-u>

If this option is specified, B<schedule list> will suppress the output of
user, hostname, and B<HOSTTEXT>.

=item B<--no-host> or B<--nohost> or B<-H>

If this option is specified, B<schedule list> will suppress the output of
B<HOSTTEXT>.

=item B<--no-dir> or B<--nodir> or B<-D>

If this option is specified, B<schedule list> will suppress the output of
the current working directory for the scheduled command.

=item B<--no-command> or B<--nocommand> or B<-c>

If this option is specified, B<schedule list> will suppress the output of
the queued command.

=item B<--keep-dir> or B<--keepdir> or B<-d>

If this option is specified with B<queue>, B<start>, or B<start-or-queue>,
the current working directory is not shortcut using the B<HOME>
environment variable. This influences the later output with B<schedule list>.

=item B<--exit=>I<exitstatus> or B<-e> I<exitstatus>

For B<queue>, B<start>, or B<start-or-queue>: If the command is canceled by
one of the signals B<INT>, B<HUP>, or B<TERM>, then the command exits with
I<exitstatus> and also I<exitstatus> appears as exit status in the queue.
If the command if canceled indirectly by B<schedule cancel> or
B<schedule remove>, I<exitstatus> is the exit status
(with the execption described in the next sentence).

For B<cancel> or B<remove>: If I<exitstatus> is nonzero,
then I<exitstatus> is the exit status of the canceled/removed commands.

B<cancel> always sets the I<exitstatus> of the canceled job(s) in the queue
(independently of whether I<exitstatus> is zero or not).

The default value of I<exitstatus> is B<0>.

=item B<--color> or B<-F>

Try to color even if output is not a terminal.

=item B<--no-color> or B<--nocolor> or B<-p>

Do not color the output.
Setting the environment variable B<ANSI_COLORS_DISABLED> has the same effect.

=item B<--quiet> or B<-q> (accumulative)

Be quiet.

=item B<--help> or B<-h>

Display brief help.

=item B<--man> or B<-?>

Display extended help as a manpage.

=back

=head1 SPECIFYING JOBS

Whenever you have to pass a parameter which specifies a job,
you can do this by specifying the job number.
In this case, the number refers to the number in the queue.

If you specify the number 0 or a negative number, the counting is backwards
from the queue.

Note that the association of a number to the job can change when you rearrange
the queue (by the B<insert> or B<delete> command or by queuing new jobs
not at the end of the queue).
For this reason, there is also a possibility to specify jobs by their
addresses. A job address has the form B<@>I<number> and can be seen by
the output of the B<list> or B<address> command.
Such a job address does never change. However, it can become invalid:
If the job is removed from the queue, the address becomes invalid.

Besides these (absolute) job addresses, it is also possible to specify
relative job addresses which have the form B<@>I<number><summand>.
For instance, if you want to address that job which comes in the queue
immediately after the job with the address B<@5>, you would specify B<@5+1>.
Similarly, B<@4-5> means the job which comes in the queue 5 places before
job B<@4>.

In most occassions you can enter also job ranges or job address ranges.

A job range has the form I<from>B<:>I<to> where I<from> and I<to>
are job numbers or (relative or absolute) job addresses.
A job range consists of all jobs from the queue between B<from> and B<to>
(boundaries inclusive); if B<from> is omitted, the range consists of all jobs
in the queue until B<to> (inclusive) and if B<to> is ommitted, the range
consists of all jobs in the queue starting from B<from> (inclusive).
If B<to> comes before B<from> in the queue then the range is empty.

Some examples of job ranges:

=over 8

=item B<1:3>
B<:3>

These are both equivalent and mean the first three jobs in the queue.

=item B<-2:>

This gives the last three jobs in the queue (-2, -1, and 0).

=item B<:>

This means all jobs in the queue. This is the default, for instance,
if you specify no further arguments after B<schedule run>.

=item B<2:1>

This strange example specifies an empty job range. You can use this if
for some reason you want to override the default B<:> and really want to
specify B<no> jobs (although this hardly ever makes any sense).

=item B<@2:@1>

This can be a nonempty job range, since it can happen that the job with
address B<@2> appears in the queue before that with address B<@1>.

=item B<@1-1:@1+2>

This consists of 4 jobs: The job in the queue before that with address B<@1>,
then the job B<@1>, and the two subsequent ones in the queue.

=item B<@1+1:@1>

This is the empty range (or an error if there is no job with address B<@1>
in the queue).

=back

A job address range has the form I<from>B<_>I<to>, where I<from> and I<to>
are (absolute or relative) job addresses. This is just a convenience shortcut
and means all addresses with address numbers between that from I<from> and
I<to>. (The queue is ignored here.)

If you specify relative addresses in I<from> and I<to>, the summand may occur
either in I<from> or in I<to>, but it is invalid to specify different
summands, of course.

Some examples of job address ranges:

=over 8

=item B<@1_@3>

The range consists of the three jobs with addresses B<@1>, B<@2>, and B<@3>.

=item B<@2_@1>

This is the empty range. Not to be confused with B<@2:@1> which can be
nonempty (see the earlier examples).

=item B<@2-1_@4-1> or B<@2-1_@4> or B<@2_@4-1>

These all mean the same, namely the three jobs with the relative addressses
B<@2-1>, B<@3-1>, and B<@4-1>. In other words, these are the three jobs in the
queue before those with the respective job addresses B<@2>, B<@3>, and B<@4>.

=item B<@2-1_@4-2>

This makes no sense.

=back

All job numbers, job addresses, job ranges, and job address ranges can also
be marked to be "static". This makes only sense for the commands
B<exec>, B<run>, and B<wait> which can be subject to a race condition.

Marking a range or an address as "static" is similar to specifying a
corresponding absolute job address or absolute job address range,
where the address is resolved in the moment when the command is started.
The only differences is that the job address(es) are also associated with
the server, that is, the corresponding job is considered to be removed from
the queue even if the schedule-server has been shut down and restarted and
another job with the same address has been queued with that new
schedule-server.

To mark a range or an address static, simply preceed it with "/".
You can mark only a whole range (or address range) static, not individual
addresses in it. For example, B</1:2> means that the whole range B<1:2>
is considered to be static; the syntax B<1:/2> is invalid.

Examples with static ranges:

=over 8

=item B<schedule run /5:7 /0 /: :>

This will run the jobs 5, 6, 7, and the last from the current queue, followed
by all of the rest of the current queue, followed by all commands which are
possibly added to the queue until this happens.

=item B<schedule run /:4 /5:0>

=item B<schedule run /:0>

=item B<schedule run /:>

These are all equivalent: They start all jobs of the current queue
successively, independent of later modifications of the queue.

=item B<schedule run :4 5:0>

=item B<schedule run :0>

=item B<schedule run :>

In contrast to the previous example, these are not equivalent:
They differ in the moment when B<0> is evaluated (and replaced by the
last number in the queue). In the first case, B<0> is evaluated in the
moment when the 5th job gets started, in the second case immediately,
and in the last case changes in the length of the queue are always honoured.

=item B<schedule run @1_@4>

=item B<schedule run /@1_@4>

Despite job addresses are used, these two commands are not completey
equivalent: the latter binds the addresses also to the server
as mentioned before, that is, it is not possible to "trick" it by
exchanging the server and starting new jobs with addreses B<@2> B<@3>,
or B<@4> (job B<@1> is started immediately, so for this job there is no race).

=item B<schedule run @1 /@1+1>

The last argument looks like a relative job address, but it only partially
behaves like such: It is the job which is queued after the job with the
address B<@1> when the command is executed, even if that queue will change
while that job is running. Without the B</> symbol the job actually referred
to might change.

=back

=head1 COPYRIGHT AND LICENSE

Copyright Martin VE<auml>th. This project is under the BSD license.

=head1 AUTHOR

Martin VE<auml>th E<lt>martin@mvath.deE<gt>

=cut

sub man_schedule_init {
	my ($s) = @_;
	$s->check_version()
}

'EOF'
