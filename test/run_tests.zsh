#!/usr/bin/env zsh
# Test harness for cas. Run: zsh test/run_tests.zsh

CAS_ZSH=${0:A:h:h}/cas.zsh
typeset -i pass=0 fail=0

assert_eq() {  # actual expected
  [[ $1 == $2 ]] || { print -u2 "  assert_eq: expected '$2', got '$1'"; exit 1 }
}
assert_file() {
  [[ -f $1 && ! -L $1 ]] || { print -u2 "  assert_file: $1 is not a regular file"; exit 1 }
}
assert_symlink_to() {
  [[ -L $1 && $(readlink -- $1) == $2 ]] ||
    { print -u2 "  assert_symlink_to: $1 -> $(readlink -- $1 2>/dev/null), expected -> $2"; exit 1 }
}
assert_not_exists() {
  [[ ! -e $1 && ! -L $1 ]] || { print -u2 "  assert_not_exists: $1 exists"; exit 1 }
}
assert_contains() {  # haystack needle
  [[ $1 == *$2* ]] || { print -u2 "  assert_contains: '$2' not found in: $1"; exit 1 }
}
asserts=$(typeset -f assert_eq assert_file assert_symlink_to assert_not_exists assert_contains)

make_home() {
  mkdir -p $1/.claude/plugins $1/.claude/debug
  print '{"model":"opus"}' > $1/.claude/settings.json
  print '# global memory'  > $1/.claude/CLAUDE.md
  print '{"display":"hi"}' > $1/.claude/history.jsonl
  print '1749500000'       > $1/.claude/.last-cleanup
  print '{"mcpServers":{"dummy":{"command":"dummy-server"}},"oauthAccount":{"emailAddress":"user@example.com"}}' > $1/.claude.json
}

run_test() {
  local name=$1 body=$2 sandbox
  sandbox=$(mktemp -d)
  make_home $sandbox
  if HOME=$sandbox zsh -f -c "$asserts
source ${(q)CAS_ZSH}
$body" >/dev/null; then
    print "PASS  $name"; (( ++pass ))
  else
    print "FAIL  $name"; (( ++fail ))
  fi
  rm -rf $sandbox
}

run_test "add creates profile dir" '
  cas add work || { print -u2 "  cas add work failed"; exit 1 }
  [[ -d $HOME/.claude-profiles/work ]] || { print -u2 "  profile dir missing"; exit 1 }
'

run_test "add links non-denylisted entries to canonical" '
  cas add work
  for e in settings.json CLAUDE.md plugins history.jsonl; do
    assert_symlink_to $HOME/.claude-profiles/work/$e $HOME/.claude/$e
  done
'

run_test "add skips denylisted entries" '
  cas add work || { print -u2 "  cas add work failed"; exit 1 }
  assert_not_exists $HOME/.claude-profiles/work/debug
  assert_not_exists $HOME/.claude-profiles/work/.last-cleanup
'

run_test "add seeds .claude.json with only mcpServers" '
  cas add work
  p=$HOME/.claude-profiles/work/.claude.json
  assert_file $p
  assert_eq "$(jq -S . $p)" "$(jq -S "{mcpServers}" $HOME/.claude.json)"
'

run_test "add tells the user how to switch and log in" '
  out=$(cas add work 2>&1)
  assert_contains "$out" "cas work"
  assert_contains "$out" "claude"
'

run_test "add refuses existing profile and leaves it untouched" '
  cas add work
  out=$(cas add work 2>&1); rc=$?
  assert_eq $rc 1
  assert_contains "$out" "already exists"
  assert_symlink_to $HOME/.claude-profiles/work/settings.json $HOME/.claude/settings.json
  assert_file $HOME/.claude-profiles/work/.claude.json
'

run_test "add rejects invalid and reserved names" '
  cas add bad/name 2>/dev/null; assert_eq $? 1
  cas add default  2>/dev/null; assert_eq $? 1
  assert_not_exists $HOME/.claude-profiles
'

run_test "add links entries even under nobareglobqual" '
  setopt nobareglobqual
  cas add work || { print -u2 "  cas add work failed"; exit 1 }
  assert_symlink_to $HOME/.claude-profiles/work/settings.json $HOME/.claude/settings.json
'

run_test "add rejects dash-leading name" '
  cas add -foo 2>/dev/null; assert_eq $? 1
  assert_not_exists $HOME/.claude-profiles
'

run_test "add is all-or-nothing on failure" '
  print "not json" > $HOME/.claude.json
  cas add work 2>/dev/null; assert_eq $? 1
  assert_not_exists $HOME/.claude-profiles/work
  print "{\"mcpServers\":{}}" > $HOME/.claude.json
  cas add work || { print -u2 "  retry after fixing json failed"; exit 1 }
  [[ -d $HOME/.claude-profiles/work ]] || { print -u2 "  profile dir missing"; exit 1 }
'

run_test "add creates the profiles root when missing" '
  assert_not_exists $HOME/.claude-profiles
  cas add work || { print -u2 "  cas add work failed"; exit 1 }
  [[ -d $HOME/.claude-profiles/work ]] || { print -u2 "  profile dir missing"; exit 1 }
'

run_test "switch exports CLAUDE_CONFIG_DIR and CAS_PROFILE" '
  cas add work
  cas work || { print -u2 "  cas work failed"; exit 1 }
  assert_eq "$CLAUDE_CONFIG_DIR" "$HOME/.claude-profiles/work"
  assert_eq "$CAS_PROFILE" "work"
'

run_test "default unsets CLAUDE_CONFIG_DIR" '
  cas add work
  cas work
  cas default || { print -u2 "  cas default failed"; exit 1 }
  assert_eq "${CLAUDE_CONFIG_DIR-}" ""
  assert_eq "$CAS_PROFILE" "default"
'

run_test "switch to unknown profile fails and leaves env unchanged" '
  out=$(cas nosuch 2>&1); rc=$?
  cas nosuch 2>/dev/null
  assert_eq $? 1
  assert_eq $rc 1
  assert_contains "$out" "unknown profile"
  assert_eq "${CLAUDE_CONFIG_DIR-}" ""
  assert_eq "${CAS_PROFILE-}" ""
'

run_test "switch syncs mcpServers and preserves other profile keys" '
  cas add work
  p=$HOME/.claude-profiles/work/.claude.json
  print "{\"mcpServers\":{\"new\":{\"command\":\"new-server\"}}}" > $HOME/.claude.json
  tmp=$p.tmp.$$
  jq ". + {oauthAccount:{emailAddress:\"work@example.com\"}}" $p > $tmp && mv $tmp $p
  cas work || { print -u2 "  cas work failed"; exit 1 }
  assert_eq "$(jq -c .mcpServers $p)" "$(jq -c .mcpServers $HOME/.claude.json)"
  assert_eq "$(jq -r .oauthAccount.emailAddress $p)" "work@example.com"
'

run_test "switch aborts before touching env when canonical .claude.json is bad" '
  cas add work
  print "not json" > $HOME/.claude.json
  cas work 2>/dev/null; assert_eq $? 1
  assert_eq "${CLAUDE_CONFIG_DIR-}" ""
  assert_eq "${CAS_PROFILE-}" ""
  rm $HOME/.claude.json
  out=$(cas work 2>&1); assert_eq $? 1
  assert_contains "$out" ".claude.json"
  assert_eq "${CLAUDE_CONFIG_DIR-}" ""
'

run_test "switch warns about forked entries but still succeeds" '
  cas add work
  rm $HOME/.claude-profiles/work/settings.json
  print "{\"model\":\"sonnet\"}" > $HOME/.claude-profiles/work/settings.json
  err=$( { cas work; } 2>&1 ); rc=$?
  assert_eq $rc 0
  assert_contains "$err" "settings.json"
  assert_contains "$err" "cas heal"
  cas work 2>/dev/null || exit 1
  assert_eq "$CAS_PROFILE" "work"
'

run_test "bare cas shows default active with canonical email" '
  out=$(cas) || { print -u2 "  bare cas failed"; exit 1 }
  assert_contains "$out" "* default"
  assert_contains "$out" "user@example.com"
'

run_test "bare cas shows (not logged in) without oauthAccount" '
  print "{\"mcpServers\":{}}" > $HOME/.claude.json
  out=$(cas) || { print -u2 "  bare cas failed"; exit 1 }
  assert_contains "$out" "(not logged in)"
'

run_test "bare cas lists profiles, marks active, shows its email" '
  cas add work
  p=$HOME/.claude-profiles/work/.claude.json
  tmp=$p.tmp.$$
  jq ". + {oauthAccount:{emailAddress:\"work@example.com\"}}" $p > $tmp && mv $tmp $p
  cas work
  out=$(cas) || { print -u2 "  bare cas failed"; exit 1 }
  assert_contains "$out" "  default"
  assert_contains "$out" "* work"
  assert_contains "$out" "work@example.com"
  [[ $out != *user@example.com* ]] || { print -u2 "  canonical email leaked: $out"; exit 1 }
'

run_test "heal relinks forked entry, canonical wins" '
  cas add work
  cas work 2>/dev/null
  rm $HOME/.claude-profiles/work/CLAUDE.md
  print "# forked memory" > $HOME/.claude-profiles/work/CLAUDE.md
  out=$(cas heal); rc=$?
  assert_eq $rc 0
  assert_contains "$out" "CLAUDE.md"
  assert_symlink_to $HOME/.claude-profiles/work/CLAUDE.md $HOME/.claude/CLAUDE.md
  assert_eq "$(<$HOME/.claude/CLAUDE.md)" "# global memory"
'

run_test "heal links new canonical entries" '
  cas add work
  mkdir $HOME/.claude/skills
  cas heal work || { print -u2 "  cas heal work failed"; exit 1 }
  assert_symlink_to $HOME/.claude-profiles/work/skills $HOME/.claude/skills
'

run_test "heal never touches denylisted entries" '
  cas add work
  p=$HOME/.claude-profiles/work/.claude.json
  before=$(<$p)
  out=$(cas heal work) || { print -u2 "  cas heal work failed"; exit 1 }
  assert_contains "$out" "already canonical"
  assert_file $p
  assert_eq "$(<$p)" "$before"
'

run_test "heal needs an active profile or an explicit name" '
  cas add work
  out=$(cas heal 2>&1); assert_eq $? 1
  assert_contains "$out" "active profile"
  cas default
  out=$(cas heal 2>&1); assert_eq $? 1
  assert_contains "$out" "active profile"
  cas heal work || { print -u2 "  explicit name on default failed"; exit 1 }
'

run_test "heal rejects unknown profile" '
  out=$(cas heal nosuch 2>&1); assert_eq $? 1
  assert_contains "$out" "nosuch"
'

run_test "rm removes profile, canonical data survives" '
  cas add work
  cas rm work <<< y || { print -u2 "  cas rm work failed"; exit 1 }
  assert_not_exists $HOME/.claude-profiles/work
  assert_eq "$(<$HOME/.claude/settings.json)" "{\"model\":\"opus\"}"
  assert_file $HOME/.claude/CLAUDE.md
'

run_test "rm answering n leaves profile untouched" '
  cas add work
  cas rm work <<< n 2>/dev/null; assert_eq $? 1
  [[ -d $HOME/.claude-profiles/work ]] || { print -u2 "  profile dir gone"; exit 1 }
  assert_symlink_to $HOME/.claude-profiles/work/settings.json $HOME/.claude/settings.json
  assert_file $HOME/.claude-profiles/work/.claude.json
'

run_test "rm refuses default" '
  out=$(cas rm default <<< y 2>&1); assert_eq $? 1
  assert_contains "$out" "default"
'

run_test "rm rejects unknown profile and missing argument" '
  out=$(cas rm nosuch <<< y 2>&1); assert_eq $? 1
  assert_contains "$out" "nosuch"
  cas rm <<< y 2>/dev/null; assert_eq $? 1
'

run_test "rm notes Keychain credentials are not removed" '
  cas add work
  out=$(cas rm work <<< y 2>&1); assert_eq $? 0
  assert_contains "$out" "Keychain"
'

run_test "rm of active profile resets shell to default" '
  cas add work
  cas work
  cas rm work <<< y || { print -u2 "  cas rm work failed"; exit 1 }
  assert_eq "${CLAUDE_CONFIG_DIR-}" ""
  assert_eq "$CAS_PROFILE" "default"
'

print -- "--"
print "$pass passed, $fail failed"
(( fail == 0 ))
