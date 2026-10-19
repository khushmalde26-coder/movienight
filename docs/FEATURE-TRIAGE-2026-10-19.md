# Feature requests: triage

Khush's 17 requests from 19 Oct 2026, sorted by what exists, what is worth building, and what I'd cut. Effort is a rough guess: S is a day or less, M is a few days, L is a week or more.

## Already there, or mostly

| # | Request | State |
|---|---|---|
| 2 | Calm home screen | Done. Continue Watching, Recently Added, On This Day, folders and years build themselves with no setup. |
| 3 | Smart resume | Done. Resume and Start Over on the video page, and the Always Watch from Beginning setting. A one-tap "Restart" on the Continue Watching card would finish it (S). |
| 8 | Picture in Picture | Works for MP4/MOV on Mac and iPad. **Missing for MKV and other mpv formats.** mpv draws with Metal, which PiP doesn't accept, so this means copying frames into a sample-buffer layer (L, and fiddly). |
| 1 (part) | Network drives | Probably works today, but nobody has tested it. On Mac, a mounted SMB share is just a folder. On iPad, the Files picker can see servers added under Files > Connect to Server. |

## Worth building, in this order

| # | Request | Effort | Notes |
|---|---|---|---|
| 9 | Chapters and saved moments | M | Chapters come from the file in both engines. Bookmarks are a timestamp list per video. Making clips only works for MP4/MOV (AVFoundation can export them); MKV clips would need FFmpeg's command-line tool, which isn't bundled. |
| 5 | Effortless controls | M | One set of controls for both engines: tap the edges to skip, swipe for volume and brightness on iPad, and advanced controls behind a button. Fixes the "two players feel different" weak spot too. |
| 12 | Accessibility | M | Dynamic Type everywhere (the banner title is a fixed 40pt today), VoiceOver labels on chips and cards, keyboard navigation of shelves on Mac, high contrast. Cheap now, expensive to retrofit later. |
| 1 | Open anything (video) | M | One "Open" button for a file, folder or URL (http, HLS streams). Both engines already play URLs; the work is the UI and treating a link as a library item. |
| 6 | Subtitle help | M | Timing offset, size and background, remembered language: S to M, works in both engines. Also .srt files next to MP4/MOV. **Searching for subtitles online needs an OpenSubtitles account and API key**, which only you can set up. |
| 16 | Cleanup suggestions | S | Duplicates (same name and size), files that won't play, iCloud files that never finished downloading. Read-only list, never deletes. |
| 10 | Collections | M | Folder, year, source and event grouping already exist. Custom lists are the new part. "Series" can come from file names like S01E02. |
| 4 | Queue (video only) | M | Play next, reorder, shuffle, Watch Later. Pairs with "Play next" from the review. |
| 7 | Clearer audio | M | Easy on mpv (dialogue boost and loudness levelling are built-in audio filters). On AVKit it needs custom audio processing: L. Ship mpv first, or route everything through mpv when it's on. |
| 11 | Presets | S | Only worth it once 7 exists. "Quiet room" is loudness levelling. "Save battery" is hardware decoding and 30fps. |
| 15 | Offline packs | M | iPad only. Copy chosen videos into the app with storage shown. Matters mostly for iCloud and SSD libraries. |
| 14 | Inbox | M | Needs a Share extension (a second app target, its own signing). Do after 1. |
| 17 | Themes and wallpapers | S to M | Accent colours and backgrounds from the user's own photos. **Apple's wallpapers can't be bundled**, they are Apple's copyright. On Mac you could pick one from /System/Library/Desktop Pictures yourself through the file picker; on iPad they aren't readable at all. |
| 13 | Handoff | L | Passing what's playing to another device is simple (Handoff). Passing the queue, progress and preferences needs the iCloud sync the library doesn't have yet, which first needs a data-model change. |

## I'd cut or postpone

- **Books (1).** Reading is a different app: pagination, fonts, highlights, EPUB and PDF rendering. Putting it here dilutes the one thing this app is better at than VLC and Infuse, which is home video. Books.app already does it well.
- **Music and podcasts (1, 4).** Possible, since both engines play audio, but they need their own screens (albums, artists, episode lists, feeds, background downloads). That's a second product. I'd only add plain audio files played like video, no music library.
- **Home-screen toggles for content types (1).** Only needed if music and books come in.

## Proposed order

- **Batch A, quick wins (1 to 2 days):** resume or restart choice on Play (3), bookmarks and chapters (9), cleanup suggestions (16), audio controls (7), presets (11), themes with original gradients and your own photos (17).
- **Batch B, the player (about a week):** one set of controls for every format, which also brings PiP, AirPlay and lock-screen controls to MKV (5), subtitles (6), accessibility (12).
- **Batch C, library (about a week):** queue (4), series detection and custom lists (10), one Open button with links, streams and network drives (1).
- **Batch D, bigger pieces:** inbox via a Share extension (14), offline packs (15), Handoff (13, fully useful only after Mac and iPad share a library).

Open decisions for Khush: scope for music, podcasts and books; the wallpaper replacement; and whether to start Batch A.
