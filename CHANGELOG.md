# Changelog

The appcast generator reads this file. Each release is a `## <version>` heading, and everything
under it until the next heading becomes that version's release notes in the update feed.

## 0.1.0

First release.

- One window per simulator, with the device body drawn around the screen and its buttons clickable.
- Point Accurate, Pixel Accurate, Physical Size and Fit, plus full screen and windows that remember
  where they were.
- Click to tap, drag, two finger pinch and rotate, keyboard input, hardware buttons, and the swipe
  up from the bottom edge that goes home or opens the app switcher.
- Rotation, screenshots, screen recording, drag and drop onto a device, and the clipboard shared
  with the Mac.
- A window follows its device: it shows when the device has shut down, offers a reboot, and
  reattaches on its own when the device comes back.
- The `odhub` command line tool beside the app, for listing devices and driving input from a script.

Known gaps are listed in the README.
