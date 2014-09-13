# Schedule::Client::Tmuxman.pm
#
# Copyright Martin Väth <martin@mvath.de>.
# This is part of the schedule project.

require 5.012;
package Schedule::Client::Tmuxman v6.0.1;

use strict;
use warnings;
use integer;

=head1 NAME

schedule-tmux - call schedule in a new tmux window

=head1 SYNOPSIS

=over 8

=item B<schedule-tmux> [options] B<queue>|B<start>|B<start-or-queue> I<cmd> [I<arg> ...]

=back

Use B<schedule-tmux man> for details.

=head1 DESCRIPTION

This command is like opening a new tmux window and calling B<schedule>
with the corresponding options in that window.
In contrast to using B<tmux new-window -d schedule ...> directly,
a sequence of these commands is guaranteed to keep the order of schedule.

=head1 OPTIONS

All options known to B<schedule> are supported (except B<--alpha>);
for a complete list, type: B<schedule man>

The variable B<SCHDEULE_REMAIN> decides whether the window remains after exit
(it does not if the variable is undefined, empty, B<0>, B<false>,
B<no>, B<off>, etc.)

Alternatively, you can use one of the following options to change this default
independent of the value of B<SCHEDULE_REMAIN>.
If one of these options is used, it must necessarily be the first one
and appear as a separate word.

=over 8

=item B<--remain> or B<-r>

Set remain-after-exit in the new tmux window.

=item B<--no-remain> or B<noremain> or B<-R>

Do not set remain-after-exit in the new tmux window.

=back

=head1 COPYRIGHT AND LICENSE

Copyright Martin VE<auml>th. This project is under the BSD license.

=head1 AUTHOR

Martin VE<auml>th E<lt>martin@mvath.deE<gt>

=cut

sub man_tmux_init {
	my ($s) = @_;
	$s->check_version()
}

'EOF'
