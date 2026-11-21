#!/usr/bin/env bash
# hmd-skills use-case suite: the journeys a person or an agent comes to these skills to get done, run through the doors they use.
#
#   bash tests/use_cases/run.sh      exit 0 every journey passed (a skipped one is said, never hidden), 1 a journey is broken, 2 bad setup
#
# Journeys (the suite's spec: a journey with no scenario is a gap, a scenario with no journey is deleted):
#   load a skill ................... an agent opens skills/<id>/SKILL.md (stacks, designmatch, self-improve, system-health, mac-deep-clean) and
#                                    finds the name it is invoked by and the description that says when to reach for it
#   follow a skill's pointers ...... every file a SKILL.md names exists: its own references, scripts and assets and its sibling skills here,
#                                    the host's bin, commands, agents, docs and test files there
#   get the stack pack for a repo .. the host's stack-pack, run on a FastAPI, Next.js, React Native or Spring Boot repo, prints THIS repo's pack
#                                    for it; the repo's own .planning/skills notes come after it; a repo of no known stack gets none
#   score a screen ................. designmatch's emit-parity turns the harness's metrics.json into parity.json and a badge (green only at
#                                    SSIM >= 0.95); with no metrics, or no score in them, it writes no receipt
#   know what the host provides .... HOST-CONTRACT.md names every host command the skills tell an agent to run, and the host has each one it names
#
# The host is heimdall, which owns the commands the skills call (HOST-CONTRACT.md). It is HMD_HOST_DIR when set (it must hold bin/stack-pack, else
# exit 2), else a heimdall checkout next to this repository (../heimdall). With neither, the steps that need a host are SKIPPED and say so;
# HMD_REQUIRE_HOST=1 turns that skip into a failure (set it in CI: a skipped journey must not read as a passing one).
# Real code end to end: the host's own stack-detect and stack-pack and designmatch's own emit-parity run on fixture repos built in a temp dir.
# Nothing is mocked and nothing touches the network. designmatch's scripts need node (absent: that journey is skipped, said).

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../../scripts/lint-skills.sh
. "$ROOT/scripts/lint-skills.sh"

SKILLS="stacks designmatch self-improve system-health mac-deep-clean"
PASSED=0
FAILED=0
SKIPPED=0
HOST=""

if [ -n "${HMD_HOST_DIR:-}" ]; then
  if [ ! -x "$HMD_HOST_DIR/bin/stack-pack" ]; then
    echo "run.sh: HMD_HOST_DIR=$HMD_HOST_DIR is not a heimdall checkout (no executable bin/stack-pack)" >&2
    exit 2
  fi
  HOST="$(cd "$HMD_HOST_DIR" && pwd -P)"
elif [ -x "$ROOT/../heimdall/bin/stack-pack" ]; then
  HOST="$(cd "$ROOT/../heimdall" && pwd -P)"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hmd-skills-uc.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

indent() { printf '%s\n' "$1" | sed 's/^/        /'; }

# scenario "<journey in the user's words>" FUNCTION [ARGS...]: runs FUNCTION in a subshell; 0 passes (what it printed is a note), 77 skips
# (what it printed is the reason), anything else fails (what it printed is why).
scenario() {
  local title="$1" out rc
  shift
  out="$("$@" 2>&1)"; rc=$?
  case "$rc" in
    0)  PASSED=$((PASSED + 1)); printf 'ok    %s\n' "$title"; [ -z "$out" ] || indent "$out" ;;
    77) SKIPPED=$((SKIPPED + 1)); printf 'SKIP  %s\n' "$title"; indent "$out" ;;
    *)  FAILED=$((FAILED + 1)); printf 'FAIL  %s\n' "$title"; indent "$out" ;;
  esac
}

need_host() {
  [ -n "$HOST" ] && return 0
  echo "no heimdall host found: set HMD_HOST_DIR to a heimdall checkout, or put one next to this repository as ../heimdall"
  [ "${HMD_REQUIRE_HOST:-}" = 1 ] && return 1
  return 77
}

need_node() {
  command -v node >/dev/null 2>&1 && return 0
  echo "node is not installed: the designmatch scripts run on it"
  return 77
}

# normalize PATH: collapses . and .. segments of a path that need not exist (a/b/../c -> a/c)
normalize() {
  printf '%s\n' "$1" | awk -F/ '{
    n = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "" || $i == ".") continue
      if ($i == "..") { if (n > 0) n--; continue }
      p[++n] = $i
    }
    s = ""
    for (i = 1; i <= n; i++) s = s (i > 1 ? "/" : "") p[i]
    print s
  }'
}

# pointers ID: the files skills/ID/SKILL.md names, as repo-relative paths, one per line: markdown links with a relative target, own-tree names
# (references/ scripts/ assets/) and inline code that is a concrete path under skills/ or a host root. Placeholders (<id>) and URLs are not files.
pointers() {
  local id="$1" file="$ROOT/skills/$1/SKILL.md" t
  [ -f "$file" ] || return 0
  {
    grep -oE '\]\([^) ]+\)' "$file" | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' | grep -vE '^$|^[A-Za-z][A-Za-z0-9+.-]*:' \
      | while IFS= read -r t; do normalize "skills/$id/$t"; done
    grep -oE '(^|[^A-Za-z0-9._/-])(references|scripts|assets)/[A-Za-z0-9._-]+' "$file" | sed -E 's/^[^A-Za-z0-9]//; s/[.-]+$//' \
      | while IFS= read -r t; do normalize "skills/$id/$t"; done
    awk '{
      line = $0
      while (match(line, /`[^`]+`/)) {
        tok = substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
        sub(/ .*/, "", tok)
        print tok
      }
    }' "$file" | grep -E '^(skills|bin|commands|agents|docs|test|hooks)/[A-Za-z0-9._/-]+$' | sed -E 's/[.]+$//'
  } | sort -u
}

# contract_entries: the host files section 2 of HOST-CONTRACT.md names (rows K-O<n> and X<n>), as host-relative paths, one per line
contract_entries() {
  awk -F'|' '$2 ~ /^ (K-O|X)[0-9]+ $/ {
    c = $3
    sub(/^ *`/, "", c); sub(/`.*/, "", c); sub(/ .*/, "", c)
    if (c !~ /\//) c = "bin/" c
    print c
  }' "$ROOT/HOST-CONTRACT.md"
}

loads_skill() {
  local problems
  problems="$(skill_problems "$ROOT/skills/$1")"
  [ -z "$problems" ] && return 0
  printf '%s\n' "$problems"
  return 1
}

follows_pointers() {
  local id="$1" p here=0 there=0 unchecked=0 missing=""
  if [ ! -f "$ROOT/skills/$id/SKILL.md" ]; then
    echo "skills/$id/SKILL.md is missing"
    return 1
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      skills/*)
        here=$((here + 1))
        [ -e "$ROOT/$p" ] || missing="$missing$p (not in this repository)"$'\n' ;;
      *)
        there=$((there + 1))
        if [ -z "$HOST" ]; then unchecked=$((unchecked + 1)); continue; fi
        case "$p" in
          bin/*) [ -x "$HOST/$p" ] || missing="$missing$p (not an executable in the host)"$'\n' ;;
          *) [ -e "$HOST/$p" ] || missing="$missing$p (not in the host)"$'\n' ;;
        esac ;;
    esac
  done <<< "$(pointers "$id")"
  if [ -n "$missing" ]; then
    printf 'skills/%s/SKILL.md points at files that are not there:\n%s' "$id" "$missing"
    return 1
  fi
  if [ "$unchecked" -gt 0 ]; then
    if [ "${HMD_REQUIRE_HOST:-}" = 1 ]; then
      echo "no heimdall host (HMD_REQUIRE_HOST=1): $unchecked host file(s) it names could not be checked"
      return 1
    fi
    printf '%s file(s) it names here exist; %s host file(s) not checked (no heimdall host found)\n' "$here" "$unchecked"
    return 0
  fi
  if [ "$here" -eq 0 ] && [ "$there" -eq 0 ]; then
    echo "it names no files"
    return 0
  fi
  printf '%s file(s) it names here, %s in the host: all exist\n' "$here" "$there"
}

# pack_for STACK_ID MANIFEST_FILE MANIFEST_TEXT: given a repo whose manifest says STACK_ID, the host's stack-pack hands the agent THIS repo's pack
pack_for() {
  local id="$1" repo="$TMP/$1-repo" detected packs pack="$ROOT/skills/stacks/$1/PACK.md"
  need_host || return $?
  mkdir -p "$repo"
  printf '%s\n' "$3" > "$repo/$2"
  detected="$("$HOST/bin/stack-detect" "$repo")" || { echo "stack-detect failed on the $id repo"; return 1; }
  case "$detected" in
    "{\"stacks\":[\"$id\"],"*) ;;
    *) printf 'stack-detect said %s, wanted the stack %s\n' "$detected" "$id"; return 1 ;;
  esac
  packs="$(CLAUDE_PLUGIN_ROOT="$ROOT" "$HOST/bin/stack-pack" load "$repo")" || { echo "stack-pack load failed on the $id repo"; return 1; }
  if [ "$packs" != "$pack" ]; then
    printf 'stack-pack load printed:\n%s\nwanted exactly: %s\n' "$packs" "$pack"
    return 1
  fi
  if [ ! -s "$pack" ] || ! grep -q "$id" "$pack"; then
    printf '%s is empty, or never names its own stack\n' "$pack"
    return 1
  fi
}

repo_notes_come_after_the_pack() {
  local repo="$TMP/refined-repo" got want
  need_host || return $?
  mkdir -p "$repo/.planning/skills"
  printf '%s\n' '{"name":"web","dependencies":{"next":"14.2.0"}}' > "$repo/package.json"
  printf '# House rules\nUse pnpm, not npm.\n' > "$repo/.planning/skills/house-rules.md"
  got="$(CLAUDE_PLUGIN_ROOT="$ROOT" "$HOST/bin/stack-pack" load "$repo")" || { echo "stack-pack load failed"; return 1; }
  want="$ROOT/skills/stacks/nextjs/PACK.md"$'\n'"$repo/.planning/skills/house-rules.md"
  if [ "$got" != "$want" ]; then
    printf 'stack-pack load printed:\n%s\nwanted, in this order:\n%s\n' "$got" "$want"
    return 1
  fi
}

unknown_stack_gets_no_pack() {
  local repo="$TMP/bare-repo" detected packs
  need_host || return $?
  mkdir -p "$repo"
  detected="$("$HOST/bin/stack-detect" "$repo")" || { echo "stack-detect failed on an empty repo"; return 1; }
  if [ "$detected" != '{"stacks":[],"signals":[]}' ]; then
    printf 'stack-detect said %s, wanted no stack\n' "$detected"
    return 1
  fi
  packs="$(CLAUDE_PLUGIN_ROOT="$ROOT" "$HOST/bin/stack-pack" load "$repo")" || { echo "stack-pack load failed on an empty repo"; return 1; }
  if [ -n "$packs" ]; then
    printf 'stack-pack load printed a pack for a repo of no known stack:\n%s\n' "$packs"
    return 1
  fi
}

# scores_a_screen SSIM PIXEL_DIFF_PCT HARNESS_PASS PARITY_PCT PASS: the harness measured SSIM, the receipt says PARITY_PCT and PASS
scores_a_screen() {
  local dir="$TMP/score-$1"
  need_node || return $?
  mkdir -p "$dir"
  printf '{"ssim":%s,"pixelDiffCount":41000,"totalPixels":2639520,"pixelDiffPct":%s,"width":1080,"height":2444,"canonical":"canonical.png","native":"native.png","timestamp":"2026-11-22T10:00:00.000Z","pass":%s}\n' \
    "$1" "$2" "$3" > "$dir/metrics.json"
  node "$ROOT/skills/designmatch/scripts/emit-parity.js" --metrics "$dir/metrics.json" --out-dir "$dir/out" --screen Home > "$dir/stdout" 2> "$dir/stderr" \
    || { printf 'emit-parity failed: %s\n' "$(cat "$dir/stderr")"; return 1; }
  node -e '
    const fs = require("fs");
    const [dir, pct, pass, harness] = process.argv.slice(1);
    const receipt = JSON.parse(fs.readFileSync(dir + "/out/parity.json", "utf8"));
    const badge = fs.readFileSync(dir + "/out/parity-badge.svg", "utf8");
    const bad = [];
    if (receipt.screen !== "Home") bad.push("screen is " + receipt.screen + ", wanted Home");
    if (receipt.parity_pct !== Number(pct)) bad.push("parity_pct is " + receipt.parity_pct + ", wanted " + pct);
    if (receipt.pass !== (pass === "true")) bad.push("pass is " + receipt.pass + ", wanted " + pass);
    if (receipt.harness_pass !== (harness === "true")) bad.push("harness_pass is " + receipt.harness_pass + ", wanted " + harness);
    if (!badge.includes("design parity") || !badge.includes(pct + "%")) bad.push("the badge does not say design parity " + pct + "%");
    if (badge.includes("#3fb950") !== (pass === "true")) bad.push("the badge is " + (pass === "true" ? "not green" : "green") + " for pass=" + pass);
    if (bad.length) { console.log(bad.join("\n")); process.exit(1); }
  ' "$dir" "$4" "$5" "$3"
}

# writes_no_receipt WHY: the metrics are missing (missing) or hold no score (noscore); emit-parity exits 1 and writes nothing
writes_no_receipt() {
  local dir="$TMP/refuse-$1" err rc
  need_node || return $?
  mkdir -p "$dir"
  [ "$1" = noscore ] && printf '%s\n' '{"pixelDiffPct":3}' > "$dir/metrics.json"
  err="$(node "$ROOT/skills/designmatch/scripts/emit-parity.js" --metrics "$dir/metrics.json" --out-dir "$dir/out" 2>&1)"; rc=$?
  if [ "$rc" -ne 1 ]; then
    printf 'emit-parity exited %s, wanted 1:\n%s\n' "$rc" "$err"
    return 1
  fi
  if [ -e "$dir/out/parity.json" ]; then
    echo "a parity receipt was written anyway"
    return 1
  fi
}

contract_covers_the_skills() {
  local id p entries missing=""
  if [ ! -f "$ROOT/HOST-CONTRACT.md" ]; then
    echo "HOST-CONTRACT.md is missing"
    return 1
  fi
  entries="$(contract_entries)"
  if [ -z "$entries" ]; then
    echo "HOST-CONTRACT.md names no host entry points (rows K-O<n> and X<n> of its section 2)"
    return 1
  fi
  for id in $SKILLS; do
    while IFS= read -r p; do
      case "$p" in
        bin/*|commands/*) printf '%s\n' "$entries" | grep -qxF "$p" || missing="$missing$p (named by skills/$id/SKILL.md)"$'\n' ;;
      esac
    done <<< "$(pointers "$id")"
  done
  if [ -n "$missing" ]; then
    printf 'HOST-CONTRACT.md does not name:\n%s' "$missing"
    return 1
  fi
}

host_has_what_the_contract_names() {
  local p n=0 missing=""
  need_host || return $?
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    [ -e "$HOST/$p" ] || missing="$missing$p"$'\n'
  done <<< "$(contract_entries)"
  if [ "$n" -eq 0 ]; then
    echo "HOST-CONTRACT.md names no host entry points (rows K-O<n> and X<n> of its section 2)"
    return 1
  fi
  if [ -n "$missing" ]; then
    printf 'the host at %s has no:\n%s' "$HOST" "$missing"
    return 1
  fi
  printf '%s entry points, all present in %s\n' "$n" "$HOST"
}

for id in $SKILLS; do
  scenario "an agent loads the $id skill" loads_skill "$id"
done
for id in $SKILLS; do
  scenario "an agent follows the pointers in the $id skill" follows_pointers "$id"
done
scenario "a FastAPI repo gets the fastapi stack pack" pack_for fastapi requirements.txt $'fastapi==0.110.0\nuvicorn[standard]'
scenario "a Next.js repo gets the nextjs stack pack" pack_for nextjs package.json '{"name":"web","dependencies":{"next":"14.2.0","react":"18.3.0"}}'
scenario "a React Native repo gets the react-native stack pack" pack_for react-native package.json '{"name":"app","dependencies":{"react-native":"0.74.0","expo":"~51.0.0"}}'
scenario "a Spring Boot repo gets the spring-boot stack pack" pack_for spring-boot build.gradle "plugins { id 'org.springframework.boot' version '3.2.0' }"
scenario "a repo's own .planning/skills notes come after the base pack" repo_notes_come_after_the_pack
scenario "a repo of no known stack gets no pack" unknown_stack_gets_no_pack
scenario "a screen that clears SSIM 0.95 gets a passing parity receipt and a green badge" scores_a_screen 0.973 1.55 true 97 true
scenario "a screen below the bar gets a failing receipt and no green badge" scores_a_screen 0.82 12.4 false 82 false
scenario "no metrics, no parity receipt" writes_no_receipt missing
scenario "metrics without a score, no parity receipt" writes_no_receipt noscore
scenario "HOST-CONTRACT.md names every host command the skills tell an agent to run" contract_covers_the_skills
scenario "the host has every entry point HOST-CONTRACT.md names" host_has_what_the_contract_names

printf 'use-cases: %s passed, %s failed, %s skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
[ "$SKIPPED" -eq 0 ] || echo "use-cases: a skipped journey ran nothing; the SKIP lines say what it needed"
[ "$FAILED" -eq 0 ]
