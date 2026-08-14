# Changelog

All notable changes to HandyNotes: Homestead are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/). The release workflow
extracts the `## [X.Y.Z] - YYYY-MM-DD` section matching the pushed tag, so the
entry for a version must exist before its tag is pushed.

To cut a release: RENAME the `## [Unreleased]` heading to `## [X.Y.Z] - date`
(then start a fresh Unreleased section above it). Do NOT add the version
heading below the Unreleased content: extraction takes everything between the
version heading and the next VERSION heading (`## [Unreleased]` does not stop
it, so always keep Unreleased ABOVE the released sections), and appending below
ships an EMPTY changelog to CurseForge/Wago/GitHub on a green CI run.

## [Unreleased]

### Added

- Vendor tooltips now show item prices, with coin and currency icons.
- Items with a cost the tooltip can't fully show, such as one paid for with
  another item, now show "(other cost)" next to any price that can be shown,
  so they don't look free or cheaper than they are.

## [1.0.0] - 2026-08-12

- Initial release: housing decor vendor map pins with vendor wares in
  tooltips, powered by Homestead.
