#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# set -x  # Enable tracing of this script.

VERSION_NUMBER="2.0"
SCRIPT_NAME="DownloadAndBuildAutotools.sh"

GNU_FTP_SITE="ftpmirror.gnu.org"

# Otherwise, assume the files have already been downloaded. Useful only when developing this script.
DOWNLOAD_FILES=true

# Otherwise, carry on building where it failed last time. Useful only when developing this script.
START_CLEAN=true


abort ()
{
  echo >&2 && echo "Error in script \"$0\": $*" >&2
  exit 1
}


display_help ()
{
cat - <<EOF

$SCRIPT_NAME version $VERSION_NUMBER
Copyright (c) 2011-2014 R. Diez - Licensed under the GNU AGPLv3

This script downloads, builds and installs any desired versions of the GNU autotools
(autoconf + automake), which are often needed to build many open-source projects
from their source code repositories.

You would normally use whatever autotools versions your Operating System provides,
but sometimes you need older or newer versions, or even different combinations
for testing purposes.

You should NEVER run this script as root nor attempt to upgrade your system's autotools versions.
In order to use the new autotools just built by this script, temporary prepend
the full path to the "bin" subdirectory underneath the installation directory
to your \$PATH variable, see option --prefix below.

Syntax:
  $SCRIPT_NAME --autoconf-version=<nn> --automake-version=<nn>  <other options...>

Options:
 --autoconf-version=<nn>  autoconf version to download and build
 --automake-version=<nn>  automake version to download and build
 --prefix=/some/dir       directory where the binaries will be installed, see notes below
 --help     displays this help text
 --version  displays the tool's version number (currently $VERSION_NUMBER)
 --license  prints license information

Usage example:
  % cd some/dir  # The file cache and intermediate build results will land there.
  % ./$SCRIPT_NAME --autoconf-version=2.69 --automake-version=1.14.1

About the installation directory:

If you specify with option '--prefix' the destination directory where the binaries will be installed,
and that directory already exists, its contents will be preserved. This way, you can install other tools
in the same destination directory, and they will all share the typical "bin" and "share" directory structure
underneath it that most autotools install scripts generate.

Make sure that you remove any old autotools from the destination directory before installing new versions.
Otherwise, you will end up with a mixture of old and new files, and something is going to break sooner or later.

If you do not specify the destination directory, a new one will be automatically created in the current directory.
Beware that this script will DELETE and recreate it every time it runs, in order to minimise chances
for mismatched file version. Therefore, it is best not to share it with other tools, in case you inadvertently
re-run this script and end up deleting all other tools as an unexpected side effect.

About the download cache and the intermediate build files:

This script uses 'curl' in order to download the files from $GNU_FTP_SITE ,
which should give you a fast mirror nearby.

The tarball for a given autotool version is downloaded only once to a local file cache,
so that it does not have to be downloaded again the next time around.
Do not run several instances of this script in parallel, because downloads
to the cache are not serialised or protected in any way against race conditions.

The file cache and the intermediate build files are placed in automatically-created
subdirectories of the current directory. The intermediate build files can be deleted
afterwards in order to reclaim disk space.

Interesting autotools versions:
- Ubuntu 12.04 (as of february 2014): autoconf 2.68, automake 1.11.3
- Ubuntu 13.10: autoconf 2.69, automake 1.13.3
- Latest as of february 2014: autoconf 2.69, automake 1.14.1

Exit status: 0 means success. Any other value means error.

Feedback: Please send feedback to rdiezmail-tools at yahoo.de

EOF
}


display_license()
{
cat - <<EOF

Copyright (c) 2011-2014 R. Diez

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License version 3 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License version 3 for more details.

You should have received a copy of the GNU Affero General Public License version 3
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

EOF
}


delete_dir_if_exists ()
{
  # $1 = dir name

  if [ -d "$1" ]
  then
    # echo "Deleting directory \"$1\" ..."

    rm -rf -- "$1"

    # Sometimes under Windows/Cygwin, directories are not immediately deleted,
    # which may cause problems later on.
    if [ -d "$1" ]; then abort "Cannot delete directory \"$1\"."; fi
  fi
}


create_dir_if_not_exists ()
{
  # $1 = dir name

  if ! test -d "$1"
  then
    echo "Creating directory \"$1\" ..."
    mkdir --parents -- "$1"
  fi
}


download_tarball ()
{
  URL="$1"
  TEMP_FILENAME="$2"
  FINAL_FILENAME="$3"
  TAR_OPTION_TO_EXTRACT="$4"

  NAME_ONLY="${URL##*/}"

  if [ -f "$FINAL_FILENAME" ]; then
    echo "Skipping download of file \"$NAME_ONLY\", as it already exists in the cache directory."
    return 0
  fi

  echo "Downloading URL \"$URL\"..."

  curl --location --show-error --url "$URL" --output "$TEMP_FILENAME"

  # Test the archive before committing it to the cache with its final filename.
  # Some GNU mirrors use HTML redirects that curl cannot follow,
  # and once a corrupt archive lands in the destination directory,
  # it will stay corrupt until the user manually deletes it.

  echo "Testing the downloaded tarball \"$TEMP_FILENAME\"..."

  TMP_DIRNAME="$(mktemp --directory --tmpdir "$SCRIPT_NAME.XXXXXXXXXX")"

  pushd "$TMP_DIRNAME" >/dev/null

  set +o errexit
  tar --extract "$TAR_OPTION_TO_EXTRACT" --file "$TEMP_FILENAME"
  TAR_EXIT_CODE="$?"
  set -o errexit

  popd >/dev/null

  rm -rf -- "$TMP_DIRNAME"

  if [ $TAR_EXIT_CODE -ne 0 ]; then
    ERR_MSG="Downloaded archive file \"$URL\" failed the integrity test, see above for the detailed error message. "
    ERR_MSG="${ERR_MSG}The file may be corrupt, or curl may not have been able to follow a redirect properly. "
    ERR_MSG="${ERR_MSG}Try downloading the archive file from another location or mirror. "
    ERR_MSG="${ERR_MSG}You can inspect the corrupt file at \"$TEMP_FILENAME\"."
    abort "$ERR_MSG"
  fi

  mv "$TEMP_FILENAME" "$FINAL_FILENAME"
}


# --------------------------------------------------


# The way command-arguments are parsed below is described on this page:  http://mywiki.wooledge.org/ComplexOptionParsing

# Use an associative array to declare how many arguments a long option expects.
# Long options that aren't listed in this way will have zero arguments by default.
declare -A MY_LONG_OPT_SPEC=( [autoconf-version]=1 [automake-version]=1 [prefix]=1 )

# The first colon (':') means "use silent error reporting".
# The "-:" means an option can start with '-', which helps parse long options which start with "--".
MY_OPT_SPEC=":-:"

AUTOCONF_VERSION=""
AUTOMAKE_VERSION=""
PREFIX_DIR=""
DELETE_PREFIX_DIR=true

while getopts "$MY_OPT_SPEC" opt; do
  while true; do
    case "${opt}" in
        -)  # OPTARG is name-of-long-option or name-of-long-option=value
            if [[ "${OPTARG}" =~ .*=.* ]]  # With this --key=value format, only one argument is possible. See also below.
            then
                opt=${OPTARG/=*/}
                OPTARG=${OPTARG#*=}
                ((OPTIND--))
            else  # With this --key value1 value2 format, multiple arguments are possible.
                opt="$OPTARG"
                OPTARG=(${@:OPTIND:$((MY_LONG_OPT_SPEC[$opt]))})
            fi
            ((OPTIND+=MY_LONG_OPT_SPEC[$opt]))
            continue  # Now that opt/OPTARG are set, we can process them as if getopts would have given us long options.
            ;;
        autoconf-version)
          AUTOCONF_VERSION="$OPTARG"
            ;;
        automake-version)
          AUTOMAKE_VERSION="$OPTARG"
            ;;
        prefix)
          PREFIX_DIR="$OPTARG"
          DELETE_PREFIX_DIR=false
            ;;
        help)
            display_help
            exit 0
            ;;
        version)
            echo "$VERSION_NUMBER"
            exit 0
            ;;
        license)
            display_license
            exit 0
            ;;
        *)
            if [[ ${opt} = "?" ]]; then
              abort "Unknown command-line option \"$OPTARG\"."
            else
              abort "Unknown command-line option \"${opt}\"."
            fi
            ;;
    esac
  break; done
done


if [ $OPTIND -le $# ]; then
  abort "Too many command-line arguments. Run this tool with the --help option for usage information."
fi

if [[ $AUTOCONF_VERSION = "" ]]; then
  abort "You need to specify an autoconf version. Run this tool with the --help option for usage information."
fi

if [[ $AUTOMAKE_VERSION = "" ]]; then
  abort "You need to specify an automake version. Run this tool with the --help option for usage information."
fi

CURRENT_DIR_ABS="$(readlink -f "$PWD")"

DIRNAME_WITH_VERSIONS="autoconf-$AUTOCONF_VERSION-automake-$AUTOMAKE_VERSION"

if [[ $PREFIX_DIR = "" ]]; then
  PREFIX_DIR="$CURRENT_DIR_ABS/$DIRNAME_WITH_VERSIONS-bin"
fi


DOWNLOAD_CACHE_DIR="$CURRENT_DIR_ABS/AutotoolsDownloadCache"
TMP_DIR="$CURRENT_DIR_ABS/AutotoolsIntermediateBuildFiles/$DIRNAME_WITH_VERSIONS"

TARBALL_EXTENSION="tar.xz"
TAR_OPTION_TO_EXTRACT="--auto-compress"

DOWNLOAD_IN_PROGRESS_STR="download-in-progress"

AUTOCONF_TARBALL_TEMP_FILENAME="$DOWNLOAD_CACHE_DIR/autoconf-$AUTOCONF_VERSION-$DOWNLOAD_IN_PROGRESS_STR.$TARBALL_EXTENSION"
AUTOMAKE_TARBALL_TEMP_FILENAME="$DOWNLOAD_CACHE_DIR/automake-$AUTOMAKE_VERSION-$DOWNLOAD_IN_PROGRESS_STR.$TARBALL_EXTENSION"

AUTOCONF_TARBALL_FINAL_FILENAME_ONLY="autoconf-$AUTOCONF_VERSION.$TARBALL_EXTENSION"
AUTOMAKE_TARBALL_FINAL_FILENAME_ONLY="automake-$AUTOMAKE_VERSION.$TARBALL_EXTENSION"

AUTOCONF_TARBALL_FINAL_FILENAME="$DOWNLOAD_CACHE_DIR/$AUTOCONF_TARBALL_FINAL_FILENAME_ONLY"
AUTOMAKE_TARBALL_FINAL_FILENAME="$DOWNLOAD_CACHE_DIR/$AUTOMAKE_TARBALL_FINAL_FILENAME_ONLY"

echo "The download cache directory is located at \"$DOWNLOAD_CACHE_DIR\""

if $DOWNLOAD_FILES
then
  # echo "Downloading the autotools..."

  create_dir_if_not_exists "$DOWNLOAD_CACHE_DIR"

  download_tarball "http://$GNU_FTP_SITE/autoconf/$AUTOCONF_TARBALL_FINAL_FILENAME_ONLY" "$AUTOCONF_TARBALL_TEMP_FILENAME" "$AUTOCONF_TARBALL_FINAL_FILENAME" "$TAR_OPTION_TO_EXTRACT"
  download_tarball "http://$GNU_FTP_SITE/automake/$AUTOMAKE_TARBALL_FINAL_FILENAME_ONLY" "$AUTOMAKE_TARBALL_TEMP_FILENAME" "$AUTOMAKE_TARBALL_FINAL_FILENAME" "$TAR_OPTION_TO_EXTRACT"
fi

# This is probably not the best heuristic for make -j , but it's better than nothing.
MAKE_J_VAL="$(( $(getconf _NPROCESSORS_ONLN) + 1 ))"

AUTOCONF_SRC_SUBDIRNAME="autoconf-$AUTOCONF_VERSION"
AUTOMAKE_SRC_SUBDIRNAME="automake-$AUTOMAKE_VERSION"

AUTOCONF_OBJ_DIR="$TMP_DIR/autoconf-obj"
AUTOMAKE_OBJ_DIR="$TMP_DIR/automake-obj"


if $START_CLEAN
then
  echo "Cleaning any previous build results..."
  if $DELETE_PREFIX_DIR; then
    delete_dir_if_exists "$PREFIX_DIR"
  fi
  delete_dir_if_exists "$TMP_DIR"
fi


create_dir_if_not_exists "$TMP_DIR"

pushd "$TMP_DIR" >/dev/null

echo "Uncompressing \"$AUTOCONF_TARBALL_FINAL_FILENAME\"..."
tar  --extract "$TAR_OPTION_TO_EXTRACT" --file "$AUTOCONF_TARBALL_FINAL_FILENAME"
if ! [ -d "$AUTOCONF_SRC_SUBDIRNAME" ]; then
  abort "Tarball \"$AUTOCONF_TARBALL_FINAL_FILENAME\" did not extract to the expected \"$AUTOCONF_SRC_SUBDIRNAME\" subdirectory when extracting to \"$TMP_DIR\"."
fi

echo "Uncompressing \"$AUTOMAKE_TARBALL_FINAL_FILENAME\"..."
tar  --extract "$TAR_OPTION_TO_EXTRACT" --file "$AUTOMAKE_TARBALL_FINAL_FILENAME"
if ! [ -d "$AUTOMAKE_SRC_SUBDIRNAME" ]; then
  abort "Tarball \"$AUTOMAKE_TARBALL_FINAL_FILENAME\" did not extract to the expected \"$AUTOMAKE_SRC_SUBDIRNAME\" subdirectory when extracting to \"$TMP_DIR\"."
fi

popd >/dev/null


echo "----------------------------------------------------------"
echo "Building autoconf"
echo "----------------------------------------------------------"

create_dir_if_not_exists "$AUTOCONF_OBJ_DIR"

pushd "$AUTOCONF_OBJ_DIR" >/dev/null

# If configuration fails, it's often useful to have the help text in the log file.
echo "Here is the configure script help text, should you need it:"
"$TMP_DIR/$AUTOCONF_SRC_SUBDIRNAME/configure" --help

echo
echo "Configuring autoconf..."
"$TMP_DIR/$AUTOCONF_SRC_SUBDIRNAME/configure" \
    --config-cache\
    --prefix="$PREFIX_DIR"

echo
echo "Building autoconf..."
make -j $MAKE_J_VAL

echo
echo "Installing autoconf to \"$PREFIX_DIR\"..."
make install

popd >/dev/null


# Automake needs the new autoconf version.
export PATH="${PREFIX_DIR}/bin:$PATH"


echo "----------------------------------------------------------"
echo "Building automake"
echo "----------------------------------------------------------"

create_dir_if_not_exists "$AUTOMAKE_OBJ_DIR"

pushd "$AUTOMAKE_OBJ_DIR" >/dev/null

# If configuration fails, it's often useful to have the help text in the log file.
echo "Here is the configure script help text, should you need it:"
"$TMP_DIR/$AUTOMAKE_SRC_SUBDIRNAME/configure" --help

echo
echo "Configuring automake..."
"$TMP_DIR/$AUTOMAKE_SRC_SUBDIRNAME/configure" \
    --config-cache\
    --prefix="$PREFIX_DIR"

echo
echo "Building automake..."
make -j $MAKE_J_VAL

echo
echo "Installing automake to \"$PREFIX_DIR\"..."
make install

popd >/dev/null

echo
echo "Finished building the autotools. You will probably want to prepend the bin directory to your PATH like this:"
echo "  export PATH=\"${PREFIX_DIR}/bin:\$PATH\""
echo