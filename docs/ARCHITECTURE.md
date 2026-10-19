# Movie Night: architecture and plan

A Netflix / Apple TV+ style browser and player for videos you own: home videos, family footage, ripped or purchased files. It reads folders on the device, in iCloud Drive and on external SSDs, and presents them as shelves with artwork, resume points and sensible titles instead of a file list.

## Decisions (defaults, open to change)

| Area | Choice | Why |
|---|---|---|
| Platform | SwiftUI, one multiplatform target, macOS 14+ first, iPadOS/iOS 17+ from the same code | External SSD libraries live on Macs. iPad works via Files but is second priority. |
| Persistence | SwiftData | Small schema, native, no server. |
| Folder access | Security-scoped bookmarks | The only way a sandboxed app keeps access to a user-picked folder (iCloud Drive or SSD) across launches. |
| Playback | AVKit (`AVPlayerView` / `AVPlayerViewController`) behind a small seam | Best battery, PiP, AirPlay, HDR, native controls. Fails on MKV and some codecs, see "Format support". |
| Artwork | Generated frame grab at ~10% of duration, cached as JPEG on disk | Home videos have no posters, the first frame is often black. |
| Titles | Camera filenames (`IMG_1234`, `PXL_...`, `GOPR...`) become the recording date; other names are cleaned up | `IMG_4821.MOV` on a hero banner looks broken. |
| Dates | QuickTime `creationDate` metadata first, file dates as fallback | Copying files between drives resets file dates; the embedded date survives. |

## Honest weak spots

1. **This is a crowded space.** Infuse already does local files, SMB, SSDs, MKV and a polished UI on Mac, iPad and Apple TV. Plex and Jellyfin cover the server route. A generic "nicer VLC" loses to Infuse. The defensible angle is **home video specifically**: Infuse is built around TMDB metadata for films and TV and handles a folder of `IMG_*.MOV` poorly. So the product's value is in auto-titling, date and event grouping, "On this day", good frame selection and (later) people/place grouping with Vision and location metadata. The plan below leans that way.
2. **Most family video is probably in iCloud Photos, not iCloud Drive.** Those are different stores. iCloud Drive folders work with this design; the Photos library needs PhotoKit, which is a separate source type. Worth confirming where your footage actually lives before building more source types.
3. **Two players means two sets of behaviour.** AVKit files get PiP and AirPlay; mpv files get our own controls and no AirPlay. Worth unifying the controls later so the difference isn't visible.
4. **iCloud Drive with "Optimise Storage" evicts files.** Scanning sees them, but thumbnails and duration need the bytes. The scanner records evicted files and only reads metadata from local ones; playback triggers a download first. Generating artwork for a large evicted library would download all of it, so that must stay opt-in.
5. **External drives go away.** Bookmarks survive unplugging on macOS, and resolve again when the drive returns. The library marks the source offline and keeps its items (greyed out) instead of deleting them, which is what a naive rescan would do. iPadOS bookmarks to external drives are less reliable and need real-device testing.
6. **Apple TV is the natural home for this UI, and tvOS has no file access.** A tvOS app would need the Mac to act as a server (Bonjour plus HTTP range streaming). Out of scope for v1, but it shapes the design: the library model should not assume local file URLs forever.

## Module layout

```
MovieNight/
  App/          App entry, AppModel (navigation, now-playing)
  Models/       SwiftData models: LibrarySource, MediaItem
  Library/      Bookmarks, scanner, metadata reader, thumbnails, LibraryStore, ShelfBuilder, DisplayTitle
  Playback/     PlaybackSession (AVPlayer + progress), PlayerView (platform wrappers)
  UI/           Home, hero banner, shelf rows, cards, detail, sources, theme
MovieNightTests/  Swift Testing tests for the pure logic (titles, shelves)
```

### Data flow

1. User picks a folder with `.fileImporter`. `LibraryStore.addSource` creates a security-scoped bookmark and a `LibrarySource`.
2. On launch, each bookmark is resolved and `startAccessingSecurityScopedResource()` is held for the app's lifetime. Stale bookmarks are refreshed; unresolvable ones mark the source offline.
3. `LibraryScanner` (an actor, off the main thread) walks the folder and returns `ScannedFile` value snapshots, including iCloud download state.
4. `LibraryStore` (main actor) upserts `MediaItem`s keyed by source + relative path, deletes items whose files disappeared (only when the source is online), then enriches new local items with `MetadataReader` (duration, embedded date, playability) and `ThumbnailService`.
5. `ShelfBuilder` is a pure function from item snapshots to shelves: Continue Watching, On This Day, Recently Added, one shelf per year, one per top-level folder. It is unit tested.
6. `PlaybackSession` owns the `AVPlayer`, resumes from saved progress, saves progress every 5 seconds and marks an item finished past 95%.

## Format support

Two engines, chosen per file when it is first scanned (`MediaItem.engine`):

- **AVKit** for anything AVFoundation opens (MOV, MP4, M4V, most phone and camera footage). It brings PiP, AirPlay, system controls and the best battery life.
- **mpv via MPVKit** (libmpv + FFmpeg, LGPL build) for everything else on the [video file format list](https://en.wikipedia.org/wiki/Video_file_format): MKV, WebM, AVI, WMV/ASF, FLV/F4V, VOB, MPEG-PS/TS, Ogg, RealMedia, MXF, NSV, RoQ, AMV and more. It decodes with VideoToolbox where it can and renders through Vulkan on Metal (MoltenVK). Its controls are our own SwiftUI overlay, with audio and subtitle track menus; external `.srt`/`.ass` files next to the video are picked up automatically.

`MPVProbe` also gives non-AVFoundation files the same metadata as the rest (duration, resolution, frame rate, codec, HDR, audio channels, embedded date) and a thumbnail, using a headless mpv that decodes one frame to JPEG.

Deliberately not supported: `.m4p`/`.f4p` (DRM, only Apple's and Adobe's own players can decrypt them), `.yuv` (raw frames with no header, so nothing knows their size), `.gif`/`.gifv`/`.mng` (images and web animations), `.f4a`/`.f4b` (audio only).

Licensing: the LGPL MPVKit product is used, not MPVKit-GPL. Its xcframeworks are static, so an App Store release needs the LGPL relinking offer (bundled licence texts plus object files on request), and a libmpv build without LuaJIT, whose JIT is refused by the App Store and the hardened runtime. Until then `ENABLE_HARDENED_RUNTIME` is off.

## Roadmap

1. **Phase 1 (this scaffold):** sources, scanning, artwork, shelves, hero, detail, AVKit playback with resume. macOS first.
2. **Phase 2:** home-video smarts. Event grouping (clips within a few hours become one "event"), better frame picking (skip dark and blurry frames using luminance and Vision saliency), editable titles and collections, search.
3. **Phase 3:** chapter markers and scrubbing thumbnails; Lua-free libmpv build for distribution.
4. **Phase 4:** PhotoKit source, iPad polish, then Mac-as-server for an Apple TV client.

## Building

No repository is attached yet. The project is generated with XcodeGen so the repo holds a readable `project.yml` instead of a `.pbxproj`:

```
brew install xcodegen
cd movie-night
xcodegen
open MovieNight.xcodeproj
```

The code was written without a Swift toolchain available (the cloud workspace is Linux), so expect a few compile fixes on the first build in Xcode 16 or later.
