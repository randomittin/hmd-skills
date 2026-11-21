# hmd-skills

The skills that ship with [Heimdall](https://github.com/randomittin/heimdall) (`hmd`), as a repository of their own: five agent skills, one directory each under `skills/`. Every file keeps the path it has in heimdall, so heimdall's own commands (`bin/stack-pack`, `bin/designmatch`) find them unchanged, and heimdall still ships a copy at the same paths.

| Skill | What it gives an agent | What it needs from heimdall |
|---|---|---|
| `stacks` | Knowledge packs (conventions, exact lint/test/build commands, failure patterns) for Next.js, React Native, Spring Boot and FastAPI repos, and the detection of which stack a repo uses | `bin/stack-detect`, `bin/stack-pack` |
| `designmatch` | The loop that ports a Claude Design canonical to a React Native screen and scores it against the device (SSIM >= 0.95 or pixel diff <= 5%) | `bin/designmatch` and its helpers, `/hmd:designmatch` |
| `self-improve` | The loop that tunes the maintainer's routing from measured results: collect, hypothesise, experiment, evaluate, keep or roll back | `bin/heimdall-self-improve`, `bin/heimdall-metric`, `/dream` |
| `system-health` | Read-only advice on whether a machine needs a disk or memory cleanup, and whether heimdall itself is the hog | `bin/heimdall-cleanup`, `bin/heimdall-sysmon` |
| `mac-deep-clean` | The confirm-gated macOS disk and memory cleanup `system-health` hands off to | `bin/heimdall-cleanup --deep`, `bin/heimdall-sysmon` |

## What you can do with it

- Load any of the five skills: `skills/<id>/SKILL.md` opens with frontmatter whose `name` is the directory name and whose `description` says when to reach for it.
- Follow a skill: every file its `SKILL.md` names exists, here for its own references, scripts and assets, in heimdall for the commands it tells you to run.
- Get the stack pack for a repo: heimdall's `bin/stack-pack load <repo>` prints this repository's `skills/stacks/<id>/PACK.md` for a FastAPI, Next.js, React Native or Spring Boot repo, then the repo's own `.planning/skills/*.md` notes; a repo of no known stack gets none.
- Score a screen: `node skills/designmatch/scripts/emit-parity.js --metrics metrics.json --out-dir out` turns the harness's measurements into `parity.json` and a badge, green only at SSIM >= 0.95, and writes nothing when the metrics are missing or hold no score.

## Using it

With heimdall there is nothing to install: the skills are invoked as `hmd:stacks`, `hmd:designmatch`, `hmd:self-improve`, `hmd:system-health` and `hmd:mac-deep-clean`.

Without it, a skill installer can read this repository as it stands: each `skills/<id>/SKILL.md` has its `references/`, `scripts/` and `assets/` beside it, and `scripts/lint-skills.sh` holds that layout in place. The runnable steps of a skill call heimdall commands, and `HOST-CONTRACT.md` names every one, with the line of the skill that relies on it and the line of heimdall that implements it. A skill used on a machine without those commands can still be read, but its commands will not run, and the few links that point into heimdall (such as `self-improve`'s link to `docs/analysis/autoresearch-distilled.md`) resolve only inside a heimdall checkout.

## Layout

```
skills/<id>/SKILL.md          the skill; references/, scripts/, assets/ and PACK.md files sit beside it
HOST-CONTRACT.md              the heimdall commands and files the skills rely on, and the heimdall code that reads these paths
scripts/lint-skills.sh        static checks
tests/use_cases/run.sh        the journeys above, run for real
.heimdall/repo-checks.json    the two checks heimdall's push gate grades this repository on
```

## Checks

```bash
bash scripts/lint-skills.sh      # frontmatter, SKILL.md size cap, bash -n, node --check, shellcheck, no runtime state in the tree
bash tests/use_cases/run.sh      # the journeys, against a heimdall checkout
```

The journeys that need heimdall look for it in `HMD_HOST_DIR`, then in `../heimdall`. Without one they are skipped and say so; `HMD_REQUIRE_HOST=1` makes that a failure, which is what CI wants. designmatch's journeys need `node`.

The gate follows heimdall's rule for managed repositories: lint plus use-case journeys, no full-sweep runner. From a heimdall checkout, `bin/heimdall-repo-checks run --repo <this directory>` runs both and records the receipt a push is graded on.

## History

The history of each skill was carried over from heimdall with `git filter-repo`, paths unchanged, so `git log -- skills/<id>` follows a skill back through heimdall. Runtime caches that a checkpoint once committed under `skills/designmatch/.heimdall/` were dropped from every commit.
