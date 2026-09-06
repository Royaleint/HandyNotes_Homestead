# Release

RELEASE_CONFIG: .claude/commands/release.config.json

Package and publish a new HandyNotes_Homestead release. This file lives in the
public repo root, same as Foundry's. The nested `HNH_Dev/` repo is where
`gate2.source_path` reads Gate 2 evidence from (`HNH_Completed.md`).

Project-specific notes, worth knowing before running this:

- **No version-bump step.** `version_bump_files` is empty on purpose: only
  `HandyNotes_Homestead.toc` is tracked and it uses `@project-version@` — the
  packager substitutes the real version from the pushed git tag at build time.
- **Wago is deliberately not a publication target** (Rawb, 2026-08-12). The
  workflow's Wago step no-ops with no `X-Wago-ID`/`WAGO_API_TOKEN`; to adopt
  Wago later, add both plus `"Wago"` to `publication_targets`.
- **Data.lua is generated** from Homestead vendor data
  (`Home_Dev/scripts/generate-handynotes-export.mjs --write --source-version
  "<id>"` run from the Homestead repo). If a release should carry fresh vendor
  data, regenerate AFTER the source commit lands in Homestead so the stamp
  names a real commit — never hand-edit Data.lua. After regenerating, run
  `lua5.1 Home_Dev/scripts/verify-handynotes-export.lua` (native-Lua fidelity
  check against the Homestead source, independent of the exporter's own
  parsing) and confirm `RESULT: EXACT MATCH` before tagging.
- **Pre-release history carries no HNH- ticket IDs** (commits up to the first
  release predate the convention). First-release runs use the guard's
  `--allow-sha` for those, each named explicitly — from HNH-002 onward,
  commits carry ticket IDs and no blanket exceptions are acceptable.

The synced core procedure below is the studio standard.

---

<!-- SYNC: release-skill-core from .claude/skills/wow-release-execution/SKILL.md -->
## Config

The invoking project's `release.md` names `RELEASE_CONFIG` — the path to its
`release.config.json` — outside this synced block. Step 0 below validates it.
Every guard invocation in this procedure passes it through:

```
node ../BawrLabs/scripts/release-guard.mjs <subcommand> --config <RELEASE_CONFIG>
```

That literal command template carries no shell conditionals and no variable
expansion, so it is valid verbatim in both bash and PowerShell — run it
exactly as written, substituting only `<subcommand>` and `<RELEASE_CONFIG>`
and appending the flags that subcommand takes; the one flag value that is
itself an expansion, step 9's `$(git rev-parse HEAD)`, is called out there.
`shipping-set`, `map-tickets`, `check-gate2`, and `suggest-version` each
build a shipping set, so each also requires `--since <last-tag>`; omitting
it is a usage error, not a verdict. All four optionally take
`--allow-sha <sha>`, and the last three also take `--allow-ticket <id>`.
Both exception flags are repeatable, and each occurrence names exactly one
commit or one ticket, never a pattern.

**On any guard non-zero exit, read the RESULT line before deciding what it
means** — non-zero is not uniformly "hard stop." `check-gate2` exits non-zero
for two different things, distinguished only by that line's text, never by
the exit code itself:
- `RESULT: STOP — ...` is a hard failure. Report the reason to Rawb verbatim
  and stop the procedure — do not proceed past the failing step, do not retry
  with different flags, and do not hand-verify the condition yourself as a
  substitute for the guard passing. A stop is the guard doing its job.
- `RESULT: MANUAL-CONFIRM REQUIRED — ...` is the designed result for any
  project whose config sets `gate2.mode: "manual-confirm"` — see step 2. It
  means *pause and ask Rawb directly*, not abort. Do not treat this exit code
  as a stop.

Exit 2 is a third branch and never a verdict: it is a hard error, raised by a
bad or missing `--config`, by a git failure, or by a usage error such as a
missing `--since`. It prints `error: <message>` on stderr and emits no
`RESULT:` line at all. Absence of a `RESULT:` line means the check never ran,
so do not read it as a pass and do not retry with different flags: fix the
invocation or the config.

Every other subcommand's exit 1 is a plain stop; `check-gate2` is the one
exception, and only for `manual-confirm` projects. Exit 2 is the hard error
described above, and it means the same thing for every subcommand.

## Procedure

0. **Validate config.** Confirm `RELEASE_CONFIG` is set in the invoking
   `release.md` and that the file it points to parses as JSON. If either
   check fails, stop before running any guard subcommand — nothing below
   runs without a working config.

1. **Branch and cleanliness.**
   Run `check-branch` — current branch must exactly equal the project's
   `release_branch`. Run `check-clean` — every root in the config's
   `clean_roots` (this may include a nested Dev repo, not just the public
   repo) must be clean; the guard names the specific dirty root if one
   exists. Either check failing stops the release before any other step.

2. **Shipping set, ticket mapping, Gate 2, version proposal.**
   - Run `shipping-set --since <last-tag>` to enumerate the commits going
     out. A commit with no resolvable ticket ID stops the run. This is where
     the run's named exceptions are established: `--allow-sha <full-sha>`
     names a single commit that has no resolvable ticket ID, and
     `--allow-ticket <id>` (taken by the three subcommands below, not by
     `shipping-set`) names a single ticket with no entry in the configured
     source, or one whose live entry sits outside the configured gate
     section. Every exception stays visible in the evidence output, tagged
     `[no ticket, allowed]`, `[no entry, allowed]`, or
     `[live entry, allowed — ships nothing, section "…"]`, and contributes
     no version category. Write down each flag you pass: every later step
     that rebuilds the shipping set needs the identical set.
   - Run `map-tickets --since <last-tag>` to resolve each ticket ID against
     the project's configured tracker/completed source. A duplicate entry
     with conflicting type or status stops the run as ambiguous.
   - Run `check-gate2 --since <last-tag>` — **before any file is touched.**
     For automated projects this is authoritative: a missing or non-matching
     marker stops the run. **For a project whose config sets
     `gate2.mode: "manual-confirm"`**, the guard verifies nothing: it
     reports `manual-confirm` and defers. In that case, stop here and ask
     Rawb directly, in this conversation, listing the exact ticket IDs from
     the shipping set, and wait for his real response before continuing.
     Record his confirmation verbatim (what he said, when) in the eventual
     report — label it "Rawb's interactive confirmation," never as a Gate 2
     pass the tooling verified.
   - Run `suggest-version --since <last-tag>` and present the full evidence
     table (shipping commits, mapped tickets, proposed category and version)
     to Rawb for confirmation before proceeding. A first release with no
     previous tag, an unresolved commit/ticket, or a ticket `Type:` matching
     none of the project's `version_categories` stops the run — none of these
     fall back to a silent default.

3. **Lint.** Run the project's configured `luacheck` command. Errors stop
   the release. Warnings proceed only if they're within the project's
   established baseline.

4. **Version bump.** Update every file in `version_bump_files` plus the TOC
   `## Interface:` line if the game version changed. When
   `version_bump_files` is empty there is nothing to bump, and the step is
   skipped.

5. **Changelogs.** Write the internal changelog entry first, then derive the
   public entry from it per the project's `changelog` config. For a project
   with `changelog.confidentiality_mode: "restricted"`, build the public
   entry from the fixed template and closed outcome vocabulary only — a
   freeform override requires an explicit flag and must be flagged for a human
   confidentiality read during the diff review in step 7, never applied
   silently. Route public-facing text through Everett.

6. **`.pkgmeta` sanity.** Run the guard subcommand that performs this check;
   its name is literally the string `.pkgmeta`:
   `node ../BawrLabs/scripts/release-guard.mjs .pkgmeta --config <RELEASE_CONFIG>`.
   Local, deterministic checks only: the file exists and parses, and
   `manual-changelog` resolves to a real file. This is not a re-check of
   ignore-rules-vs-shipped-files — that's covered by CI's
   TOC-vs-zip job, reported in step 11.

7. **Diff review.** Show the full diff (version bump, changelog entries,
   any other touched files) and get Rawb's explicit confirmation before
   committing. Do not commit on an assumed approval.

8. **Commit.** Commit the release. The message is plain prose that says what
   changed and why, readable months later, and it carries no trailer of any
   kind.

9. **Tag.** Create an annotated tag (`git tag -a vX.Y.Z -m "..."`). Then
   re-run `shipping-set` and `check-gate2` a second time — defense-in-depth
   against tracker state changing mid-run — and run `check-tag <version>`,
   which requires `git rev-parse vX.Y.Z^{commit}` to exactly equal
   `git rev-parse HEAD`.

   Both re-runs repeat step 2's invocation exactly: the same
   `--since <last-tag>` and every `--allow-sha` and `--allow-ticket` you
   passed there, plus one more `--allow-sha` naming the release commit you
   just made, `$(git rev-parse HEAD)`, which expands in both bash and
   PowerShell. Both flags are needed because the guard rebuilds the whole
   range on every run: a step-2 exception you leave off stops the run on
   that commit again, and the release commit carries no ticket ID of its
   own. `shipping-set` is the evidence: expect the same commit lines as
   step 2 plus exactly one new `[no ticket, allowed]` line, the release
   commit. Any other difference is a stop. `check-gate2` prints only the
   mode and the per-ticket states, never the commit list, so it cannot
   stand in for that comparison.

   In `automated` mode, both `check-gate2` and `check-tag` must pass before
   either push in step 10. In `manual-confirm` mode `check-gate2` reports
   `MANUAL-CONFIRM REQUIRED` again by design and can never pass, so what must
   hold before the push is that `check-tag` passes and that the shipping set
   is unchanged since Rawb's step-2 confirmation apart from the allowed
   release commit.

10. **Push.** Push the commit, then push the specific tag only:
    `git push origin vX.Y.Z`. Never `git push --tags`.

11. **Publication verification.** `release-guard.mjs publication-targets`
    only classifies which targets are even in scope for this project
    (`configured` vs `not applicable`) — it does **not** perform the live
    GitHub checks itself, and its exit 0 means "the config split is sane,"
    not "publication is verified." Do not stop at that command and report
    success; the live verification is this step's own work, using `gh`:
    1. Locate the run: `gh run list --workflow=release.yml
       --branch=vX.Y.Z` (or equivalent lookup by the pushed tag ref), then
       confirm it's for **this tag's exact commit SHA** — never assume "most
       recent run" if more than one exists. Wait for it to reach a terminal
       state (`gh run watch <id>`, with a sane overall timeout — on timeout,
       report "could not confirm, check manually," never treat timeout as
       success). Report state 1 as `passed` only if `conclusion == success`
       (this includes the TOC-vs-zip check, which runs as a job step) —
       otherwise `failed`, with the failing step named if `gh run view
       --log-failed` can show it.
    2. Report state 2, the CF duplicate check, as `passed` if that job step
       succeeded, or `unarmed/skipped` if it warned-and-skipped because
       `CF_CORE_API_KEY` isn't set — an unarmed check is reported as
       unarmed, never folded into "passed."
    3. For each entry in `config.publication_targets` marked `configured` by
       the guard's classification, report `upload succeeded` (from the same
       CI run) or `not applicable` for a target the project doesn't publish
       to (e.g. Wago for Sift). Then run `gh release view vX.Y.Z` to confirm
       the GitHub Release object exists.
    Report all three states separately in the final report (step 13) —
    never collapse them into one "covered," and never let a bare guard
    PROCEED stand in for having actually run these `gh` checks.

12. **Release notes and community posts.** Write or confirm the GitHub
    release notes; draft any community posts. Route all of this through
    Everett before anything is posted — this skill never posts on its own.

13. **Report.** Summarize the release for Rawb, including any "not
    applicable" targets, any "unarmed" checks, and, for a manual-confirm
    project, the recorded human confirmation from step 2. Never omit these
    silently; an incomplete or skipped check is part of the record, not noise.
<!-- END SYNC: release-skill-core -->
