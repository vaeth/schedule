# schedule

Framework to schedule jobs in a multiuser multitasking environment

(C) Martin Väth (martin at mvath.de).
This project is under the BSD license 2.0 (“3-clause BSD license”).
SPDX-License-Identifier: BSD-3-Clause

## What is this project and what it is good for?

Suppose you have some long-running tasks which you want to start
before you leave the machine for the night (or for going to lunch),
for instance the command `emerge -NDu @world`, a kernel compilation script
`kernel -f`, and a command to build special kernel modules
`emerge -1O @module-rebuild`.

Normally, what you would do is probably to start these tasks in a shell as
```
	emerge -NDu @world && kernel -f && emerge -1O @module-rebuild \
		&& shutdown -h now
```
Now suppose that you started the above line and realize after an hour
that you want to do something else before the `shutdown -h now`.
For instance, you want to do the same commands also in a chroot.
Now if you typed the above line, you are lost, in a sense:
You would have to stop the lengthy `emerge -NDu @world` command only to
change this command line.

Therefore, it is better to use a scheduler for jobs.
A rather primitive such "scheduler" is my __starter__ script from
-	https://github.com/vaeth/starter/

With this you could just write e.g.
- `starter emerge -NDu @world`
- `starter kernel -f`
- `starter emerge -1O @module-rebuild`
- `starter shutdown -h now`

in different shells, each, and the later commands would
not restart until the former ones have finished (or are stopped with Ctrl-C).
However, this approach was limited to removing "scheduled" jobs (with Ctrl-C)
or adding new jobs at the end.

The current project is an improvement which is much more flexible:
You can add jobs anywhere, sort jobs differently, start jobs in parallel,
schedule based on the exit status of other jobs, schedule jobs of
different chroots without any problems.
Actually, you can even schedule jobs of different machines!

Instead of running the above command line you would do the following when
you use this project.

0. unless you started `schedule-server` in an init file or use a
   `schedule-server` of a different machine, you run
   ```
	schedule-server --daemon
   ```
1. You run
   ```
	schedule sq emerge -NDu @world
   ```
   This is a shortcut for
   ```
	schedule start-or-queue emerge -NDu @world
   ```
   It immediately starts the `emerge -NDu @world` so that you will not
   loose time when doing the next steps.
   Simultaneously, it will "queue" the job `emerge -NDu @world`.
   What this means will become clear in step 5.

2. In a different shell you run
   ```
	schedule sq kernel -f
   ```
   If you enter it while the above command is still running,
   `kernel -f` is not started immediately, but it will be "queued"
   for scheduling in step 5.
   If you do not want to use a different shell for the next step,
   you use instead
   ```
	schedule --bg sq kernel -f
   ```
   which is similar to
   ```
	schedule sq kernel -f &
   ```
   but in contrast to the latter will not cause a race condition if
   several such commands are used subsequently in a script.
   Alternatively, if you are in a tmux session, you can use
   ```
	schedule-tmux sq kernel -f
   ```
   to schedule execution in a new tmux window.

3. In another shell run
   ```
	schedule sq emerge -1O @module-rebuild
   ```

4. In yet another shell run
   ```
	schedule wait && shutdown -h now
   ```
   This means that if all queue jobs have successfully finished,
   we shut down the machine. (The exit status of `schedule wait` is the
   maximum of the exit status of all queued jobs, that is, it "succeeds"
   only if all jobs suceeded.)

5. Finally, we run in yet another shell:
   ```
	schedule exec
   ```

The latter instructs schedule to run all queued jobs sequentially,
stopping if the first job returns with a nonzero exit status.
(If we would not want the stopping, we could have used instead:
```
	schedule run
```
This will run all jobs sequentially, even if they return a nonzero exit status;
The exit status of `schedule run` is calculated as for `schedule wait`)

Now if we suddenly decide that something else must be done, e.g.,
the same jobs should be queued in a chroot, we just press Ctrl-C in the
shell of 5, queue further commands and run `schedule exec` again.
Alternatively, we could have used
```
	schedule --job -1 sq something
```
to insert our new job `something` one entry before the end of the queue.
If we have inserted a job at the wrong place, we can sort the queue
differently. For instance,
```
	schedule --job=-1 insert :3
```
will shift the first three jobs in the queue one entry before the end of
the queue. Of course, we can also remove jobs from the list
(in which case the corresponding `schedule queue ...` command will return).
If you lost an overview of the queued jobs,
```
	schedule list
```
will show you the jobs with their numbers.
The commands `schedule exec` and `schedule run` are intentionally not
race-free, that is, if you modify the job queue while these commands are
running (e.g. if you insert new jobs), they will adapt to the new queue
dynamically. If you do not want that use static job numbers. For instance,
```
	schdeule exec /:
```
will execute all jobs of the current queue, even if you modify the queue
later on (with some exception; see `schedule man` for details).

Instead of sequential executing, one can also start more jobs in
parallel, wait for other jobs, build dependencies on the success of
certain jobs etc. In fact, you can write a simple "driver" script
(in any language which you like) to actually schedule the queued jobs.
To stay with the above example, suppose that you have queued the jobs

1. `emerge -NDu @world`
2. `kernel -f`
3. `emerge -1O @module-rebuild`
4. `shutdown -h now`
5. `emerge -NDu @world` (in a chroot)
6. `kernel -f` (in a chroot)
7. `emerge -1O @module-rebuild` (in a chroot)

Intuitively, there are the dependencies 1->2->3, 5->6->7, and 3,7->4.
To honour these dependencies you can write a tiny shell "script" (in
this case in a single line) instead of using `schedule exec`:
```
( schedule exec 1:3; schedule-exec 5:7; schedule wait 3 7 && schedule run 4 )
```
or, equivalently,
```
( schedule exec 1:3; schedule-exec 5:7; schedule exec 1:3 5:7 4)
```
Note that jobs are never executed twice. For instance, the above
`schedule exec 1:3` will not start the first job again (which in the
above example is already running and maybe possibly finished meanwhile);
more drastically, the last `schedule exec` will not restart any job again
which has already been run, but only start the remaining job 4 if the
former ones succeeded.

The above commands have the disadvantage that if you run these "driver"
scrips and stop them, if you have rearranged the queue meanwhile, you cannot
just restart these scripts, since the queue numbers might refer to different
jobs. To avoid this problem you can use "job addresses" instead which will
not change. For details on this technical issue, see the section
__SPECIFYING JOBS__ of the schedule manpage (`schedule man`); if the job
addresses are the same as the above numbers in the queue, you can use e.g.
```
( schedule exec @1_@3; schedule-exec @5_@7; schedule exec @1_@3 @5_@7 @4)
```
This script can then be restarted even with a modified queue but will refer
to the original jobs.

You can also run jobs in parallel. For instance,
```
	schedule parallel 1 5
```
would start jobs 1 and 5 in parallel and return when both are finished
(exit status is as for "schedule run", that is, it tells you whether
all jobs succeeded).

Of course, you can also return immediately:
```
	schedule bg 1 5
```
starts jobs 1 and 5 in parallel and returns. You can wait for their end with
```
	schedule wait 1 5
```
For further details on the various commands and options, use

-	```schedule man```
-	```schedule-tmux man```
-	```schedule-server man```
-	```cat -- "$(command -v schedule-tmux)"```


## Security considerations: Encryption and Global vs. Local Servers

In the above example, we assumed that you are root and that you are the
only user on the machine: In this case you can just run `schedule-server`
in an init-file. The server will use a TCP socket for communicating.
(Normally on a local socket, but you can even list worldwide by
using `-h 0.0.0.0`).

However, you should be aware that in this simple setting everybody who
can access the TCP socket can start/see/cancel/re-order all of your tasks!

This is intentional so that you can also queue tasks as different users.
It is not really a security risk, since users can only start e.g. a
task of root if root has queued this task before.
(This is not a built-in "feature" of schedule but due to the nature of the
unix permission system. In fact, `schedule-server` needs no permissions at all
to do its job [except for accessing the TCP socket], and therefore it is
highly recommended to start it with an unprivileged user/group;
the suggested and default name for that user/group is `schedule`:
If started as root, schedule-server will by default change to user/group
`schedule`, falling back to `nobody`).

Nevertheless, the above is not always desired.
For instance, in the second example above the attacker might be able
to shutdown the machine whenever he wants.
(Even in the first example, an attacker might cancel your jobs, setting their
exit status to 0, and thus might cause the shutdown to happen earlier,
although in that case the attacker is not able to see the shutdown command
since in the first example the shutdown command is not part of the queue.)

There are two ways to solve this problem which can also be combined.

### (1) Using only encrypted sockets.

This is done by using the option `--passfile FILE` for `schedule-server`
and whenever you invoke schedule (see the next section how to simplify this).
Then the communication of schedule with `schedule-server` is only possible
if the same password (the first line of `FILE`) is used for both programs.
(We point out for later configuration that if `FILE` is not readable or the
first line is empty then this option is ignored.)

### (2) Using a file socket instead of a TCP socket.

This is done by using the option `-l` or by specifying the file with `--file`
for `schedule-server` and whenever you invoke schedule (see the next section
how to simplify this).
In this case, only users who can access the file socket are able to
communicate with schedule-server. This is even more secure than (1)
and might even avoid some DOS attacks which might be still possible with (1).

The disadvantage of (2) is that you are then no longer able to schedule tasks
of all users or of different machines (unless you use other tools like
a network filesystem which supports file sockets), and also in a chroot
you have to make sure that you can access the socket file (for instance
by using mount --bind into the chroot).

Of course, nothing prevents you from starting a global server and a local
server simultaneously and to mix "global" commands with local (and possibly
security critical) tasks: You only have to be aware to use always the
correct options (e.g. `-l`, `-t`, or specify the correct hosts/ports/filenames)
for the corresponding schedule commands.


## Configuration: environment variables SCHEDULE_OPTS and SCHEDULE_SERVER_OPTS

To simplify setting an option like `--passfile FILE` or `-l` globally for
every call to schedule and schedule-server, schedule supports the environment
variable `SCHEDULE_OPTS`: For instance, you can set
```
	export SCHEDULE_OPTS="--passfile '/path/to/file'"
```
and all of your future calls of `schedule` and `schedule-server` will use the
coresponding option. Recall that it is safe to specify `--passfile` if
`/path/to/file` does not exist - in this case, the option is ignored.
Similarly, you can alternatively/additionally add the option `-l` to use
a (local) TCP socket instead of a TCP port by default (to override this,
you can specify the option `-t` later on).

Note that `SCHEDULE_OPTS` can contain shell quotes: These are resolved by the
`schedule` and `schedule-server` programs. In addition, `SCHEDULE_OPTS`
can also refer to environment variables which are then resolved.

In some rare cases, you might want to specify different default options
for `schedule` and `schedule-server`: In this case, you can use the
environment variables `SCHEDULE_OPTS` and `SCHEDULE_SERVER_OPTS`; the latter
overrides the former for `schedule-server`. To avoid this "override" and
instead "add" your options you can use the mechanisms mentioned earlier,
for instance
```
	export SCHEDULE_SERVER_OPTS='$SCHEDULE_OPTS -f "/foo/socket name"'
```

## Requirements

You need a multitasking system with TCP Sockets and/or Unix Domain sockets
(for usage with `-t` or `-l`, respectively). Any Linux flavour will do
(as will many other operating systems) and any __>=perl-5.12__
Any full installation of __>=perl-5.12__ contains most of the required
libraries in its core; the list of required perl libraries is found in
the beginning of the `bin/*` files.

If you want to use the options `--bg` or `--daemon` you need a system which can
do `fork()`. If you want to use the options `--detach`, you additionally need
a functioning POSIX library in perl.

Additionally, if you want to use encryption, the perl module
```
	Crypt::Rijndael
```
is needed. This module might have to be installed separately from CPAN.
This module is not needed if the `--password` and `--passfile` option
is not used (or if no password file exists).


## Installation

If you are a gentoo user, you can just emerge __schedule__ from the mv overlay
and possibly have to adapt `/etc/conf.d/schedule` and the systemd service file.
By default, these contain the options `--passfile /etc/schedule.password`.
It is recommended to generate this file with a random password and to
make it readable only by user/group `schedule`: Then you can add all your
users who should be able to access the default server to the group `schedule`.

If your distribution has no package for schedule, you have to copy
`bin/*` into `/usr/bin/` or any other directory of your `$PATH`.

Moreover, you have to copy `share/schedule` (or its content) into the
same directory as the binaries or into the parent directory or into
a directory shown by
```
	perl -e 'print join("\n", @INC, "")'
```
Alternatively, copy `share/schedule` into `/usr/share/schedule`
(or into a different directory by modifying that path in the sourcecode;
for a proper installation it is recommended in this case to remove/comment
out the lines between `use FindBin;` and `}` in the sourcecode).

For __zsh completion__ support also copy 'zsh/_schedule` into a directory of
your zsh's `$fpath`.

For __openrc__ support copy the content of openrc to `/etc` and activate
the `schedule` file in the usual way.
For __systemd__ support copy `systemd/system/schedule.{service,socket}` to your
systemd system folder and activate the service or socket file in the usual way.
If you copied the main script not to `/usr/bin/schedule`, you have to modify
the `schedule.service` file for __systemd__ correspondingly.

If you use the default openrc/systemd files you should also generate
`/etc/schedule.password` (and set corresponding permissions) if you want to
use encryption: It is recommended to generate a new user/group `schedule`
and make `/etc/schedule.password` be readable only by this user/group,
adding all users to this group which should be able to use the system wide
scheduler.

It is recommended to export the variables from the files in the `env.d`
directory (or put them into your shell startup code),
e.g. to use `/etc/schedule.password`.


## A note on versioning of this project

This project consists of many files, but not every file changes in every
release. Therefore, every file can have a different version number
(which can be found after the `package` keyword near the beginning).

By definition, the version number of the project is that of the "main" file
`share/schedule/Schedule/Connect.pm` (module `Schedule::Connect`).
This file contains also information which other minimal/maximal/exact
versions of files belong to that project version - this is specified
near the beginning of `share/schedule/Schedule/Connect.pm`.
Moreover, the beginning of that file also contains information which range
of running servers is accepted with the current schedule version:
In general, the version of the server and the client must match, but the
client accepts all servers which fully support the protocoll he speaks,
i.e. you can use the same server for various client version when the
internal protocoll did not change.
The server in turn does not check the client's version but just expects
to be talked to with the correct protocoll: A buggy/malevolent client might be
lying about his version number anyway (if he can establish a possibly encrypted
connection), and a well working client checks the server's version for
compatibility.

Auxiliary files in `zsh`, `openrc`, `zsh`, `env.d`, and `bin/schedule-tmux`
carry no explicit version number; their version number is implicit
that of the project (`share/schedule/Schedule/Connect.pm`).
