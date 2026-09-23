# Help

## How to use it

Knowing You is a menu-bar meeting recorder. Everyday usage looks like this:

1. **Manual recording**: click the menu bar icon to open the panel, then click "Start Recording." Click the same button again (now shown in red as "Stop Recording") to finish.
2. **Automatic recording** (optional): in Settings → Recording → Meeting Detection, enable the meeting apps you use, then turn on Settings → Recording → Auto-Record. From then on, whenever one of those apps starts using the microphone, Knowing You begins recording automatically after 3 seconds (or, with Auto-Record off, shows a notification asking whether to start).
3. **Taking notes while recording**: once recording starts, a small floating widget appears near the top-right of your screen. Click its pencil icon to expand it into a notes window you can type into; when you stop recording, your notes are saved as a `.md` file with the same name as the recording.
4. **Marking a moment**: press the shortcut (⌥⌘M by default) or click the flag icon in the notes window to insert a timestamped marker in your notes, making it easy to jump back to later.
5. **Screenshot**: press the shortcut (⌥⌘S by default) or click the screenshot button in the notes window to capture the meeting app's current window. The image is saved in a subfolder next to the recording, and a reference is inserted into your notes.

When a recording finishes, you'll find two files in the folder set under Settings → General → Data & Storage: `<timestamp> <app name>.m4a` (audio) and `<timestamp> <app name>.md` (notes — only created if you typed a title or wrote at least one note/mark).

## About permissions

Knowing You asks for the following system permissions, each only the first time you actually use the feature that needs it — not all at once on launch:

- **Microphone**: to record your own voice. Requested the first time you click "Start Recording."
- **System Audio Recording** (macOS may label this "Screen & System Audio Recording"): to record other participants' audio played through your speakers. Also requested on your first recording.
- **Notifications**: for meeting and recording-saved alerts. Requested during first-run onboarding.
- **Screen Recording**: only needed for the screenshot-mark feature, requested the first time you use it.

If you accidentally decline a permission, you can re-enable it in System Settings → Privacy & Security, or use the "Grant Access" button next to the relevant setting in Knowing You to jump straight there.

## FAQ

**I can't hear the other participants in my recording?**
First check that Settings → Recording → System Audio is on, then confirm Knowing You is checked under System Settings → Privacy & Security → Screen & System Audio Recording. Once both are set, start a new recording.

**Why didn't I get a meeting-detected notification?**
Make sure Settings → Notifications → Meeting Started Alert is on, and that the meeting app is checked under Settings → Recording → Meeting Detection. Also note: if Auto-Record is on, Knowing You starts recording directly instead of showing a notification — that's expected behavior, not a bug.

**Where are my recordings saved?**
Settings → General → Data & Storage → Save Location shows the current folder; click "Show in Finder" next to it to open it directly. By default this is `Documents/Knowing You`.

**Will a meeting in a browser (e.g. a web version of a meeting app) auto-record?**
No — it will only show a notification asking you to confirm. Knowing You can only tell that "the browser is using the microphone," not which website, so browser-based meetings always require your manual confirmation to avoid recording the wrong thing.

**If I switch microphones or unplug my headset mid-recording, does the recording break?**
With Microphone set to "Smart Selection," Knowing You follows the system's default input device automatically without interrupting the recording, and a "Microphone switched to XXX" note is added automatically.
