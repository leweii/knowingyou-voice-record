# Third-Party Licenses

Knowing You uses or references the following open-source projects.

## KeyboardShortcuts

Used for registering, storing, and validating global keyboard shortcuts (`System/HotkeyManager.swift`).

- Author: Sindre Sorhus
- Project: https://github.com/sindresorhus/KeyboardShortcuts
- License: MIT License

```
MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

## AudioCap (reference code, not a linked dependency)

Knowing You's Core Audio Process Tap implementation (`Recording/ProcessTap/`) references the Process Tap + private aggregate device approach demonstrated by the AudioCap project. This is a learning-oriented code port, not a bundled binary or source library dependency.

- Author: Guilherme Rambo
- Project: https://github.com/insidegui/AudioCap
- License: MIT License

## Swift standard library and Apple system frameworks

AVFoundation, Core Audio, ScreenCaptureKit, UserNotifications, and similar frameworks are provided by Apple and ship with macOS itself — they are not third-party dependencies.
