
-------- backup.sh and backup.bat --------

These scripts help backup files under Linux and Windows respectively.

They use tools '7z' and 'par2' in order to create compressed and encrypted backup files
with extra redundant data for recovery purposes.

In order to use one of them, copy it to an empty directory and edit the directory paths
to backup and the subdirectories and file extensions to exclude.


-------- update-backup-mirror-by-modification-time.sh version 1.06 --------

For backup purposes, sometimes you just want to copy all files across
to another disk at regular intervals. There is often no need for
encryption or compression. However, you normally don't want to copy
all files every time around, but only those which have changed.

Assuming that you can trust your filesystem's timestamps, this script can
get you started in little time. You can easily switch between
rdiff-backup and rsync (see this script's source code), until you are
sure which method you want.

Syntax:
  ./update-backup-mirror-by-modification-time.sh src dest  # The src directory must exist.

You probably want to run this script with "background.sh", so that you get a
visual indication when the transfer is complete.

If you use the default 'rsync' method instead of the alternative 'rdiff-backup' method,
you can set environment variable PATH_TO_RSYNC to specify an alternative rsync tool to use.
This is important on Microsoft Windows, as Cygwin's rsync is known to have problems.
See script copy-with-rsync.sh for more information.


Copyright (c) 2015-2017 R. Diez - Licensed under the GNU AGPLv3
