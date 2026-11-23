# hmd-skills

hmd-skills is a collection of five agent skills for hmd (Heimdall): stack packs, design parity, self-improvement, system health and macOS cleanup.

Works with, today: Claude Code and Cursor.

hmd is the command-line tool of [runhmd](https://runheimdall.dev), a verification layer for AI coding agents; Heimdall, at [randomittin/heimdall](https://github.com/randomittin/heimdall), is the engine underneath. These are the skills that ship with it. They are developed here, in a repository of their own, and heimdall ships a copy at the same paths, pinned to a release tag of this repository. A skill is a folder under `skills/` with a `SKILL.md` (its name, a description that says when to reach for it, and its steps) beside the `references/`, `scripts/` and `assets/` it needs.

## The skills

### stacks: knowledge packs for the stack a repo uses

Loads a stack's conventions, directory layout, exact lint, test and build commands, runnable acceptance-criteria templates and common failure patterns onto the agent you already use, instead of adding an agent per stack. Packs exist for **Next.js, React Native, Spring Boot and FastAPI** (`skills/stacks/<id>/PACK.md`). Detection also recognizes React, Vue, Svelte, Node, JVM, Django, Flask, Python, Go and Rust; those have no pack yet. A repo's own `.planning/skills/*.md` notes are read after the base pack and win where they disagree.

Reach for it when you start in an unfamiliar repo, or when an acceptance criterion needs a stack's exact command instead of a guess. Needs hmd's `bin/stack-detect` and `bin/stack-pack`. Read: [`SKILL.md`](skills/stacks/SKILL.md), [how packs are detected and layered](skills/stacks/README.md).

### designmatch: match a React Native screen to its design

Renders the screen's HTML design canonical (the design exported as HTML and JSX) with Playwright at a locked 1080×2444 viewport, captures the running screen from a device (`adb`, `xcrun`) or renders a web build, scores the pair with pixelmatch and SSIM, and writes a side-by-side composite to review. A screen passes at **SSIM ≥ 0.95 or a pixel difference ≤ 5%**. The method is port-first: translate the canonical's own markup, never re-derive it by eyeballing pixels; [`references/anti-patterns.md`](skills/designmatch/references/anti-patterns.md) lists the mistakes the loop is built to catch. `scripts/emit-parity.js` turns the harness's numbers into `parity.json` and an SVG badge that is green only at SSIM ≥ 0.95.

Reach for it when a screen has drifted from its design, before a visual parity audit, or for a per-screen loop on a real device. Not for logic, state shape or navigation. Needs Node.js with Playwright, pixelmatch, ssim.js and sharp, a device or emulator for native capture, and hmd's `bin/designmatch` for the `designmatch` command. Read: [`SKILL.md`](skills/designmatch/SKILL.md).

### self-improve: tune routing from measured results

Applies the keep-only-measured-wins rule of [karpathy/autoresearch](https://github.com/karpathy/autoresearch) to hmd's own routing (which model tier takes which kind of task). The loop: collect task outcomes, form testable hypotheses, run one bounded experiment, evaluate it against the baseline, then keep the change or roll it back. A change is kept only when it beats the baseline by a minimum pass-rate gain on a minimum number of samples (the skill's example uses 20 samples and a gain of 0.15); otherwise the override is rolled back. One experiment per run. Today a kept override is recorded as a measured finding and applying it is a manual step; the skill says so itself.

Reach for it between maintainer fix batches, or when asked to improve or tune hmd's routing. Needs hmd's `bin/heimdall-self-improve` and `bin/heimdall-metric`, which produces the task records it reads; with no records it reports nothing to suggest. Read: [`SKILL.md`](skills/self-improve/SKILL.md).

### system-health: advice on whether a Mac needs a cleanup

Read-only advice on whether a Mac needs a disk or memory cleanup, and whether hmd itself is the cause. It grades disk, memory and process pressure, counts hmd's own orphaned background Python processes, and suggests the fix. It deletes and kills nothing on its own: the one mutating action, `heimdall-sysmon --reap-hmd-orphans`, runs only when you ask and matches only processes that are both orphaned and carry hmd's own signature. A full disk is handed off to mac-deep-clean.

Reach for it when a machine is slow or swapping, when disk or "System Data" is full, or at the start of a long session. Needs hmd's `bin/heimdall-cleanup` and `bin/heimdall-sysmon`. Read: [`SKILL.md`](skills/system-health/SKILL.md).

### mac-deep-clean: confirm-gated macOS disk and memory cleanup

Investigates read-only first, measures before and after, and presents a tiered map of what is reclaimable: zero-risk caches, re-downloadable developer tooling (old SDK versions, `node_modules`), state-wiping items that need a per-item yes, and steps that need `sudo` or a reboot, which it hands to you as exact commands instead of running them. It covers developer-tool caches, dead repos and git worktrees, Android SDK and Xcode simulator bloat, System Data, and runaway-process memory leaks. It deletes only what regenerates or what you approve.

Reach for it when disk is full, System Data is huge or the machine is swapping. system-health and `heimdall-cleanup --deep` notice the need and hand off to it. Its own steps are plain shell; only the cleanup of hmd's own leftovers calls hmd's `bin/heimdall-gc`, `bin/heimdall-reap-idle` and `bin/heimdall-sysmon`. Read: [`SKILL.md`](skills/mac-deep-clean/SKILL.md).

## Install

```bash
hmd skills install stacks    # or: designmatch, self-improve, system-health, mac-deep-clean
```

`hmd skills install <id>` is hmd's consented install path, and the five ids above are the skills in this repository. By default hmd asks before it installs anything; add `--yes` once you have agreed (with no terminal and no `--yes` it exits with status 3 and asks to be run again with `--yes`). These skills ship inside hmd, so nothing is downloaded: on a lean hmd install, where they are left out until asked for, the command puts the skill's files back from the copy hmd already holds; on a full install they are already on disk, and it says so. A skill is listed from the next session and invoked by name: `hmd:stacks`, `hmd:designmatch`, `hmd:self-improve`, `hmd:system-health`, `hmd:mac-deep-clean`.

`hmd skills list` shows every skill hmd knows about, these five included, and `hmd skills why <id>` says why one is on the machine. To get hmd itself, follow the [install section of the heimdall README](https://github.com/randomittin/heimdall#install): the installer is pinned to a release tag and checksum-verified.

### Without hmd

Each skill is a plain folder, so a skill installer or a copy works: clone this repository and copy `skills/<id>/` whole (`SKILL.md` and its `references/`, `scripts/` and `assets/`) into your agent's skills directory. A skill used without hmd can be read, but the commands it tells an agent to run belong to hmd and will not run; [`HOST-CONTRACT.md`](HOST-CONTRACT.md) names every one, with the line of the skill that relies on it and the line of heimdall that implements it. The few links inside a skill that point into heimdall (such as `self-improve`'s link to `docs/analysis/autoresearch-distilled.md`) resolve only inside a heimdall checkout.

## Use a skill

- **Load one.** Open `skills/<id>/SKILL.md`: its frontmatter `name` is the directory name and its `description` says when to reach for it.
- **Get the stack pack for a repo.** heimdall's `bin/stack-pack load <repo>` prints the path of the matching `skills/stacks/<id>/PACK.md` for a FastAPI, Next.js, React Native or Spring Boot repo, then the repo's own `.planning/skills/*.md` notes. A repo that has neither gets nothing.
- **Start a screen.** `designmatch init "<canonical-url>" --app-dir . --port-all` copies the visual-QA stub into the app, downloads the canonical bundle with Playwright, ports every screen it finds and prints the wiring snippet.
- **Score a screen.** `node skills/designmatch/scripts/emit-parity.js --metrics metrics.json --out-dir out` turns the harness's measurements into `parity.json` and a badge, green only at SSIM ≥ 0.95, and writes nothing when the metrics are missing or hold no score.

## FAQ

### What is hmd-skills?

hmd-skills is the repository where the skills that ship with hmd (Heimdall) are developed: stacks, designmatch, self-improve, system-health and mac-deep-clean. Each is a folder with a `SKILL.md` that tells an agent when to use it and what to run. heimdall pins a release tag of this repository and ships a copy of the same files at the same paths.

### How do I install an hmd skill?

Run `hmd skills install <id>` with `stacks`, `designmatch`, `self-improve`, `system-health` or `mac-deep-clean`. hmd asks for your consent, then makes sure the skill's files are on disk: it puts them back from the copy it already holds on a lean install, and they are already there on a full one. Nothing is downloaded, and the skill is listed from the next session.

### Can I use these skills without hmd?

You can read and load them: each `skills/<id>/` folder is self-contained Markdown plus its own scripts. The commands a skill tells an agent to run belong to hmd and do not run without it; [`HOST-CONTRACT.md`](HOST-CONTRACT.md) lists each one. designmatch's scripts are plain Node and shell and run on their own once their npm packages are installed.

### Which stacks does the stacks skill cover?

It has packs for Next.js, React Native, Spring Boot and FastAPI. Detection also recognizes React, Vue, Svelte, Node, JVM, Django, Flask, Python, Go and Rust, but those have no pack yet, so a repo that detects as one of them gets no base pack. A repo's own `.planning/skills/*.md` notes are always loaded after the base pack.

### Will system-health or mac-deep-clean delete my files?

system-health is a read-only advisor: it deletes and kills nothing, except that you can ask it to reap hmd's own orphaned processes with `heimdall-sysmon --reap-hmd-orphans`. mac-deep-clean investigates read-only first and shows a tiered map; once you approve it, it clears only regenerable caches and re-downloadable tooling, asks per item before anything that wipes state, and hands you the exact `sudo` or reboot commands instead of running them.

### How does designmatch decide that a screen matches its design?

It renders the design canonical at a locked 1080×2444 viewport, captures the screen (a device screenshot or a rendered web build), and scores the pair two ways: pixelmatch for perceptual pixel difference and SSIM for structural similarity. A screen passes at SSIM ≥ 0.95 or a pixel difference ≤ 5%. [`emit-parity.js`](skills/designmatch/scripts/emit-parity.js) records the numbers in `parity.json` and never invents a score when metrics are missing.

## Layout

```
skills/<id>/SKILL.md          the skill; references/, scripts/, assets/ and PACK.md files sit beside it
HOST-CONTRACT.md              the heimdall commands and files the skills rely on, and the heimdall code that reads these paths
CITATION.cff                  how to cite this repository
llms.txt                      a structured map of this repository for language models (llmstxt.org format)
scripts/lint-skills.sh        static checks
tests/use_cases/run.sh        the use-case journeys, run for real
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

## About

hmd-skills is maintained by RJ ([randomittin](https://github.com/randomittin)) as part of [hmd](https://runheimdall.dev). Cite it with [`CITATION.cff`](CITATION.cff); a structured summary for language models is in [`llms.txt`](llms.txt).

## License

MIT. See [LICENSE](LICENSE).
