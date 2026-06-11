# cas — Claude Account Switcher

Switch Claude Code accounts per terminal: each shell can run a different
account concurrently. Everything is shared between accounts — settings,
plugins, agents, memories, session history — except credentials and account
identity.

## Requirements

- macOS
- zsh
- jq

## Install

```sh
git clone https://github.com/amaiko-ai/cas.git ~/dev/amaiko/cas
```

Add to `~/.zshrc`:

```sh
source ~/dev/amaiko/cas/cas.zsh
```

## Usage

| Command          | Description                                                        |
| ---------------- | ------------------------------------------------------------------ |
| `cas`            | Show the active profile (with account email) and list all profiles |
| `cas <name>`     | Switch this shell to a profile; syncs shared MCP servers and warns about forked entries |
| `cas default`    | Switch this shell back to the default (canonical) account          |
| `cas -t <name>`  | Transient switch: this shell only, new terminals are unaffected    |
| `cas add <name>` | Create a new profile                                               |
| `cas rm <name>`  | Delete a profile after confirmation                                |
| `cas heal [name]`| Re-link forked entries of a profile (active one if no name given)  |

First-time setup of a profile: `cas add work && cas work && claude`, then `/login`
with the second account.

Switching is **sticky**: the selection is remembered
(`~/.claude-profiles/.current`), and new terminals start in the last selected
profile. `cas default` makes new terminals start on the default account again.
A shell that already has a selection (e.g. a nested shell) keeps it.
`cas -t <name>` (or `cas -t default`) switches only the current shell.

## Prompt embedding

`$CAS_PROFILE` holds the active profile name. For example:

```sh
PROMPT='[${CAS_PROFILE:-default}] '$PROMPT
```

## How it works

Profiles in `~/.claude-profiles/<name>/` are symlink views onto the canonical
`~/.claude`; only `.claude.json` and the Keychain credentials are per-profile.
If Claude Code rewrites a shared file via temp-file-plus-rename, the symlink is
replaced by a real file and that entry silently forks — `cas <name>` detects
this and warns. `cas heal` re-links forked entries to canonical, discarding the
forked copy.
