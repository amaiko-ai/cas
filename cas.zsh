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

# Print link-set entries of a profile that are not symlinks to canonical.
_cas_forked() {
  local dir=$1 e
  for e in ${(f)"$(_cas_link_set)"}; do
    [[ -L $dir/$e && $(readlink -- $dir/$e) == $HOME/.claude/$e ]] || print -r -- $e
  done
}

_cas_switch() {
  local name=$1
  local dir=$HOME/.claude-profiles/$name
  _cas_valid_name "$name" && [[ -d $dir ]] ||
    { print -u2 "cas: unknown profile '$name'"; return 1 }

  local pj=$dir/.claude.json tmp=$dir/.claude.json.tmp.$$
  if [[ -f $pj ]]; then
    jq --slurpfile c $HOME/.claude.json '. + {mcpServers: $c[0].mcpServers}' $pj > $tmp
  else
    jq '{mcpServers}' $HOME/.claude.json > $tmp
  fi || { rm -f $tmp
          print -u2 "cas: cannot sync mcpServers from $HOME/.claude.json; switch aborted"
          return 1 }
  mv $tmp $pj || return 1

  local -a forked=(${(f)"$(_cas_forked $dir)"})
  if (( $#forked )); then
    local e
    for e in $forked; do
      print -u2 "cas: warning: '$e' in profile '$name' is not a symlink to canonical"
    done
    print -u2 "cas: run 'cas heal' to relink"
  fi

  export CLAUDE_CONFIG_DIR=$dir CAS_PROFILE=$name
}

_cas_status() {
  local active=${CAS_PROFILE:-${${CLAUDE_CONFIG_DIR-}:t}}
  : ${active:=default}
  local json=$HOME/.claude.json
  [[ $active != default ]] && json=$HOME/.claude-profiles/$active/.claude.json
  local email=$(jq -r '.oauthAccount.emailAddress // empty' "$json" 2>/dev/null)
  local name
  for name in default $HOME/.claude-profiles/*(N/:t); do
    if [[ $name == "$active" ]]; then
      print -r -- "* $name  ${email:-(not logged in)}"
    else
      print -r -- "  $name"
    fi
  done
}

cas() {
  case ${1-} in
    add)     _cas_add "${2-}" ;;
    default) unset CLAUDE_CONFIG_DIR; export CAS_PROFILE=default ;;
    '')      _cas_status ;;
    *)       _cas_switch "$1" ;;
  esac
}
