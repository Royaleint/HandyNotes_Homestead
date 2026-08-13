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
  names a real commit — never hand-edit Data.lua.
- **Pre-release history carries no HNH- ticket IDs** (commits up to the first
  release predate the convention). First-release runs use the guard's
  `--allow-sha` for those, each named explicitly — from HNH-002 onward,
  commits carry ticket IDs and no blanket exceptions are acceptable.

The synced core procedure below is the studio standard.

---

<!-- SYNC: release-skill-core from .claude/skills/wow-release-execution/SKILL.md -->
See `BawrLabs/.claude/skills/wow-release-execution/SKILL.md` for the canonical
procedure (config validation, branch/clean checks, shipping set + Gate 2 +
version proposal, lint, changelogs, .pkgmeta sanity, diff review, commit, tag,
push, publication verification, notes, report). Run it via the
`wow-release-execution` skill rather than from this file.
<!-- END SYNC -->
