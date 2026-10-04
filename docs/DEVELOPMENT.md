# Development notes

## Build directory

The scripts build into `~/Library/Caches/numo-build` instead of `.build`: SwiftPM's SQLite build
database fails with "disk I/O error" inside some synced folders. Override with `NUMO_BUILD_DIR`.

## Tests without Xcode

With only the Command Line Tools installed, swift-testing lives outside the default search paths.
`scripts/test.sh` adds them automatically.

## Rendering the UI to PNG

The app has a snapshot hook used for screenshots (run the bundled binary — document types are
declared in its Info.plist):

```bash
NUMO_DOC=/tmp/note.txt NUMO_SNAPSHOT=/tmp/shot.png [NUMO_DARK=1] \
  build/Numo.app/Contents/MacOS/Numo -ApplePersistenceIgnoreState YES -appearance light
```

- `NUMO_DOC=untitled` opens a new untitled note; `NUMO_SNAPSHOT_GUIDE=1` adds the syntax guide as a tab.
- `NUMO_SNAPSHOT_SETTINGS=1` / `2` renders the Appearance / General settings tab.
- `NUMO_SNAPSHOT_HEIGHT=900` sets the window height.
- Settings can be overridden per run with arguments such as `-fontSize 17 -resultColor slate`
  (pass each as a separate argument). `-ApplePersistenceIgnoreState YES` keeps restored windows out.
- Snapshot runs never touch Open Recent or migrate notes.

## Event log

`defaults write com.melonkid.numo eventLog -bool YES`, restart Numo, and mouse / keyboard handling
is logged to `~/Library/Logs/Numo/events.log`.
