# cas — Claude Account Switcher (Design)

Date: 2026-06-10
Status: Approved by Stefan

## Problem

Stefan runs multiple Claude Code accounts on one macOS machine and wants to switch
between them quickly — including running *different accounts concurrently in
different terminals* — while sharing all non-account state: settings, global
CLAUDE.md, plugins, agents, commands, memories, session history, output styles.

## Key facts (verified on this machine, 2026-06-10)

- Claude Code's per-account state on macOS is exactly two things:
  1. OAuth tokens in the login Keychain (item `Claude Code-credentials` for the
     default config dir).
  2. The `oauthAccount` key (plus account-flavored caches) inside `.claude.json`.
- Everything else in `~/.claude/` and `~/.claude.json` is account-independent.
- `CLAUDE_CONFIG_DIR` relocates the entire config dir, including `.claude.json`
  and credentials. It is the established multi-account mechanism; community
  tooling (Maestro docs, multiple guides) relies on per-config-dir credentials
  working on macOS.
- User-scoped MCP servers live in `.claude.json` under the `mcpServers` key.

## Rejected approaches

- **Keychain swap, single config dir**: swap the Keychain item + `oauthAccount`
  per profile. Simplest sharing story, but the active account is global to the
  machine — Stefan requires per-terminal concurrency. Rejected.
- **Fully isolated `CLAUDE_CONFIG_DIR` dirs** (the common community recipe):
  trivially concurrent, but shares nothing — settings, plugins, and memories
  fork per account. Rejected.

## Chosen design

Per-profile config dirs that are **symlink views onto the canonical `~/.claude`**,
activated per-shell by a sticky zsh switcher.

### Layout

- The default account remains canonical and untouched: `~/.claude` and
  `~/.claude.json`. "Default" means `CLAUDE_CONFIG_DIR` is unset.
- Each additional account gets `~/.claude-profiles/<name>/`:
  - Every top-level entry of `~/.claude` (settings.json, settings.local.json,
    CLAUDE.md, plugins/, agents/, commands/, projects/, output-styles/,
    scripts/, plans/, teams/, tasks/, history.jsonl, statusline scripts, …) is
    a symlink to the canonical entry. The symlink set is computed dynamically
    from whatever exists in `~/.claude` at scaffold/heal time — no hardcoded
    whitelist to go stale.
  - Per-profile (real files, never linked): `.claude.json`, and entries on a
    small denylist of genuinely ephemeral/account-bound state: `debug/`,
    `.credentials.json` (if it ever appears), `.last-update-result.json`,
    `.last-cleanup`, `stats-cache.json`, `mcp-needs-auth-cache.json`.
  - Keychain credentials are created by Claude Code itself on first `/login`
    inside the profile.

### `.claude.json` handling

Per-profile, because it contains `oauthAccount` and account-bound caches. To
keep user-scoped MCP servers shared, every `cas <name>` switch performs a
one-way jq sync of the `mcpServers` key from canonical `~/.claude.json` into
the profile's `.claude.json`. Convention: user-level MCP servers are managed on
the default account; profiles inherit on next switch.

### Symlink-fork failure mode

If Claude Code rewrites a shared file via temp-file-plus-rename, the symlink in
the profile is replaced by a real file and that profile silently forks. Every
switch runs a fast heal *check* (compare top-level entries against the expected
symlink set) and prints a warning naming forked entries. `cas heal` re-links
them; healing a forked entry is destructive to the forked copy, so heal prints
what it replaces.

## The tool

One pure-zsh file, `cas.zsh`, living in this repo (`~/dev/amaiko/cas`), sourced
from `~/.zshrc`. Dependencies: zsh, jq. No frameworks.

### Commands

- `cas` — show the active account (profile name + email read from the active
  `.claude.json`) and list all profiles, marking the active one.
- `cas <name>` — switch the current shell: export `CLAUDE_CONFIG_DIR` to the
  profile dir, export `CAS_PROFILE=<name>`, run the mcpServers sync and the
  heal check. Fails with a clear message if the profile doesn't exist.
- `cas default` — unset `CLAUDE_CONFIG_DIR`, set `CAS_PROFILE=default`.
  `default` is therefore a reserved profile name.
- `cas add <name>` — scaffold `~/.claude-profiles/<name>` with the symlink set,
  create a minimal `.claude.json` containing only the `mcpServers` key copied
  from canonical (Claude Code fills in the rest on first run), then instruct
  the user to switch to it and run `claude` once to complete `/login`.
- `cas rm <name>` — remove a profile directory after interactive confirmation.
  Refuses `default`. Since profile contents are symlinks plus `.claude.json`,
  removal never destroys shared data. Notes that the Keychain entry for that
  profile is not removed (harmless orphan; removal command mentioned in output).
- `cas heal` — re-link any forked entries and create links for new top-level
  entries that appeared in `~/.claude` since scaffold time.

### zsh integration

- Tab completion for subcommands and profile names.
- `CAS_PROFILE` exported on every switch so it can be embedded in any prompt;
  no prompt is modified by default.
- Sourced via one line in `~/.zshrc` (oh-my-zsh custom dir also works).

## Error handling

- Every command validates profile names (no slashes, not `default` where
  disallowed) and existence before acting.
- The switcher never writes to `~/.claude` or canonical `~/.claude.json`
  (the mcpServers sync reads canonical, writes profile).
- jq failures or a missing canonical `.claude.json` abort the switch with a
  message rather than half-switching.

## Verification plan

1. `cas add work`, switch, run `claude`, complete `/login` with the second
   account.
2. Empirically confirm the Keychain got a *separate* credential entry and the
   default account still works. If credentials turn out to be shared at the
   Keychain level, fall back to profile-local `.credentials.json` (supported by
   Claude Code) and update this spec.
3. Two terminals side by side, one `default`, one `work`: `/status` shows
   different accounts.
4. Edit `~/.claude/CLAUDE.md` and confirm both sessions see it; confirm a
   memory written in one profile is visible in the other.
5. Heal check: replace a profile symlink with a real file, confirm the switch
   warns and `cas heal` fixes it.
