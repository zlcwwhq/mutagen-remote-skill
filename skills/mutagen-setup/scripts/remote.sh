#!/bin/sh
# remote for SSH and Docker endpoints of the zlcwwhq/mutagen fork.
#
# The Mutagen agent installs remote at ~/.mutagen/agents/<version>/remote, so a
# PATH entry for one version breaks when the daemon is upgraded. This script
# reads the registrations of sessions connected on this system and runs the
# remote of the version that registered the session whose root most
# specifically contains the current directory, else of the most recent
# registration, else of the most recently installed agent. Install it as an
# executable named remote in a directory on PATH, such as ~/.local/bin.

data=$HOME/.mutagen
records=$(ls -t "$data"/remote/*.json 2>/dev/null)
agents=$(ls -td "$data"/agents/*/ 2>/dev/null)
directory=$(pwd -P 2>/dev/null)

# Split the lists into lines only, without expanding them as patterns.
IFS='
'
set -f

newest=
matched=
length=0
for record in $records; do
	version=$(sed -n 's/.*"Version":"\([^"]*\)".*/\1/p' "$record")
	if [ -z "$version" ] || ! [ -x "$data/agents/$version/remote" ]; then
		continue
	fi
	newest=${newest:-$version}
	root=$(sed -n 's/.*"Root":"\([^"]*\)".*/\1/p' "$record")
	case $directory/ in
	"$root"/*)
		if [ "${#root}" -gt "$length" ]; then
			matched=$version
			length=${#root}
		fi
		;;
	esac
done
version=${matched:-$newest}
if [ -n "$version" ]; then
	exec "$data/agents/$version/remote" "$@"
fi

for agent in $agents; do
	if [ -x "${agent}remote" ]; then
		exec "${agent}remote" "$@"
	fi
done

echo "remote: no Mutagen agent in $data/agents provides remote; agents provide it once a session that runs commands submitted from this system connects" >&2
exit 255
