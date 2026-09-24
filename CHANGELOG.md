# Changelog

The appcast generator reads this file. Each release is a `## <version>` heading, and everything
under it until the next heading becomes that version's release notes in the update feed.

## 0.1.0

First release.

- Click the icon and a simulator opens: whatever is already running, or the one shown last. Pick any
  other from the Dock icon or File, Open Simulator, and a device booted anywhere else gets a window
  too.
- One window per simulator, with the device body drawn around the screen and its buttons clickable.
- Point Accurate, Pixel Accurate, Physical Size and Fit, plus full screen and windows that remember
  where they were.
- Click to tap, drag, two finger pinch and rotate, keyboard input, hardware buttons, and the swipe
  up from the bottom edge that goes home or opens the app switcher.
- Rotation, screenshots, screen recording, drag and drop onto a device, and the clipboard kept in
  step with the Mac: copies carry over on their own, and a copy made inside a device is there when
  you switch to another app.
- A window follows its device: it shows when the device has shut down, offers a reboot, and
  reattaches on its own when the device comes back.
- The menu bar follows the simulator it replaces: the same menus in the same order, the same
  shortcuts, and the standard macOS ones that were missing. The zoom shortcuts are Apple's now,
  ⌘1 Physical Size, ⌘2 Point Accurate, ⌘3 Pixel Accurate, ⌘4 Fit Screen, which changes three of the
  four this app used before.
- The `odhub` command line tool beside the app, for listing devices and driving input from a script.
  One menu item puts it on your PATH, without a password on most machines.
- If Xcode is missing or its simulator frameworks will not load, the app says what is missing and
  what to do about it instead of failing silently.

Known gaps are listed in the README.
