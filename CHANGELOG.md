# Changelog

The appcast generator reads this file. Each release is a `## <version>` heading, and everything
under it until the next heading becomes that version's release notes in the update feed.

## 0.2.0

- The camera control works on every iPhone that has one, not only the iPhone Duo, and Device,
  Camera Control presses it. The item appears only for devices with the button. The simulator has
  no camera, so the device takes a screenshot.
- Choosing cover, half open or fully open on the iPhone Duo folds it smoothly to that angle instead
  of jumping, unless Reduce Motion is on. The device stays inside the window in every pose,
  standing ones included.
- The iPhone Duo's window moves to the screen the device is using sooner after a fold.
- Recording the iPhone Duo records the screen it is using, follows it through a fold, and keeps the
  picture the right way up.
- A window opens the way its device is already turned, instead of assuming it is upright.
- Restarting a device no longer leaves its window half connected. The iPhone Duo's fold buttons,
  cover screen and touches come back with the fold it was showing, and the clipboard sync picks up
  again.
- Device, Shut Down shuts a simulator down from the menu.
- Restart, Shut Down, Erase, the hardware buttons, rotation, Shake, location and text size act on
  the simulator in front, not on every open one.
- Favorite locations: save named coordinates in Settings and choose them from Features, Location.
- Screenshots and recordings each have their own folder in Settings, starting from the folder you
  had already chosen, and Save Screen can put the picture on the clipboard instead of in a file.
- Clipboard sync can be turned on or off in Settings as well as from the Edit menu, and the two stay
  in step.
- The screen shown while a device is shut down or starting stays inside its rounded corners.
- The Settings window can be resized, and scrolls.
- The disk image opens as an installer window: drag the app onto Applications. The mounted disk
  shows the app's icon.

Shut Down, favorite locations and the capture and clipboard settings were contributed by
@stephen-zeng.

## 0.1.0

First release.

- Click the icon and a simulator opens: whatever is already running, or the one shown last. Pick any
  other from the Dock icon or File, Open Simulator, and a device booted anywhere else gets a window
  too.
- One window per simulator, with the device body drawn around the screen and its buttons clickable.
- The iPhone Duo is shown as the foldable it is: the body bends with the hinge, cover, half open
  and fully open are a click away, the window follows whichever screen the device is using, and
  touch, scroll, home, the app switcher, rotation, screenshots and the buttons on the body all work
  on it.
- Point Accurate, Pixel Accurate, Physical Size and Fit, plus full screen and windows that remember
  where they were.
- Click to tap, drag, two finger pinch and rotate, keyboard input, hardware buttons, and the swipe
  up from the bottom edge that goes home or opens the app switcher.
- Rotation, screenshots, screen recording, drag and drop onto a device, and the clipboard kept in
  step with the Mac: copies carry over on their own, and a copy made inside a device is there when
  you switch to another app.
- A window follows its device: it shows when the device has shut down, offers a reboot, and
  reattaches on its own when the device comes back.
- A capture shows itself beside the window before it is filed, so you can open, copy, save or discard
  it. Left alone it saves itself, to a folder you choose.
- Create a simulator without leaving the app: name, device type and OS version, where the two lists
  follow each other so a device no installed runtime can run is never offered.
- Device controls beyond the buttons: restart, erase, text size, increased contrast, an iCloud sync,
  and a location from a scenario or your own coordinates.
- Keyboard choices: send keys to the device or keep them, connect the Mac keyboard as the device's
  hardware keyboard, and match the device's keyboard language to the Mac's.
- Settings for what closing a window does, what launching opens, where captures go, whether device
  links open here, and updates.
- The menu bar follows the simulator it replaces: the same menus in the same order, the same
  shortcuts, and the standard macOS ones that were missing. The zoom shortcuts are Apple's now,
  ⌘1 Physical Size, ⌘2 Point Accurate, ⌘3 Pixel Accurate, ⌘4 Fit Screen, which changes three of the
  four this app used before.
- The `odhub` command line tool beside the app, for listing devices and driving input from a script.
  One menu item puts it on your PATH, without a password on most machines.
- If Xcode is missing or its simulator frameworks will not load, the app says what is missing and
  what to do about it instead of failing silently.
