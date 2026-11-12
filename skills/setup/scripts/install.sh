#!/bin/sh
# Install or upgrade the zlcwwhq/mutagen fork on Linux, macOS, or FreeBSD.
#
# Usage: install.sh [--check] [--restart-daemon] [--prefix DIR] [--version TAG]
#
#   --check           report the installed version and the release that would
#                     be installed, without changing anything
#   --restart-daemon  stop the daemon before replacing files and start it
#                     again afterwards, as a running daemon must be restarted
#   --prefix DIR      install into DIR/bin and DIR/libexec (default: where the
#                     fork's mutagen on PATH is installed, else ~/.local)
#   --version TAG     release tag, such as v0.19.0-zlcwwhq.0.0.7 (default: the
#                     latest release)
#
# mutagen and remote go into the bin directory, and the agent bundle, which
# mutagen needs to install agents on endpoints, into the libexec directory, or
# next to mutagen if an existing installation keeps it there.

set -eu

repository=zlcwwhq/mutagen
check=no
restart=no
prefix=
tag=

die() {
	echo "install.sh: $*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case $1 in
	--check) check=yes; shift ;;
	--restart-daemon) restart=yes; shift ;;
	--prefix | --version)
		[ $# -ge 2 ] || die "$1 requires a value"
		if [ "$1" = --prefix ]; then prefix=$2; else tag=$2; fi
		shift 2
		;;
	-h | --help)
		sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		die "unknown argument: $1"
		;;
	esac
done

for command in curl tar awk; do
	command -v "$command" >/dev/null 2>&1 || die "$command is required"
done

case $(uname -s) in
Linux) os=linux ;;
Darwin) os=darwin ;;
FreeBSD) os=freebsd ;;
*) die "unsupported system: $(uname -s)" ;;
esac
case $(uname -m) in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
arm*) arch=arm ;;
i386 | i686) arch=386 ;;
ppc64le | riscv64 | s390x) arch=$(uname -m) ;;
*) die "unsupported architecture: $(uname -m)" ;;
esac

# Locate the mutagen on PATH. A fork installation is upgraded in place, in its
# layout; anything else, such as upstream Mutagen, is left alone.
current=$(command -v mutagen 2>/dev/null) || current=
current_version=
if [ -n "$current" ]; then
	current_version=$("$current" version 2>/dev/null) || current_version=
fi
if [ -n "$prefix" ]; then
	bindir=$prefix/bin
	bundledir=$prefix/libexec
else
	case $current_version in
	*-zlcwwhq.*)
		resolved=$current
		if [ -L "$current" ]; then
			resolved=$(readlink "$current")
			case $resolved in
			/*) ;;
			*) resolved=$(dirname "$current")/$resolved ;;
			esac
		fi
		bindir=$(dirname "$resolved")
		if [ "$(basename "$bindir")" = bin ] && ! [ -e "$bindir/mutagen-agents.tar.gz" ]; then
			bundledir=$(dirname "$bindir")/libexec
		else
			bundledir=$bindir
		fi
		;;
	*)
		bindir=$HOME/.local/bin
		bundledir=$HOME/.local/libexec
		;;
	esac
fi

# The latest release's URL redirects to its tag, which avoids the rate-limited
# GitHub API.
if [ -z "$tag" ]; then
	latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repository/releases/latest") ||
		die "unable to determine the latest release"
	tag=${latest##*/}
fi
case $tag in
v*-zlcwwhq.*) ;;
*) die "not a release tag of $repository: $tag" ;;
esac
version=${tag#v}

# Agent bundles record their version in their first entry, version, from
# v0.19.0-zlcwwhq.0.0.9 on, and mutagen refuses those of other versions.
case $version in
*-zlcwwhq.0.0.[1-8]) records=no ;;
*) records=yes ;;
esac

# Print the version that an agent bundle records, if any.
recorded() {
	tar -xzOf "$1" version 2>/dev/null || :
}

installed=
if [ -x "$bindir/mutagen" ]; then
	installed=$("$bindir/mutagen" version 2>/dev/null) || installed=unknown
fi
if [ -z "$installed" ]; then
	status="not installed"
elif [ "$installed" != "$version" ]; then
	status="update available ($installed -> $version)"
elif ! [ -f "$bundledir/mutagen-agents.tar.gz" ] ||
	[ "$("$bindir/remote" --version 2>/dev/null)" != "$version" ] ||
	{ [ "$records" = yes ] && [ "$(recorded "$bundledir/mutagen-agents.tar.gz")" != "$version" ]; }; then
	status="incomplete (remote or the agent bundle is missing or of another version)"
else
	status="up to date"
fi

if [ "$check" = yes ]; then
	echo "mutagen on PATH: ${current:-none}${current_version:+ ($current_version)}"
	echo "installation: $bindir (agent bundle in $bundledir)"
	echo "installed there: ${installed:-none}"
	echo "release: $tag"
	echo "status: $status"
	exit 0
fi
if [ "$status" = "up to date" ]; then
	echo "Mutagen $version is already installed in $bindir"
	exit 0
fi

asset=mutagen_${os}_${arch}_$tag.tar.gz
download=https://github.com/$repository/releases/download/$tag

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 1' HUP INT TERM

if [ -t 2 ]; then progress=--progress-bar; else progress=-sS; fi
curl -fsSL -o "$temporary/SHA256SUMS" "$download/SHA256SUMS" ||
	die "unable to download $download/SHA256SUMS"

# Print the checksum that SHA256SUMS lists for a file, if any.
listed() {
	awk -v name="$1" '$2 == name || $2 == "*" name { print $1 }' "$temporary/SHA256SUMS"
}

# Download a release file and verify its checksum.
fetch() {
	echo "Downloading $1..."
	curl -fL "$progress" -o "$temporary/$1" "$download/$1" ||
		die "unable to download $download/$1"
	expected=$(listed "$1")
	[ -n "$expected" ] || die "$1 isn't listed in SHA256SUMS"
	if command -v sha256sum >/dev/null 2>&1; then
		actual=$(sha256sum "$temporary/$1" | cut -d ' ' -f 1)
	else
		actual=$(shasum -a 256 "$temporary/$1" | cut -d ' ' -f 1)
	fi
	[ "$actual" = "$expected" ] || die "checksum mismatch for $1"
}

fetch "$asset"
mkdir "$temporary/bundle"
tar -xzf "$temporary/$asset" -C "$temporary/bundle"
for file in mutagen remote; do
	[ -f "$temporary/bundle/$file" ] || die "$asset lacks $file"
done
reported=$("$temporary/bundle/mutagen" version) ||
	die "the downloaded mutagen doesn't run on this system"
[ "$reported" = "$version" ] ||
	die "the downloaded mutagen reports version $reported, not $version"

# Releases after v0.19.0-zlcwwhq.0.0.7 publish the agent bundle once, rather
# than in each platform's bundle.
agents=mutagen-agents_$tag.tar.gz
if [ -n "$(listed "$agents")" ]; then
	fetch "$agents"
	agents=$temporary/$agents
else
	agents=$temporary/bundle/mutagen-agents.tar.gz
	[ -f "$agents" ] || die "$asset lacks mutagen-agents.tar.gz"
fi
if [ "$records" = yes ] && [ "$(recorded "$agents")" != "$version" ]; then
	die "the agent bundle of $tag doesn't record version $version"
fi

{ mkdir -p "$bindir" "$bundledir" && [ -w "$bindir" ] && [ -w "$bundledir" ]; } 2>/dev/null ||
	die "unable to write to $bindir and $bundledir; use sudo or another --prefix"

# Stop the daemon only once everything is ready to be installed. A daemon run
# by the systemd user service would otherwise be restarted by it.
service=no
if [ "$restart" = yes ]; then
	if command -v systemctl >/dev/null 2>&1 &&
		systemctl --user is-active --quiet mutagen.service 2>/dev/null; then
		service=yes
		echo "Stopping the daemon (systemd user service)..."
		systemctl --user stop mutagen.service
	else
		stopper=$current
		[ -n "$stopper" ] || stopper=$bindir/mutagen
		if [ -x "$stopper" ]; then
			echo "Stopping the daemon..."
			"$stopper" daemon stop >/dev/null 2>&1 || true
		fi
	fi
fi

# Copy each file next to its destination and rename it into place, which also
# replaces executables that are running.
place() {
	cp "$1" "$2.$$"
	chmod "$3" "$2.$$"
	mv -f "$2.$$" "$2"
}
place "$agents" "$bundledir/mutagen-agents.tar.gz" 644
place "$temporary/bundle/remote" "$bindir/remote" 755
place "$temporary/bundle/mutagen" "$bindir/mutagen" 755
echo "Installed Mutagen $version: $bindir/mutagen, $bindir/remote, $bundledir/mutagen-agents.tar.gz"

# The stopped daemon may take a few seconds to exit, during which a new one
# can't start, so start it until this version answers.
if [ "$restart" = yes ]; then
	echo "Starting the daemon..."
	attempts=0
	until MUTAGEN_DISABLE_AUTOSTART=1 "$bindir/mutagen" sync list >/dev/null 2>&1; do
		attempts=$((attempts + 1))
		if [ "$attempts" -gt 60 ]; then
			die "the daemon of this version didn't start; check mutagen daemon start and mutagen sync list"
		fi
		if [ "$service" = yes ]; then
			systemctl --user start mutagen.service || true
		else
			"$bindir/mutagen" daemon start >/dev/null 2>&1 || true
		fi
		sleep 1
	done
	echo "The daemon is running Mutagen $version"
fi

if [ "$bundledir" != "$bindir" ] && [ -e "$bindir/mutagen-agents.tar.gz" ]; then
	echo "warning: delete $bindir/mutagen-agents.tar.gz, which belongs to an earlier installation" >&2
fi
case :$PATH: in
*:"$bindir":*) ;;
*) echo "warning: $bindir isn't on PATH" >&2 ;;
esac
for file in mutagen remote; do
	found=$(command -v "$file" 2>/dev/null) || continue
	if ! [ "$found" -ef "$bindir/$file" ]; then
		echo "warning: $found precedes $bindir/$file on PATH" >&2
	fi
done
if [ "$restart" = no ]; then
	echo "Restart a running daemon to use this version: mutagen daemon stop; mutagen daemon start"
fi
