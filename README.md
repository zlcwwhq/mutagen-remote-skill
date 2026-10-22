# mutagen-remote skill

An agent skill that teaches coding agents to use `remote`, the executable that
runs commands on the other side of a Mutagen synchronization session, from the
[zlcwwhq/mutagen](https://github.com/zlcwwhq/mutagen) fork. It covers
synchronization around commands, quoting, long-running jobs, troubleshooting,
and resolving conflicts with `remote` alone, without the `mutagen` CLI.

The skill is in [`skills/mutagen-remote`](skills/mutagen-remote/SKILL.md). This
repository is also a Claude Code plugin marketplace that distributes it.

## Installing in Claude Code

On each system where agents submit commands with `remote`, run:

```
/plugin marketplace add zlcwwhq/mutagen-remote-skill
/plugin install mutagen-remote@mutagen-remote-skill
```

The skill is then available as `mutagen-remote:mutagen-remote`, and agents use
it automatically when a task needs to run on the other side of a session.

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

Other agents that support skills can use the `skills/mutagen-remote` directory
directly, by copying or linking it into their skills directory.

## Versions

The `main` branch describes `remote` as of the latest release of the fork, and
every commit to it is an update. If the installed `remote` is older and lacks an
option that the skill describes, the skill tells agents to follow
`remote --help` instead. The fork references the matching version of this
repository as a Git submodule at `skills/mutagen-remote`.

## License

MIT; see [LICENSE](LICENSE).
