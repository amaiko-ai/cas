# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cas` — Claude Account Switcher. A single zsh script (`cas.zsh`) sourced from
`~/.zshrc` that lets each terminal run a different Claude Code account
concurrently, while sharing all non-account state (settings, plugins, memories,
history) between accounts. macOS + zsh + jq only.

## Commands

```sh
zsh test/run_tests.zsh    # run the full test suite
```

There is no build or lint step. Tests are inline `run_test "name" 'body'`
blocks in `test/run_tests.zsh`; there is no single-test selector — to iterate
on one test, the suite is fast enough to run whole. Each test runs in a fresh
`mktemp -d` sandbox with `HOME` overridden and a minimal fake `~/.claude`
created by `make_home`, executed in a clean `zsh -f -c` subshell that sources
`cas.zsh`.

## Architecture

Design rationale and verified facts live in
`docs/superpowers/specs/2026-06-10-cas-design.md` — read it before changing
behavior.

Core model:

- The default account is canonical and untouched: `~/.claude` +
  `~/.claude.json`, with `CLAUDE_CONFIG_DIR` unset.
- Each profile is `~/.claude-profiles/<name>/`, a **symlink view** onto
  canonical `~/.claude`. The link set is computed dynamically from whatever
  exists in `~/.claude` (`_cas_link_set`) minus a **denylist** of
  account-bound/ephemeral entries (`.claude.json`, `debug/`,
  `policy-limits.json`, `remote-settings.json`, …). When Claude Code starts
  creating a new account-bound file, the fix is to add it to the denylist.
- Per-profile real files: `.claude.json` (seeded with only `mcpServers` from
  canonical, re-synced on every switch) and the Keychain credentials, which
  Claude Code creates itself on `/login` (keyed by config dir path).
- Switching = `export CLAUDE_CONFIG_DIR=<profile dir> CAS_PROFILE=<name>`,
  per shell. `cas default` just unsets `CLAUDE_CONFIG_DIR`. Switches are
  **sticky**: the selection is persisted in `~/.claude-profiles/.current` and
  re-applied (via the normal `_cas_switch` path) when `cas.zsh` is sourced in
  a fresh shell; an inherited selection in the environment always wins.
- **Forking**: Claude Code rewrites shared files via temp-file-plus-rename,
  which replaces a symlink with a real file and silently detaches that entry
  from canonical. `_cas_forked` detects this on every switch and warns;
  `cas heal` discards the fork and re-links.

## Constraints

- `cas` must remain a shell function, not a script — switching mutates the
  calling shell's environment.
- Helpers that use zsh options (globbing flags, etc.) use `emulate -L zsh` to
  localize them; keep that pattern for new helpers.
- `compdef` registration is guarded on `$+functions[compdef] && $+_comps`
  because the script may be sourced before the completion system is
  initialized.
- Profile names are validated by `_cas_valid_name`; subcommand words
  (`default`, `add`, `rm`, `heal`) are reserved.
