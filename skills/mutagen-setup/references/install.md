# Installing the zlcwwhq/mutagen fork

Releases at <https://github.com/zlcwwhq/mutagen/releases> are tagged
`v0.19.0-zlcwwhq.X.Y.Z`. Each platform's bundle,
`mutagen_<os>_<arch>_<tag>.tar.gz` (and `.zip` for Windows), contains
`mutagen`, `remote`, and `mutagen-agents.tar.gz`, which `mutagen` needs to
install agents on endpoints: it looks for it in its own directory, or in
`../libexec` if it's in a `bin` directory. `SHA256SUMS` lists the bundles'
checksums. Bundles are about 130 MB, because the agent bundle covers every
endpoint platform.

Only the daemon's system needs an installation. Endpoints get agents, which
also act as `remote` there, from the daemon when sessions connect.

## Before installing or upgrading

- **Running daemon**: the daemon's version must match `mutagen`'s, so a running
  daemon (`mutagen sync list` succeeds or reports a version mismatch) must be
  restarted, which needs the user's consent. The script's `--restart-daemon`
  does this; by hand, run `mutagen daemon stop` (or
  `systemctl --user stop mutagen` for the service below) before installing and
  `mutagen daemon start` afterwards. Sessions resume, and endpoints receive the
  new version's agents when they reconnect.
- **Other installations**: `type -a mutagen remote` lists them. Upstream
  Mutagen (such as Homebrew's `mutagen-io/mutagen/mutagen`) uses the same data
  directory, `~/.mutagen`, so the fork's daemon resumes its sessions; stop its
  daemon first, since only one daemon runs at a time. The fork's `mutagen` and
  `remote` must come first on `PATH`: ask the user before uninstalling another
  installation or changing the order.
- Don't install a release older than the installed one unless the user asks.

## Linux, macOS, and FreeBSD

```sh
sh <skill-directory>/scripts/install.sh [--check] [--restart-daemon] [--prefix DIR] [--version TAG]
```

The script installs the latest release (or `TAG`). If the `mutagen` on `PATH`
is a fork release, it replaces that installation in place, keeping the agent
bundle where it is (next to `mutagen` or in `../libexec`); otherwise it
installs into `~/.local` (or `DIR`): `bin/mutagen`, `bin/remote`, and
`libexec/mutagen-agents.tar.gz`. It does nothing if that release is already
installed completely, and `--check` only reports what it would do.

It verifies the checksum and that the binary runs and reports the release's
version before changing anything, then replaces files by renaming. With
`--restart-daemon`, it stops the daemon (or the systemd user service) after the
download and starts it again until the new version answers. It warns if `bin`
isn't on `PATH`, if other `mutagen` or `remote` executables precede it, or if
an old agent bundle sits in `bin`. For a system-wide installation, use
`--prefix /usr/local` with `sudo`, and restart the daemon as the user.

If `bin` isn't on `PATH`, add it in the user's shell profile with the user's
agreement, such as `export PATH="$HOME/.local/bin:$PATH"` in `~/.profile`
(bash), `~/.zprofile` (zsh on macOS), or `~/.config/fish/config.fish`
(`fish_add_path ~/.local/bin`). Then check in a new login shell that
`mutagen version` and `remote --version` print the same version.

## Windows

Install the `.zip` bundle with PowerShell. All three files stay in one
directory, which goes on the user's `PATH`:

```powershell
$repository = 'zlcwwhq/mutagen'
$tag = (Invoke-RestMethod "https://api.github.com/repos/$repository/releases/latest").tag_name
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$asset = "mutagen_windows_${arch}_$tag.zip"
$download = "https://github.com/$repository/releases/download/$tag"
$temporary = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "mutagen-$tag") -Force
Invoke-WebRequest "$download/$asset" -OutFile "$temporary\$asset"
Invoke-WebRequest "$download/SHA256SUMS" -OutFile "$temporary\SHA256SUMS"
$expected = ((Get-Content "$temporary\SHA256SUMS") -match "  $([regex]::Escape($asset))$" -split ' ')[0]
if (-not $expected -or (Get-FileHash "$temporary\$asset" -Algorithm SHA256).Hash -ne $expected) { throw "checksum mismatch for $asset" }
$directory = "$env:LOCALAPPDATA\Programs\Mutagen"
Expand-Archive "$temporary\$asset" -DestinationPath $directory -Force
Remove-Item -Recurse $temporary
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($path -split ';') -notcontains $directory) {
    [Environment]::SetEnvironmentVariable('Path', "$directory;$path", 'User')
}
```

Stop a running daemon first (`mutagen daemon stop`), since Windows can't
replace a running `mutagen.exe`, and start it afterwards. To upgrade, set
`$directory` to the existing installation's directory
(`Split-Path (Get-Command mutagen).Source`). New terminals see the updated
`PATH`. Mutagen uses the `ssh` of
Git for Windows if it's installed, and otherwise the OpenSSH client in
`C:\Windows\System32\OpenSSH` (`MUTAGEN_SSH_PATH` names another directory), so
check SSH access with that client.

## Starting the daemon at login

- **macOS and Windows**: `mutagen daemon register` starts the daemon at login
  (`mutagen daemon unregister` reverses it). Run it with the installed
  `mutagen`, since registration records its path.
- **Linux with systemd**: create `~/.config/systemd/user/mutagen.service`:

  ```ini
  [Unit]
  Description=Mutagen daemon

  [Service]
  ExecStart=%h/.local/bin/mutagen daemon run
  Restart=on-failure

  [Install]
  WantedBy=default.target
  ```

  Adjust `ExecStart` if `mutagen` is installed elsewhere. Then run
  `mutagen daemon stop` and `systemctl --user enable --now mutagen.service`.
  `install.sh --restart-daemon` restarts the service after upgrades. The
  service doesn't see the login session's SSH agent, so SSH keys that need one
  won't work; to keep user services running without a login, the user can run
  `loginctl enable-linger`.
- **Other systems**, including WSL without systemd: add
  `mutagen daemon start >/dev/null 2>&1` to the shell profile. Commands that
  need the daemon, such as `mutagen sync list`, also start it.
