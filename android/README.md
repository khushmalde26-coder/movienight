# Movie Night for Android

Phones, tablets and Android TV / Google TV from one app. Kotlin, Jetpack Compose, Room and Media3 ExoPlayer.

## Build

Needs the Android SDK (Android Studio installs it) and a JDK 17 or newer (Android Studio's bundled one works).

```
cd android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"   # macOS with Android Studio
./gradlew :app:testDebugUnitTest      # organising logic, same cases as the Apple app's tests
./gradlew :app:installDebug           # onto a connected device or running emulator
```

Or open the `android` folder in Android Studio and press Run.

The logo, app icon and startup animation aren't duplicated here: the build copies them from the Apple
app's `MovieNight/Resources` (task `sharedArt`), so both apps always use the same files.

## How it fits together

- `core/`: pure Kotlin ports of the Apple app's organising rules (ContentClassifier, DisplayTitle,
  shelf builders for Home, Films, TV Shows and Home Videos, TitleMatcher, WatchHistory). Unit tested
  with the same cases, so both apps arrange a library the same way.
- `data/`: Room database of sources, videos and the watch history of files that moved.
- `library/`: LibraryStore scans sources and fills in length, dates and artwork (MediaMetadataRetriever).
  - Folders and single videos use the system picker with persisted permission, the Android version of
    the Apple app's security-scoped bookmarks: a drive that's unplugged keeps its videos, greyed out.
  - "This Device's Videos" reads the system's media index, for TVs and boxes that have no folder picker
    (internal storage and USB drives).
- `playback/`: ExoPlayer with resume, progress saving, next episode, and a fallback to another decoder
  when a hardware decoder fails mid-file.
- `ui/`: one set of screens laid out three ways: bottom tabs on phones, a side rail on tablets, and
  tabs over the banner on TV with D-pad focus (OK on the remote plays; only Up leaves a page for the tabs).

Debug builds can try another layout on any device:
`adb shell am start -n com.khush.movienight/.MainActivity --es formFactor tv` (or `tablet`, `phone`;
`auto` goes back to normal, after force-stopping the app).

## Not yet

VLC-based fallback for formats ExoPlayer can't open (AVI, WMV, RealMedia), network shares (SMB),
TitleChek, picture in picture, subtitle and audio options beyond the player's own menu, saved moments,
collections, wallpapers and accent colours.
