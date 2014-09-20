# Schedule::Server::Serverman.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

require 5.012;
package Schedule::Server::Serverman v6.0.2;

use strict;
use warnings;
use integer;

=head1 NAME

schedule-server - server for the schedule client

=head1 SYNOPSIS

=over 8

=item B<schedule-server> [options]

Start server for the B<schedule> command.

Use B<schedule-server man> or B<schedule man> to get a verbose manpage
for the server or client, respectively.

=back

=head1 DESCRIPTION

This is a daemon which needs to run if the B<schedule> command shall be used.
(Versions of the daemon and of the B<schedule> command need to match.)
It can be started as a user or as root - it only needs permissions to setup a
TCP port or a unix domain socket, depending on the communication type
you choose. Only in special occassions it emits diagnostic messages on STDERR.

Note that although this daemon has the ability to background itself,
it is not recommended to use this possibility for the system's main server.
For instance, this daemon does not generate a PID file by itself.
Use a controlling program start-stop-daemon or a daemon-managing framework
like systemd, if available.

It should be completely safe to run this daemon as root, but to limit the
effect of unforeseen bugs, for security reasons, if the effective user id is 0,
this daemon tries to change its permissions to user and group "nobody".
If the user/group cannot be found, the id 65534 is used instead.

By default, the daemon uses a TCP socket on a local port for communication.
Note that this means that every user on the local machine can communicate
with the server and list/start/remove/change the order of queued commands
of all users using the same daemon. This is intentional, and you should be
aware of the security risks and make use of the encryption features
if you use this daemon globally.

If you do not want this, you can run this daemon locally, communicating by a
file (unix domain socket). In this case, you will usually run the daemon
locally as a user and specify the option B<--local> (and/or B<--file>).

If you make use of the encryption feature or of the B<--local> option,
it is recommended, to setup an alias or a shell script to call
B<schedule> always with the same B<--local> or B<--file> option, too.
You can use the variables B<SCHEDULE_OPTS> and/or B<SCHEDULE_SERVER_OPTS>
for this purpose.

=head1 OPTIONS

The default of the options is taken from the environment variable
B<SCHEDULE_SERVER_OPTS>; shell-quoting in the value is supported.
Moreover, (unquoted) environment variable references of the form $VAR
or ${VAR} in it are (recursively) expanded.
If B<SCHEDULE_SERVER_OPTS> is undefined, the default is taken from the
environment variable B<SCHEDULE_OPTS>, according to the same rules.

=over 8

=item B<--tcp> or B<-t>

Use a tcp socket (port) for IPC with the client(s). This is the default.
This option exists so that you can override an earlier specified
(e.g. set in B<SCHEDULE> or B<SCHEDULE_SERVER>) option B<-l>.

=item B<--local> or B<-l>

Use a unix domain socket (file) for IPC with the client(s).

=item B<--file=>I<file> or B<-f> I<file>

Use I<file> as a unix domain socket filename for IPC.
The default is B<${TMPDIR}/schedule-${USER}/server>.
All parent directories are created if they do not exist.
This option implies B<--local> (unless overridden later on).

=item B<--umask>I<umask> or B<-m> I<umask>

Use this umask for creating directories and/or unix domain socket file.
The argument is a number; prepend "0" to specify that it is octal.
Default is 0077. It may be a security risk to change this!

=item B<--skip-check> or B<-S>

Do not change ownership of the parent directory of I<file>.
Normally, this is checked since it can be a security risk if this is
not owned by a trusted user.
Do not use this option unless you know what you are doing!

=item B<--port=>I<port> or B<-P> I<port>

Use port number I<port>; default is B<8471>.
This option implies B<--tcp> (unless overridden later on).

=item B<--addr=>I<addr> or B<-A> I<addr>

Bind to I<addr>. The default is 127.0.0.1 (localhost only).
If you want to listen worldwide, use B<--addr 0.0.0.0> but be aware about
the security implications: Everybody will be able to start/see/re-order/cancel
your tasks unless you use encryption with B<--passfile>.
This option implies B<--tcp> (unless overridden later on).

=item B<--timeout=>I<seconds> or B<-T> I<seconds>

Time to wait in case of communication problems; the default is 10 B<seconds>.
The value B<0> means to skip the timeout.

=item B<--passfile=>I<passfile> or B<-Y> I<passfile>

Read the first line from I<password-file> (without the newline)
and use it as a password to encrypt communication between B<schedule>
and B<schedule-server>. Both programs must use the same password for a
succesfull communication.

The I<password-file> is read before permissions are dropped so that
you can (and should) restrict read-permissions on this file.

This option can be used accumulatively:
The first existing I<password-file> with a nonempty first line is used.
If no such file is found, this option is tacitly ignored.
This is to make it safe to specify this option in B<SCHEDULE_SERVER_OPTS>
or B<SCHEDULE_OPTS> if no corresponding file exists.

=item B<--password=>I<password> or B<-y> I<password>

This is like B<--passfile>, with the difference that you specify the
password directly. This option is dangerous, because many systems allow
other users to see the commandline/environment (hence the password is visible).

=item B<--alpha=>I<cmd/arg> or B<-a> I<cmd/arg>

This can be used accumulatively.
Immediately after the socket has been established, execute
perl's system(I<cmd>, I<arg>, ..., I<arg>) before acting on commands.
The purpose is that you can use this to signal e.g. that the daemon is
ready to avoid possible race conditions.

If the I<cmd> does not exit with a zero exit status, the server is stopped
immediately. Use the following option, if you do not want this.

=item B<--alpha-ignore> or B<-J>

Ignore any failure in the execution of commands from B<--alpha>.
(A warning is printed anyway unless the option B<--quiet> is used.)

=item B<--background> or B<--bg> or B<-b>

Fork into background mode.
To use this option, your system must know fork(), of course.

This option is not recommended for system servers:
Use facilities of your init-system instead.

=item B<--daemon> or B<-B>

This is like B<--background>, but it also partially detaches from terminal,
discarding all subsequent standard input/output.

This option is not recommended for system servers:
Use facilities of your init-system instead.

=item B<--detach> or B<-E>

This is like B<--daemon>, but fully detaches from terminal, discarding also
error output.
To avoid unexpected issues with relatice paths, the current working directory
is kept (and thus remains occupied). Therefore you might want to change to the
root directory before using this option.

This option is not recommended for system servers:
Use facilities of your init-system instead.

=item B<--keep-permissions> or B<-k>

Do not try to drop permissions, even if started as root.
It is equivalent to specify B<--no-change-user> and B<--no-change-group>.

=item B<--change-permission> or B<-K>

Try to drop permissions, even if not started as root.
It is equivalent to specify B<--change-user> and B<--change-group>.

=item B<--no-change-user> or B<-n>

Try to keep permissions of user, independently of how the group is treated.

=item B<--no-change-group> or B<-N>

Try to keep permissions of group (and associated groups),
ndependently of how the the user is treated.

=item B<--change-user> or B<-c>

Try to drop permissions of user, independently of how the group is treated.

=item B<--change-group> or B<-C>

Try to drop permissions of group (and associated groups),
independently of how the the user is treated.

=item B<--user=>I<user> or B<-u> I<user>

Drop permissions to user I<user> instead of B<nobody>.

=item B<--group=>I<group> or B<-g> I<group>

Drop permissions to group I<group> instead of B<nobody>.

=item B<--uid=>I<uid> or B<-U> I<uid>

Drop permissions to user with id I<uid> instead of 65534.
(If this is specified and valid the value of B<--user> is ignored.)

=item B<--gid=>I<gid> or B<-G> I<gid>

Drop permissions to user with id I<gid> instead of 65534.
(If this is specified and valid the value of B<--group> is ignored.)

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

=head1 COPYRIGHT AND LICENSE

Copyright Martin VE<auml>th. This project is under the BSD license.

=head1 AUTHOR

Martin VE<auml>th E<lt>martin@mvath.deE<gt>

=cut

sub man_server_init {
	my ($s) = @_;
	$s->check_version()
}

1;
