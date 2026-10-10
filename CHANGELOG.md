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

## [1.2.0] - 2026-10-09

### Added

- The addon's tooltip and options text is now translated into ten client
  languages: German, Spanish (Spain), Spanish (Mexico), French, Italian,
  Korean, Brazilian Portuguese, Russian, Simplified Chinese and Traditional
  Chinese.

### Changed

- The vendor's location in tooltips, the zone and, where the vendor has a
  known area, the subzone, now shows in your game's language using the
  game's own place names. If no translation is available, the English text
  is shown as before.
- Some tooltip and option labels now use the game's own wording.
- Vendor data refreshed from Homestead 2.12.0.

### Fixed

- World map summary badges are now reused instead of being rebuilt every
  time you change maps, zoom or resize the map, so the addon no longer piles
  up map frames over a long play session.
- Corrected 54 vendor currency prices across 20 vendors that were still
  showing older, higher amounts in currencies such as Order Resources, War
  Resources, Honor, Elemental Overflow and Resonance Crystals.
- Samantha Buckley now appears on the Ruins of Gilneas zone map instead of
  the Ruins of Gilneas City map.
- Three vendor pins in the Hall of the Guardian, Arcantina and Silvermoon
  City were moved to their correct spot.

## [1.1.3] - 2026-09-29

### Fixed

- Clicking a zone or continent map pin on the world map during combat no
  longer causes a lua error. Now, in combat clicking will show "You can't do
  that while in combat" error message. Out of combat function is unchanged.

## [1.1.2] - 2026-09-27

### Changed

- Vendor data refreshed from Homestead 2.11.0.

### Fixed

- Corrected 41 vendor prices for patch 12.1, mostly at Draenor and
  Undermine vendors.
- 9 items were missing from vendors in Arcantina, Silvermoon City and the
  Vaults of Atal'Utek. They now appear in those vendors' tooltips.

## [1.1.1] - 2026-09-14

### Fixed

- Reduced the performance cost of vendor tooltips while item names and
  prices are still loading. The difference is largest on vendors with
  many wares.

## [1.1.0] - 2026-09-02

### Added

- Vendor tooltips now show item prices, with coin and currency icons.
- Items paid for with another item now show that item's amount and icon
  in the tooltip. A price the game has not loaded yet shows as
  "(other cost)" and fills in on its own.
- Vendors with more than 15 wares now show a scrollable tooltip with a
  search box, so you can find a specific item without scanning the
  whole list. Search matches item, currency and reagent names.
- On the world map, vendor pins now draw above Blizzard's points of
  interest, map links and world quest markers instead of disappearing
  behind them, and they step clear of each other so neighbouring
  vendors stay individually clickable. Pins are one pixel larger.
- Continent and world maps now show a badge on each zone or continent
  that has vendors, with the number of vendors on it. Click one to zoom
  to that map.
- Irodalmin now shows on the map only if you know Herbalism.

### Changed

- Vendor data refreshed from Homestead 2.10.1.

### Fixed

- The Disguised Decor Duel Vendor's twelve items were listing the wrong
  currency and amounts. They now show their Voidlight Marl prices.
- A second Shadow-Sage Brakoss pin in Stormshield that should not have
  been there is gone.

### Known issues

- A vendor pin sitting directly on top of one of Blizzard's
  zone-transition markers blocks that marker's right-click navigation.

## [1.0.0] - 2026-08-12

- Initial release: housing decor vendor map pins with vendor wares in
  tooltips, powered by Homestead.
