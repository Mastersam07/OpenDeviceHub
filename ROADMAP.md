# Roadmap

What is being worked towards, roughly in the order it is likely to happen. Nothing here is a promise
or a date, and anything can move. The README's **Current limitations** is the honest list of what is
missing today; this is where that list is going.

If you want something sooner, say so in an issue. A feature two people ask for beats one nobody has
mentioned.

## Bringing back what went missing

Things the classic Simulator had, or that a simulator should simply be able to do.

- **Location** — presets, a search, GPX routes, and per-project saved places.
- **Push notifications** — send a payload to an app, with a saved library of them and templates for
  the fiddly parts.
- **Biometrics** — enrol, match and fail a match for Face ID and Touch ID.
- **Device and runtime management** — create, rename, erase and delete simulators, and install
  runtimes, without going back to Xcode.
- **Proxy certificates** — drop a `.cer` onto a device, or install a debugging proxy's root
  certificate on every booted device at once. Removed from Device Hub, and badly missed by anyone
  who inspects traffic for a living.
- **Status bar presets** — 9:41, full battery, full signal, for clean App Store screenshots.
- **Locale, region and Dynamic Type** — switch them without digging through Settings.
- **Privacy permissions** — grant, revoke and reset per app, so the first-run flow can be tested more
  than once.

## Tooling for the app you are actually building

The reason this project exists, and none of it is built yet. The theme is everything a mobile
developer scripts by hand today, one click away, remembered per project.

- **Project awareness** — point it at a project and it learns the bundle identifiers, flavours and
  entry points, then remembers your deep links, payloads, proxy settings and favourite devices
  alongside them.
- **Run, hot reload and hot restart** — on any device, flavour aware, from the device window.
- **DevTools** — a link on the window once the app is attached, and attaching to an app that is
  already running.
- **Deep links** — saved per app, custom schemes and universal links, one click to fire.
- **Screenshot sets** — the same screen captured across several devices in one action, named and
  organised for the App Store.

## Harder, or not yet certain

Listed separately because the honest answer is that these might not work, or might not be worth what
they cost.

- **iPad pointer and mouse input** — the hardest item here, and the one most likely to slip.
- **Network conditioning presets** — 3G, lossy, offline. Apple's own conditioner is system wide on
  macOS rather than per simulator, so either a per-device approach turns up or this gets documented
  as the compromise it is.
- **Audio routing and external displays** — wanted, not investigated.
- **Android emulators in the same window** — cross platform developers juggle both all day. Genuinely
  useful, a long way out, and not started.

## Not planned

- **tvOS, watchOS and visionOS.** Not out of dislike; the device shapes, input model and chrome are
  a different project's worth of work, and doing them badly would be worse than not doing them.
- **Physical devices.** This is a simulator tool. Xcode and Device Hub handle hardware.
- **Anything that phones home.** No analytics, no crash reporting, no telemetry, now or later.
