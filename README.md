# XWriter

A native macOS app that closely approximates the X post composer. Built with SwiftUI and AppKit, with a real `NSTextView` editor. No web view, Electron, external packages, or account credentials.

## Run

Requires macOS 14 or later and Apple Command Line Tools (`xcode-select --install`).

```sh
./build.sh
open XWriter.app
```

The build produces an ad-hoc signed `XWriter.app` in the project directory. You can move it into Applications. Open `Package.swift` in Xcode if you prefer an IDE.

## Features

- Compact, resizable, draggable composer with X-style colors, spacing, icon buttons, reply controls, and an X Premium counter: a perimeter ring with a 20-to-1 countdown at 260–279 characters, then an unnumbered circle that fills from the bottom at 280 and beyond, up to 25,000.
- The window grows downward as you type, up to 760 points or the available screen height, then scrolls. Deleting text shrinks it again.
- Light, dark, and system appearance from the View menu.
- Native text selection, undo/redo, spell checking, emoji picker, and highlighting for links, hashtags, and mentions.
- Up to four image attachments from the file picker, clipboard, or drag and drop. GIF files are supported; the inline preview is static. Images can have editable ALT descriptions.
- Thread composition, poll drafting, and an optional planned date.
- Automatic local draft saving, search, restoration, and deletion. Closing the window keeps the draft; clicking the Dock icon reopens it.
- The build bundles `me.png` as your default avatar. Custom profile photo: click the avatar or use View → Choose Profile Photo.

## Publishing

**Post** opens a review sheet. **Open on X** hands the first post's text to X in your default browser, where you review and publish it. For long posts, **Copy & open X** copies the text and opens the X composer; paste with ⌘V. Nothing is posted automatically. The draft remains saved locally.

Images, ALT descriptions, polls, reply permissions, and planned dates are draft metadata; they must be added on X. The review sheet lets you export images and copy ALT descriptions. For threads, publish the first post and copy the remaining posts into replies on X. Planned dates do not trigger automatic publishing or reminders. Location is disabled because this app has no X account integration.

The character counter approximates X's weighting, including CJK characters, combined emoji, Unicode normalization, and 23-character web links. URL detection uses Apple's `NSDataDetector`, so unusual URLs can differ from X's parser. X's own editor makes the final validation.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | New post, preserving the current draft |
| ⌘S | Save draft now |
| ⌘D | Open drafts |
| ⌘O | Add photos |
| ⌘Return | Review for publishing on X |
| ⌘⇧Return | Add another post to the thread |
| ⌃⌘Space | Emoji & Symbols |
| ⌘⇧D | Toggle light/dark appearance |
| ⌘W | Close the composer |
| ⌘1 | Show the composer |

## Storage and checks

Drafts and attached image data are written atomically to `~/Library/Application Support/XWriter/drafts.json`. The profile photo is stored alongside it. The app preserves an unreadable archive instead of overwriting it. Keep a backup of this directory if your drafts are important.

```sh
./check.sh
# Or test the release build:
./XWriter.app/Contents/MacOS/XWriter --self-test
# Launch an isolated window to check native editing and focus:
./XWriter.app/Contents/MacOS/XWriter --ui-test
```

The model checks cover weighted counts, Unicode and URL handling, post and poll validation, draft round trips, editing without duplication, thread restoration, attachments, deletion, and corrupt-file protection. The native UI checks exercise the avatar, initial focus, typing, undo/redo, window expansion and its screen-aware cap, caret visibility while scrolling, shrinking, thread editing, and persistence.

To render isolated previews without modifying your drafts:

```sh
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-light.png
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-dark.png --demo --dark
```

The project uses a small `ViewState` wrapper around SwiftUI's public `State<Value>` because recent Command Line Tools SDKs expose a same-named macro whose plugin only ships with Xcode.

Reference behavior: [X Premium limit and counter behavior](https://help.x.com/en/using-x/x-premium-how-to), [X posting help](https://help.x.com/en/using-x/how-to-post), [reply controls](https://help.x.com/en/using-x/x-conversations), and [X Web Intents](https://docs.x.com/x-for-websites/web-intents/overview).

XWriter is an independent app, not an official X client.
