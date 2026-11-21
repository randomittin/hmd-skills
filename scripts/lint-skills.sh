#!/usr/bin/env bash
# lint-skills.sh -- static checks over the hmd-skills tree.
#
#   bash scripts/lint-skills.sh        exit 0 clean, 1 findings (one "lint: ..." line each), 2 usage
#
# What it checks:
#   1. every skills/<id>/ has a SKILL.md that opens with a YAML frontmatter block holding `name` (equal to <id>: lowercase letters, digits and
#      single hyphens, at most 64 characters) and a non-empty `description` (at most 1024 characters): the layout skill installers read
#   2. a SKILL.md is at most SKILL_MAX_BYTES bytes: it is read whole when the skill fires, so long material belongs in references/
#   3. bash -n over every *.sh and node --check over every *.js (node absent: said, not silently skipped)
#   4. shellcheck, warnings and errors, over every *.sh (shellcheck absent: said)
#   5. no runtime state or build output in the tree: .heimdall/ below the root (a wip checkpoint once committed skills/designmatch/.heimdall),
#      .designmatch/, node_modules/. The root .heimdall/ holds only repo-checks.json and the ignored receipts/
# Not checked: skills/designmatch/assets/visual-qa.ts (TypeScript: it is copied into an app that has its own compiler).
# "Every file" is what git would commit: tracked files plus untracked ones that are not ignored (outside a git work tree, everything but .git).
# Sourced instead of run, it only defines skill_field and skill_problems, which tests/use_cases/run.sh reuses.

set -u

LINT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL_MAX_BYTES=24000

# skill_field FILE KEY: the frontmatter value of KEY (a folded or literal block is joined with spaces, outer quotes are dropped).
# Exit 3: no frontmatter block, 4: the block is never closed, 5: KEY is absent.
skill_field() {
  awk -v key="$2" '
    NR == 1 { if ($0 !~ /^---[ \t]*$/) { bad = 3; exit } next }
    /^---[ \t]*$/ { closed = 1; exit }
    {
      if (index($0, key ":") == 1) {
        val = substr($0, length(key) + 2)
        sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
        if (val ~ /^[>|][+-]?$/) val = ""
        found = 1; collecting = 1; out = val
        next
      }
      if (collecting) {
        if ($0 ~ /^[ \t]+[^ \t]/) {
          line = $0
          sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
          out = (out == "" ? line : out " " line)
          next
        }
        if ($0 ~ /^[ \t]*$/) next
        collecting = 0
      }
    }
    END {
      if (bad) exit bad
      if (!closed) exit 4
      if (!found) exit 5
      sq = sprintf("%c", 39)
      gsub("^[\"" sq "]|[\"" sq "]$", "", out)
      print out
    }' "$1"
}

# skill_problems SKILL_DIR: one finding per line, nothing when the skill is sound.
skill_problems() {
  local dir="$1" id file bytes name desc nstat dstat
  id="$(basename "$dir")"
  file="$dir/SKILL.md"
  if [ ! -f "$file" ]; then
    printf 'skills/%s: no SKILL.md\n' "$id"
    return 0
  fi
  bytes="$(wc -c < "$file" | tr -d ' ')"
  if [ "$bytes" -gt "$SKILL_MAX_BYTES" ]; then
    printf 'skills/%s/SKILL.md: %s bytes, over the %s byte cap (long material belongs in references/)\n' "$id" "$bytes" "$SKILL_MAX_BYTES"
  fi
  name="$(skill_field "$file" name)"; nstat=$?
  desc="$(skill_field "$file" description)"; dstat=$?
  case "$nstat" in
    3) printf 'skills/%s/SKILL.md: does not open with a --- frontmatter block\n' "$id"; return 0 ;;
    4) printf 'skills/%s/SKILL.md: the --- frontmatter block is never closed\n' "$id"; return 0 ;;
  esac
  if [ "$nstat" -ne 0 ] || [ -z "$name" ]; then
    printf 'skills/%s/SKILL.md: frontmatter has no name\n' "$id"
  else
    [ "$name" = "$id" ] || printf 'skills/%s/SKILL.md: name "%s" is not the directory name "%s"\n' "$id" "$name" "$id"
    if [ "${#name}" -gt 64 ] || ! printf '%s\n' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
      printf 'skills/%s/SKILL.md: name "%s" must be lowercase letters, digits and single hyphens, at most 64 characters\n' "$id" "$name"
    fi
  fi
  if [ "$dstat" -ne 0 ] || [ -z "$desc" ]; then
    printf 'skills/%s/SKILL.md: frontmatter has no description\n' "$id"
  elif [ "${#desc}" -gt 1024 ]; then
    printf 'skills/%s/SKILL.md: description is %s characters, over the 1024 limit\n' "$id" "${#desc}"
  fi
  return 0
}

list_files() {
  if git -C "$LINT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$LINT_ROOT" ls-files --cached --others --exclude-standard
  else
    (cd "$LINT_ROOT" && find . -type f -not -path './.git/*' | sed 's|^\./||')
  fi
}

lint_main() {
  local files dir f out line sh_list js_list stray findings=0 skills=0 shells=0 jsfiles=0

  if [ "$#" -gt 0 ]; then
    echo "usage: bash scripts/lint-skills.sh   (no arguments)" >&2
    return 2
  fi
  files="$(list_files)"

  for dir in "$LINT_ROOT"/skills/*/; do
    [ -d "$dir" ] || continue
    skills=$((skills + 1))
    out="$(skill_problems "${dir%/}")"
    [ -n "$out" ] || continue
    while IFS= read -r line; do
      findings=$((findings + 1))
      printf 'lint: %s\n' "$line"
    done <<< "$out"
  done
  if [ "$skills" -eq 0 ]; then
    findings=$((findings + 1))
    printf 'lint: skills/: no skill directories found, so there is nothing to ship\n'
  fi

  sh_list="$(printf '%s\n' "$files" | grep -E '\.sh$')"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$LINT_ROOT/$f" ] || continue
    shells=$((shells + 1))
    if ! out="$(bash -n "$LINT_ROOT/$f" 2>&1)"; then
      findings=$((findings + 1))
      printf 'lint: %s: bash -n: %s\n' "$f" "$(printf '%s\n' "$out" | head -n 1)"
    fi
  done <<< "$sh_list"

  js_list="$(printf '%s\n' "$files" | grep -E '\.(js|cjs|mjs)$' | grep -vE '(^|/)node_modules/')"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$LINT_ROOT/$f" ] || continue
    jsfiles=$((jsfiles + 1))
    command -v node >/dev/null 2>&1 || continue
    if ! out="$(node --check "$LINT_ROOT/$f" 2>&1)"; then
      findings=$((findings + 1))
      printf 'lint: %s: node --check: %s\n' "$f" "$(printf '%s\n' "$out" | head -n 1)"
    fi
  done <<< "$js_list"
  if [ "$jsfiles" -gt 0 ] && ! command -v node >/dev/null 2>&1; then
    printf 'lint: note: node is not installed, so %s javascript file(s) were not syntax-checked\n' "$jsfiles"
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$LINT_ROOT/$f" ] || continue
      if ! out="$(cd "$LINT_ROOT" && shellcheck -S warning -x "$f" 2>&1)"; then
        findings=$((findings + 1))
        printf 'lint: %s: shellcheck\n' "$f"
        printf '%s\n' "$out" | sed 's/^/lint:   /'
      fi
    done <<< "$sh_list"
  else
    printf 'lint: note: shellcheck is not installed, so shell scripts were only checked with bash -n\n'
  fi

  stray="$(printf '%s\n' "$files" | grep -E '(^|/)(node_modules|\.designmatch)/|^.+/\.heimdall/|^\.heimdall/' | grep -vE '^\.heimdall/(repo-checks\.json$|receipts/)')"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    findings=$((findings + 1))
    printf 'lint: %s: runtime state or build output does not belong in the tree\n' "$f"
  done <<< "$stray"

  if [ "$findings" -gt 0 ]; then
    printf 'lint: FAILED, %s finding(s)\n' "$findings"
    return 1
  fi
  printf 'lint: clean (%s skills, %s shell scripts, %s javascript files)\n' "$skills" "$shells" "$jsfiles"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  lint_main "$@"
  exit $?
fi
