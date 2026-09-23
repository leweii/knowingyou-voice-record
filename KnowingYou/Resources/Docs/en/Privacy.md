# Privacy Policy

## Core promise: zero network

Knowing You **does not collect, upload, or transmit any of your data, in any way.** Specifically:

- **No account system**: no sign-up, no login, no user-identifying information at all.
- **No cloud sync**: all recordings, notes, and screenshots are saved only to the local folder you choose in Settings → General — never uploaded to any server.
- **No telemetry**: this app collects no usage data, crash reports, or analytics.
- **No automatic update checks**: clicking "Check for Updates" on the About page simply opens a web page (the GitHub Releases page) in your default browser — the app process itself never initiates any network connection to check for a new version.
- **No AI / cloud processing**: all audio processing (mixing, transcoding) happens entirely on your Mac; no audio or text is ever sent to any third-party service.

You're welcome to verify this yourself with a tool like [Little Snitch](https://www.obdev.at/products/littlesnitch/) or macOS's built-in network monitoring — Knowing You makes no network connections while running.

## Local data

Knowing You reads and writes the following, all stored on your own Mac:

- **Recordings** (`.m4a`) and **notes** (`.md`): saved to the folder you choose, `Documents/Knowing You` by default.
- **Screenshots**: saved in a subfolder next to the corresponding recording.
- **Preferences**: stored in macOS's standard `UserDefaults` (`~/Library/Preferences/`), containing only your interface preferences (auto-record on/off, shortcut combos, etc.) — never recording content.
- **System logs**: macOS's standard `OSLog` mechanism records this app's runtime logs (used for troubleshooting when you choose to export diagnostics). Logs only ever exist on your Mac; Knowing You never uploads them on its own.

## System permissions

Knowing You requests four system permissions — microphone, system audio recording, notifications, and screen recording — each used strictly for its corresponding feature (see the Help document), never for any data-collection purpose. You can review or revoke these at any time in System Settings → Privacy & Security.

## Contact

If you have questions about this privacy policy, you can reach the developer via Settings → General → Feedback.
