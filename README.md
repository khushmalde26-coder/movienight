# Movie Night

A Netflix / Apple TV+ style library and player for videos you own, home videos first.
macOS 14+ and iPadOS/iOS 17+, SwiftUI + SwiftData + AVKit.
Android phones, tablets and TV: see [android/README.md](android/README.md).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for decisions, weak spots and the roadmap. Logo source files are in [docs/brand](docs/brand).

## Run it

```
brew install xcodegen
xcodegen
open MovieNight.xcodeproj
```

Pick the "My Mac" destination, run, and add a folder of videos.

## Status

Phase 1 scaffold: folder sources (local, iCloud Drive, external drives) via security-scoped bookmarks,
background scanning, generated artwork, shelves (Continue Watching, On This Day, Recently Added,
folders, years), detail page, AVKit playback with resume. MKV and other non-AVFoundation formats are
detected and flagged but not playable yet.
