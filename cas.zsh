# cas — Claude Account Switcher. Source from ~/.zshrc.
# `cas` must stay a shell function: switching mutates the calling shell's env.

_cas_valid_name() {
  [[ $1 =~ '^[A-Za-z0-9][A-Za-z0-9_-]*$' && $1 != (default|add|rm|heal) ]]
}

# Print the non-denylisted top-level entry names of canonical ~/.claude.
_cas_link_set() {
  emulate -L zsh
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
  print -r -- "Switch with 'cas $name', then run 'claude' and /login with the new account"
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

# Replace each forked entry of a profile with a symlink to canonical.
_cas_heal() {
  local name=${1:-${CAS_PROFILE-}}
  [[ -z $name || $name == default ]] &&
    { print -u2 "cas: heal needs an active profile or an explicit name"; return 1 }
  local dir=$HOME/.claude-profiles/$name
  _cas_valid_name "$name" && [[ -d $dir ]] ||
    { print -u2 "cas: unknown profile '$name'"; return 1 }
  local -a forked=(${(f)"$(_cas_forked $dir)"})
  (( $#forked )) || { print -r -- "Profile '$name' already canonical"; return 0 }
  local e
  for e in $forked; do
    rm -rf -- $dir/$e
    ln -s $HOME/.claude/$e $dir/$e || return 1
    print -r -- "Relinked '$e' to canonical"
  done
}

_cas_rm() {
  local name=$1
  [[ $name == default ]] && { print -u2 "cas: cannot remove 'default'"; return 1 }
  local dir=$HOME/.claude-profiles/$name
  _cas_valid_name "$name" && [[ -d $dir ]] ||
    { print -u2 "cas: unknown profile '$name'"; return 1 }
  if [[ -t 0 ]]; then read -q "?cas: delete profile '$name'? [y/N] "; else read -q -u 0; fi ||
    { print -u2; print -u2 "cas: aborted; profile '$name' untouched"; return 1 }
  print
  rm -rf -- $dir
  [[ ${CAS_PROFILE-} == $name ]] && { unset CLAUDE_CONFIG_DIR; export CAS_PROFILE=default }
  print -r -- "Profile '$name' removed"
  print -r -- "Its Keychain entry ('Claude Code-credentials') was NOT removed; delete it via Keychain Access if desired"
}

_cas_status() {
  emulate -L zsh
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
    heal)    _cas_heal "${2-}" ;;
    rm)      _cas_rm "${2-}" ;;
    default) unset CLAUDE_CONFIG_DIR; export CAS_PROFILE=default ;;
    '')      _cas_status ;;
    *)       _cas_switch "$1" ;;
  esac
}

_cas() {
  emulate -L zsh
  local -a profiles=($HOME/.claude-profiles/*(N/:t))
  if (( CURRENT == 2 )); then
    compadd -- add rm heal default $profiles
  elif (( CURRENT == 3 )) && [[ $words[2] == (rm|heal) ]]; then
    compadd -- $profiles
  fi
}

if (( $+functions[compdef] )); then
  compdef _cas cas
fi
