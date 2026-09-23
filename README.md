# OpenDeviceHub

An open-source iOS Simulator app for Xcode 26 and 27.

Xcode 27 replaced Simulator.app with Device Hub. OpenDeviceHub brings back the classic Simulator workflow (one window per device, pixel-accurate scaling, familiar shortcuts) with extra tooling for mobile developers and first-class Flutter support.

## Status

Early development. Nothing to install yet.

The machine is coming. ⚙️

## Requirements

- macOS 14 or later, on Apple silicon
- Xcode 26 or 27, with at least one iOS simulator runtime installed

Apple silicon only, and not by preference: the simulator frameworks this app loads from Xcode ship
as `arm64e` with no Intel slice, so an Intel build would launch and then fail at the first
framework load.

## Building

```sh
scripts/build.sh              # the executables
scripts/build-app.sh release  # build/OpenDeviceHub.app
```

Use `scripts/build.sh` rather than calling `swift build` directly. SwiftPM records the deployment
target as the linked SDK version, and AppKit then gives the window its pre macOS 26 toolbar
appearance.

A build from source is marked as a development build: it reports version `0.0.0-dev` and, once
in-app updates land, never talks to the release channel.

## The odhub command

The app bundle carries the `odhub` command line tool beside it. To use it from a terminal, add it
to your `PATH`:

```sh
echo 'export PATH="/Applications/OpenDeviceHub.app/Contents/MacOS:$PATH"' >> ~/.zshrc
```

Then `odhub doctor` reports what it found, and `odhub list` shows the simulators.

## License

MIT