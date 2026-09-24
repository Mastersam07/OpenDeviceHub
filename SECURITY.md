# Security

## Reporting something

Open a
[private advisory](https://github.com/Mastersam07/OpenDeviceHub/security/advisories/new). Please do
not open a public issue for a vulnerability.

Expect an acknowledgement within a week. There is no bounty; there is credit in the advisory and in
the release notes, unless you would rather not be named.

## What this app does to your machine

Worth knowing, because it is unusual for an app to touch these things at all.

**It loads private Apple frameworks from your Xcode.** `CoreSimulator`, `CoreSimDeviceIO` and
`SimulatorKit` are opened with `dlopen` at runtime from the Xcode already installed on your Mac.
Nothing is linked at build time and no Apple framework, simulator runtime or device bezel asset is
bundled or redistributed. If a class or selector is missing on your Xcode, the app reports a missing
capability rather than crashing.

**Every private call is checked first.** Classes are looked up by name and selectors through
`respondsToSelector:` before use, and everything crossing that boundary is treated as possibly nil.
Private API access is confined to two directories, `engine/Sources/OpenDeviceHubPrivate` and
`engine/Sources/OpenDeviceHubEngine/Adapter`; no other file may touch a private symbol.

**It can drive your simulators.** Taps, keystrokes and hardware buttons go to simulators on your
machine, from the app and from the `odhub` command. It does not touch physical devices.

**It can write outside its own bundle**, in exactly two places, both of which you ask for:
screenshots and recordings go to your Desktop, and **Install Command Line Tool** creates one symlink
in a directory on your `PATH`. That one asks for an administrator password only when every such
directory belongs to the system, and it explains why before macOS asks. **Remove Command Line Tool**
deletes it.

**It talks to the network for one thing only**: checking for updates. There is no analytics, no
crash reporting and no telemetry of any kind. A build from source has no update channel at all, so
it never makes a network request.

## How releases are protected

- **Signed and notarized.** Release builds are signed with a Developer ID Application certificate,
  use the hardened runtime, and are notarized and stapled by Apple. The staple means the ticket
  travels with the download, so it verifies with no network.
- **No entitlements.** The hardened runtime is enabled with none of the exceptions to it, library
  validation included. Loading Xcode's frameworks was tested and needs none.
- **Checksums.** Every release lists `SHA256SUMS` generated from the final signed, notarized and
  stapled artifacts, verifiable with `shasum -c`.
- **Signed updates.** The update feed is signed with an EdDSA key whose public half is compiled into
  the app. An installed copy only accepts an update that verifies against the key it already has, so
  a compromised feed cannot push a build to anyone.
- **Reproducible from source.** The release workflow is in this repository and the scripts it runs
  are the same ones used by hand.

## Credentials

No credential, key or certificate is in this repository. The signing certificate, the App Store
Connect key and the update signing key live outside it and reach the release workflow as repository
secrets.

If the update signing key were ever lost or exposed, it cannot be fixed by a later release: every
installed copy only trusts the key baked into it. That is why it is backed up outside this machine
and why its handling is treated as the most sensitive part of the release.
