# mutagen-remote skill

Agent skills for the [zlcwwhq/mutagen](https://github.com/zlcwwhq/mutagen) fork,
whose `remote` executable runs commands on the other side of a Mutagen
synchronization session:

- [`mutagen-remote`](skills/mutagen-remote/SKILL.md) teaches coding agents to
  use `remote`: synchronization around commands, quoting, long-running jobs,
  troubleshooting, and resolving conflicts with `remote` alone, without the
  `mutagen` CLI.
- [`mutagen-setup`](skills/mutagen-setup/SKILL.md) sets Mutagen up for a
  project on the user's request: it installs or upgrades the fork from its
  latest release when it's missing or outdated, starts the daemon, writes
  `mutagen.yml` with the alpha and beta endpoints, starts the sessions, and
  makes `remote` usable on the endpoints.

This repository is also a plugin marketplace that distributes both skills in
one plugin, `mutagen-remote`, for Claude Code and Codex.

## Installing

Install the plugin on each system where agents submit commands with `remote` or
set up Mutagen. The skills are then available as `mutagen-remote:mutagen-remote`
and `mutagen-remote:mutagen-setup`. Agents use the first automatically when a
task needs to run on the other side of a session, and the second when asked to
set up, repair, or upgrade Mutagen.

### Claude Code

In Claude Code, run:

```
/plugin marketplace add zlcwwhq/mutagen-remote-skill
/plugin install mutagen-remote@mutagen-remote-skill
```

Or, from a shell:

```sh
claude plugin marketplace add zlcwwhq/mutagen-remote-skill
claude plugin install mutagen-remote@mutagen-remote-skill
```

Claude Code doesn't update third-party marketplaces automatically by default.
To receive updates automatically, enable auto-update for the
`mutagen-remote-skill` marketplace in `/plugin` (Marketplaces tab), or add it
to `~/.claude/settings.json` with auto-update enabled:

```json
{
  "extraKnownMarketplaces": {
    "mutagen-remote-skill": {
      "source": { "source": "github", "repo": "zlcwwhq/mutagen-remote-skill" },
      "autoUpdate": true
    }
  }
}
```

Updates are checked after Claude Code starts and take effect in the next
session, or after `/reload-plugins`. To update by hand, run
`/plugin marketplace update mutagen-remote-skill`.

### Codex

From a shell, run:

```sh
codex plugin marketplace add zlcwwhq/mutagen-remote-skill
codex plugin add mutagen-remote@mutagen-remote-skill
```

Alternatively, after adding the marketplace, install the plugin from the
`/plugins` browser in a Codex session. The skills are available in sessions
started afterwards (`/skills` lists them).

Codex keeps marketplaces added from Git up to date by itself: whenever it
starts, it checks the marketplace for new commits in the background and, if
there are any, updates the installed plugin, which later sessions use. No
setting is needed. To update right away, run:

```sh
codex plugin marketplace upgrade mutagen-remote-skill
```

Codex's default `workspace-write` sandbox has no network access, which also
prevents `remote` from connecting to the Unix sockets through which it reaches
the daemon: it fails with `connect: operation not permitted`. To let agents use
`remote` in the sandbox, allow network access in `~/.codex/config.toml`:

```toml
[sandbox_workspace_write]
network_access = true
```

Otherwise, approve running `remote` outside the sandbox when the agent asks.
Setting up Mutagen also downloads releases, writes outside the project (such
as to `~/.local` and `~/.mutagen`), and starts the daemon, so expect to approve
those commands as well.

### Other agents

Other agents that support skills can use the directories in `skills` directly,
by copying or linking them into their skills directory.

## Example: setting up Mutagen with `mutagen-setup`

Run the agent in the project directory on the system that should run the
Mutagen daemon, usually your workstation, which becomes alpha. Then ask, for
example:

> Set up Mutagen for this project: sync it with `gpu-box:~/projects/myproject`,
> run commands on gpu-box, and activate the conda environment `torch` there
> before each command.

The agent summarizes its plan and asks before anything that changes your
system or sessions. Then it:

1. Runs the skill's `install.sh --check`. If Mutagen is missing, it installs
   the latest release of the fork into `~/.local` (`bin/mutagen`, `bin/remote`,
   and the agent bundle in `libexec`), after verifying its checksum, and tells
   you if `~/.local/bin` needs to be added to `PATH`.
2. Starts the daemon (`mutagen daemon start`).
3. Checks that `ssh -o BatchMode=yes gpu-box true` works without prompts, and
   shows you any existing content in `~/projects/myproject` on gpu-box before
   synchronizing into it.
4. Locates conda on gpu-box and writes a prologue there,
   `~/.config/remote-prologue.sh`:

   ```sh
   eval "$("$HOME/miniconda3/bin/conda" shell.posix hook)"
   conda activate torch
   ```

5. Writes `mutagen.yml` in the project directory:

   ```yaml
   sync:
     myproject:
       alpha: "."
       beta: "gpu-box:~/projects/myproject"
       mode: "two-way-safe"
       remote: beta
       ignore:
         vcs: true
         paths:
           - "/mutagen.yml.lock"
           - ".venv/"
           - "__pycache__/"
       configurationBeta:
         remotePrologue: "~/.config/remote-prologue.sh"
   ```

6. Shows you `mutagen project apply --dry-run`, then runs
   `mutagen project apply` and `mutagen project flush`, and checks the result:

   ```sh
   remote pwd                     # the directory on gpu-box
   remote python -c 'import torch; print(torch.cuda.is_available())'
   ```

7. Reports what it installed, the session's status, and what's left to you,
   such as `PATH` changes in your shell profile or starting the daemon at login.

If agents also work on gpu-box and run commands back on your workstation, ask
for commands in both directions. The agent then sets `remote: true` and
installs a `remote` on gpu-box that keeps working across Mutagen upgrades.

Later, ask "Is there a newer Mutagen release?" or "Upgrade Mutagen". The agent
compares the installed version with the latest release and, once you agree to
restart the daemon, runs `install.sh --restart-daemon`, which upgrades the
installation in place and waits until the new daemon is running. It then checks
that the sessions reconnect.

## Versions

The `main` branch describes `remote` as of the latest release of the fork, and
every commit to it is an update. If the installed `remote` is older and lacks an
option that the skill describes, the skill tells agents to follow
`remote --help` instead. `mutagen-setup` installs the latest release. The fork
references the matching version of this repository as a Git submodule at
`skills/mutagen-remote`.

## License

MIT; see [LICENSE](LICENSE).
