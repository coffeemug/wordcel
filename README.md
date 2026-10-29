# XWriter

A native macOS app that closely approximates the X post composer. Built with SwiftUI and AppKit, with a real `NSTextView` editor. No web view, Electron, or X account credentials.

## Run

Requires macOS 14 or later and Apple Command Line Tools (`xcode-select --install`).

```sh
./build.sh
open XWriter.app
```

The build produces an ad-hoc signed `XWriter.app` in the project directory. You can move it into Applications. Open `Package.swift` in Xcode if you prefer an IDE.

## Features

- Compact, resizable, draggable composer with X-style colors, spacing, icon buttons, a synonym model picker, and an X Premium counter: a perimeter ring with a 20-to-1 countdown at 260–279 characters, then an unnumbered circle that fills from the bottom at 280 and beyond, up to 25,000.
- The window grows downward as you type, up to 760 points or the available screen height, then scrolls. Deleting text shrinks it again.
- Light, dark, and system appearance from the View menu.
- Native text selection, undo/redo, spell checking, and highlighting for links, hashtags, and mentions.
- A bottom echo area displays errors and status messages instead of message dialogs or floating toasts, without interrupting typing. The next keypress, cursor movement, click, scroll, or menu command clears the message; new messages produced by that action remain visible. Hover to read a long message in full. Settings has no echo area. Deleting a draft in the drawer asks `(y/n)` here and takes focus away from the editor: **Y** confirms; **N** or **Esc** cancels and returns focus to the editor. Other keys only blink the question, without editing text or running shortcuts. Clicking the editor also cancels the question and resumes editing. Other destructive actions still use their existing confirmations.
- On-demand Claude synonyms grouped by Latin and Germanic roots, with click-to-replace suggestions.
- **Ctrl-Enter** opens a `> ` minibuffer input for a freeform prompt. **Enter** sends it to the selected model with the exact selected text, or the cursor's word if nothing is selected. With no cursor word, it sends just the prompt. The model is asked for a short, plain-text reply, shown as a minibuffer message. Longer replies word-wrap and expand the minibuffer upward, lifting the toolbar without moving the editor or resizing the window; dismissing the reply lowers it again. **Esc** cancels input or a pending request; you can keep editing the post while waiting.
- Configurable prompt buttons highlight text using Claude. Add, remove, rename, reorder, and customize their icons and prompts in Settings (⌘,).
- Automatic local draft saving, restoration, and deletion in a right-side drawer. The drawer icon widens the window to keep the composer alongside your drafts. Closing the window keeps the draft; clicking the Dock icon reopens it.
- The build bundles `me.png` as your default avatar. Custom profile photo: click the avatar or use View → Choose Profile Photo.

## Publishing

**Post** opens a review sheet. **Open on X** hands the first post's text to X in your default browser, where you review and publish it. For long posts, **Copy & open X** copies the text and opens the X composer; paste with ⌘V. Nothing is posted automatically. The draft remains saved locally.

Publishing sends text only. Apply any previously saved reply settings directly on X. Previously saved threads remain available; publish their first post and copy the remaining posts into replies on X. New threads cannot be created.

The character counter approximates X's weighting, including CJK characters, combined emoji, Unicode normalization, and 23-character web links. URL detection uses Apple's `NSDataDetector`, so unusual URLs can differ from X's parser. X's own editor makes the final validation.

## Synonyms

Install the official [Claude Code CLI](https://code.claude.com/docs/en/setup) and use a Claude subscription that includes Claude Code. Put the cursor inside a word (or immediately after it), or highlight a phrase, and press **⌃Space**. A phrase lookup finds single words that capture the whole phrase's meaning. The first lookup opens Claude Code's own browser sign-in flow. XWriter uses a separate CLI profile at `~/Library/Application Support/XWriter/claude-code`; the CLI manages all authentication. XWriter does not read or copy its credentials and does not use API-key billing.

While Claude runs in the background, the minibuffer shows `pulling synonyms...` with cycling dots; the toolbar icons stay visible and usable. Results expand the minibuffer upward to two rows of up to six context-fitting suggestions: Latin beside a laurel symbol above Germanic beside an oak leaf. The toolbar, counter, and Post button slide up as an opaque overlay, then slide down when results are dismissed. The window, editor layout, scroll position, and model selector stay fixed; the overlay can temporarily cover the model selector. Click a synonym to replace the target word or the entire selected phrase, preserving surrounding whitespace. Capitalization and native undo/redo are preserved. Suggestions stay visible when switching apps, toggling the drawer, or moving the cursor within the same word. Press **Esc**, edit the target, or choose a different word or phrase selection to cancel the lookup. A new status or error message replaces the suggestions. Long result rows can be scrolled horizontally.

The blue model link with the robot icon above the toolbar selects Fable 5.1 (the default), Opus 5.5, Sonnet 5.5, or Haiku 5.5. The same dropdown offers Low, Medium (the default), High, Extra high, and Max reasoning levels. It stays open while selecting options; click outside or press Esc to close it. Both choices are saved in macOS preferences across restarts and apply to the next synonym or highlighting request; existing results stay visible.

The target word or phrase and its enclosing sentence(s) are sent to the selected model for context-appropriate alternatives, allowing modest shifts in nuance rather than requiring exact equivalence. Suggestions must still fit grammatically and preserve the sentence's overall intent. Results are always single, unhyphenated words, even for phrase lookups. Other sentences are not sent. Each lookup uses a fresh temporary working directory, no session persistence, and no tools, MCP servers, skills, or user/project hooks. Claude may still misclassify a word's origins; suggestions are not verified dictionary entries. Empty groups are shown as “None found.”

If macOS intercepts **⌃Space** to switch input sources, change or disable that binding in **System Settings → Keyboard → Keyboard Shortcuts → Input Sources**. **Edit → Find Synonyms** also starts a lookup. Update Claude Code if it reports unsupported command-line options.

## Highlighting buttons

Open **Settings (⌘,)** to add or remove toolbar buttons, edit their names and prompts, and choose from 41 monochrome icons built from SF Symbols. Drag rows to reorder them. Two editable examples are included: **Latin words** (the same laurel as synonyms) and **Removable wording** (scissors). Settings save automatically across restarts. New buttons stay disabled until they have a name and prompt; an empty toolbar offers an “Add buttons…” link.

Each button also has its own **Highlight style** with a live preview: optional font color, solid strikethrough, no/solid/dotted/wiggly underline with its own color, and optional background color. Color pickers support opacity. Latin words default to a blue solid underline with unchanged text and no background; removable wording defaults to icon-gray text and strikethrough with no background. Existing example buttons receive these styles on upgrade without changing their prompts or icons; other existing buttons retain a yellow background. Saved custom styles are never replaced by the defaults. Changing a style updates current or pending results without another model call.

Write a natural-language rule describing what to highlight; no output-format instructions are needed. Clicking a button sends its prompt and the **entire active post** to the composer's selected Claude model through the same isolated CLI and subscription sign-in as synonyms. Idle icons are gray, with a gray circular background on hover. The active icon turns blue and bounces while waiting for Claude, then rests when the results arrive. Reduce Motion disables the bounce. Click it again to hide the highlights. Selecting another button cancels any pending request, clears the previous highlights, and runs the new prompt. Only one highlighting button is active at a time. Long toolbars scroll horizontally.

Editing never reruns a prompt. Inserting within a highlighted span or at either edge clears that span; deleting or replacing text clears intersected spans. All other intervals shift with the edit, including native undo/redo and edits made while Claude is still responding. Invalidated spans do not reappear on undo. The button stays pressed even if no highlights remain; toggle it off and on to analyze the new text. Cursor movement, app switching, the drafts drawer, and Settings leave highlights intact. Switching posts/drafts, removing the active button, or editing its prompt clears its results.

Claude returns exact quoted spans and occurrence numbers, which the app validates and converts to native UTF-16 ranges without splitting Unicode characters. Malformed output is reported, not partially applied. Highlights are temporary editor attributes: they never alter draft text, clipboard formatting, publishing, or undo history, and they are not saved across restarts. The old image/GIF/poll/emoji/calendar/location actions remain removed.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | New post, preserving the current draft |
| ⌘S | Save draft now |
| ⌘D | Toggle the drafts drawer |
| ⌘Return | Review for publishing on X |
| ⌃Space | Find single-word alternatives for the word at the cursor or selected phrase |
| ⌃Return | Enter a freeform model prompt in the minibuffer |
| ⌘, | Configure toolbar buttons in Settings |
| ⌘⇧D | Toggle light/dark appearance |
| ⌘W | Close the current window |
| ⌘1 | Show the composer |

## Storage and checks

Drafts are written atomically to `~/Library/Application Support/XWriter/drafts.json`. On first load, version-1 archives are upgraded to version 2: saved attachments (including GIFs and ALT descriptions), polls, and planned dates are permanently removed. Saved drafts containing no text are removed; the current editor remains available even when empty. Text and existing threads are preserved. The profile photo is stored separately and is unchanged. The app preserves an unreadable archive instead of overwriting it. Keep a backup of this directory if your drafts are important.

```sh
./check.sh
# Or test the release build:
./XWriter.app/Contents/MacOS/XWriter --self-test
# Launch an isolated window to check native editing and focus:
./XWriter.app/Contents/MacOS/XWriter --ui-test
```

The model checks cover weighted counts, Unicode and URL handling, post validation, draft round trips, editing without duplication, thread restoration, retired-data migration, deletion, corrupt-file protection, synonym targeting, interval tracking, toolbar persistence, and response validation. The native UI checks also exercise Settings, exclusive highlighting toggles, edits during requests, synonym shortcuts, cancellation, replacement and undo, simulated sign-in, and subprocess timeouts. Checks use synthetic Claude responses and never sign in or send your drafts to Claude.

Add `--synonyms-only` to `--ui-test` for focused composer, minibuffer-prompt, and synonym-overlay checks; add `--with-cli-checks` to include the isolated CLI checks without the Settings suite. On unattended desktops where macOS refuses app activation, `--skip-activation-check` explicitly skips and reports the two app-switch checks.

To render isolated previews without modifying your drafts:

```sh
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-light.png
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-dark.png --demo --dark
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-drafts.png --demo --drafts
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-synonyms.png --synonyms
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-synonyms-loading.png --synonyms --loading
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-highlights.png --highlights
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-cuts.png --highlights --cuts
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-wiggly.png --highlights --wiggly
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-loading.png --highlights --loading
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-settings.png --settings
./XWriter.app/Contents/MacOS/XWriter --snapshot /tmp/xwriter-message.png --message
```

The project uses a small `ViewState` wrapper around SwiftUI's public `State<Value>` because recent Command Line Tools SDKs expose a same-named macro whose plugin only ships with Xcode.

Reference behavior: [X Premium limit and counter behavior](https://help.x.com/en/using-x/x-premium-how-to), [X posting help](https://help.x.com/en/using-x/how-to-post), [reply controls](https://help.x.com/en/using-x/x-conversations), and [X Web Intents](https://docs.x.com/x-for-websites/web-intents/overview).

XWriter is an independent app, not an official X client.
