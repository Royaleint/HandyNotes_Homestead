# Changelog

All notable changes to HandyNotes: Homestead are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/) — the release workflow
extracts the `## [X.Y.Z] - YYYY-MM-DD` section matching the pushed tag, so the
entry for a version must exist before its tag is pushed.

To cut a release: RENAME the `## [Unreleased]` heading to `## [X.Y.Z] - date`
(then start a fresh Unreleased section above it). Do NOT add the version
heading below the Unreleased content — extraction takes everything between the
version heading and the next VERSION heading (`## [Unreleased]` does not stop
it — always keep Unreleased ABOVE the released sections), so appending below
ships an EMPTY changelog to CurseForge/Wago/GitHub on a green CI run.

## [Unreleased]

- Initial release: housing decor vendor map pins with wares tooltips,
  powered by Homestead's verified vendor data.
