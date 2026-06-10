# cas — Claude Account Switcher. Source from ~/.zshrc.
# `cas` must stay a shell function: switching mutates the calling shell's env.

_cas_valid_name() {
  [[ $1 =~ '^[A-Za-z0-9_-]+$' && $1 != (default|add|rm|heal) ]]
}

# Print the non-denylisted top-level entry names of canonical ~/.claude.
_cas_link_set() {
  local -a deny=(.claude.json .credentials.json debug .last-update-result.json
                 .last-cleanup stats-cache.json mcp-needs-auth-cache.json)
  local e
  for e in $HOME/.claude/*(ND:t); do
    (( $deny[(Ie)$e] )) || print -r -- $e
  done
}

# Link the link set and seed .claude.json into a freshly made profile dir.
_cas_build_profile() {
  local dir=$1 e
  mkdir -p $dir || return 1
  for e in ${(f)"$(_cas_link_set)"}; do
    ln -s $HOME/.claude/$e $dir/$e || return 1
  done
  local tmp=$dir/.claude.json.tmp.$$
  jq '{mcpServers}' $HOME/.claude.json > $tmp && mv $tmp $dir/.claude.json
}

_cas_add() {
  local name=$1
  _cas_valid_name "$name" || { print -u2 "cas: invalid profile name '$name'"; return 1 }
  local dir=$HOME/.claude-profiles/$name
  [[ -e $dir ]] && { print -u2 "cas: profile '$name' already exists"; return 1 }
  _cas_build_profile $dir ||
    { rm -rf $dir; print -u2 "cas: failed to create profile '$name'"; return 1 }
  print -r -- "Profile '$name' created at $dir"
  print -r -- "Switch with 'cas $name', then run 'claude' and /login with the new account."
}

cas() {
  case ${1-} in
    add) _cas_add "${2-}" ;;
    *)   print -u2 "cas: unknown command '${1-}'"; return 1 ;;
  esac
}
