# Releasing

For maintainers. Nothing here contains a credential; the values live outside this repository and
reach the workflow as repository secrets.

## Two values that must never change

| Value | Why |
|---|---|
| The bundle identifier | A new one makes macOS treat the app as a different one, orphaning every installed copy. |
| The update feed URL | The installed app keeps asking the old URL. Changing it silently ends updates for everyone, with no way to push a fix. |

Both are based on a GitHub handle rather than the product name or a domain, so the app can be
renamed and the repository moved without touching either. The feed itself lives in a separate
repository served by GitHub Pages; the enclosure URLs inside it point at this repository's release
downloads and are rewritten on every release.

## Before the first release on a new machine

- A **Developer ID Application** certificate in the login keychain. Not Apple Development, which
  notarization rejects.
- An App Store Connect **Team** API key with the Developer role. An **Individual** key does not work
  with `notarytool`, and the failure only shows up at submission.
- The Sparkle update key pair. The public half is compiled into the app; the private half signs the
  feed.

**If the update private key is lost, no installed copy can ever be updated again.** A later release
cannot fix it, because the installed app only trusts the public key baked into the copy someone
already has. Keep it in a password manager as well as in the repository secret.

## Repository secrets

| Secret | Contents |
|---|---|
| `DEVELOPER_ID_IDENTITY` | the full identity string, `Developer ID Application: Name (TEAMID)` |
| `DEVELOPER_ID_P12` | that identity exported as a `.p12`, base64 encoded |
| `DEVELOPER_ID_P12_PASSWORD` | the password used for that export |
| `ASC_KEY_ID` | App Store Connect key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_KEY_P8` | the contents of the `.p8` private key |
| `SPARKLE_PRIVATE_KEY` | the update signing private key |

A missing secret fails the run loudly on its first step. Signing is never skipped quietly, because an
unsigned build that reaches a release page is worse than a run that stops.

## Making a release

1. Add the version's section to `CHANGELOG.md`. The release notes on GitHub and the notes inside the
   update feed both come from it, so they cannot drift apart.
2. Update `VERSION`.
3. Run the **Release** workflow from the Actions tab with `publish` left **false**. That is a dry
   run: it builds, signs, notarizes, staples, packages, checksums and generates the feed, and
   creates no tag, no release and no commit anywhere. The artifacts are attached to the run under a
   short retention name so you can download and check them.
4. Install the dry run's DMG and use it. `stapler validate` on the app and on the DMG, and
   `shasum -c SHA256SUMS` from a different directory.
5. Run the workflow again with `publish` **true**. It creates the tag and a pre-release with the DMG
   and `SHA256SUMS`.
6. **Only once that release page exists**, commit the generated `appcast.xml` to the feed
   repository. A feed pointing at a download that is not there yet breaks updates for everyone who
   reads it in the meantime.
7. Confirm an already installed older copy finds the update, verifies it and installs it, ending on
   the new version. Do this before announcing anything: a broken updater cannot be fixed by a later
   release.

Everything the workflow runs is a script in `scripts/`, and each one works on its own from a
terminal. The workflow wraps them; it does not reimplement them.

### The order that matters

Two steps fail silently if they are done in the wrong order, and both are wired that way on purpose:

- **Sign inside out.** Sparkle's nested XPC services, then `Autoupdate`, then `Updater.app`, then the
  framework, then the bundled command, then the app. `--deep` is for verification only, never for
  signing.
- **Sign the update last.** The feed signature covers the exact bytes of the file people download, so
  it is taken after notarizing, stapling and packaging. Anything that rewrites the artifact
  afterwards leaves a signature that no longer matches, and Sparkle then refuses the update without
  telling anyone. `scripts/appcast.sh` refuses to sign an artifact that is not stapled, and checks
  the byte length it writes against the file on disk.

## Reading a notarization log

The log is fetched and saved on every submission, including successful ones, under
`build/notarization/`. `notarytool submit` reports `Accepted`, `Invalid` or `Rejected`; for anything
but `Accepted`, the log is the only thing that says why.

```sh
xcrun notarytool log <submission-id> \
  --key <p8> --key-id <key-id> --issuer <issuer-id>
```

It is JSON. `issues` is the part that matters, and each entry names a `path` inside the bundle, a
`severity` and a `message`. The usual ones:

| Message | What it means |
|---|---|
| `The signature of the binary is invalid` | Something was modified after signing, or signed in the wrong order. |
| `The executable does not have the hardened runtime enabled` | A nested binary was missed. Check each one on its own, not with `--deep`. |
| `The signature does not include a secure timestamp` | Signed without `--timestamp`, usually offline. |
| `The binary is not signed with a valid Developer ID certificate` | An Apple Development identity was used. |

`status: Accepted` with a non-empty `issues` list is possible and is worth reading: those are
warnings that become failures in a later macOS.

## When a release fails midway

Nothing before the publish step changes anything outside the runner, so a failure there costs
nothing: fix it and run the dry run again.

After that, work backwards from how far it got.

**The tag and release exist, but the artifacts are wrong.** Delete the release and the tag, then run
again. Do this only if nobody can have downloaded it yet, and never once the feed points at it.

```sh
gh release delete v<version> --yes
git push --delete origin v<version>
```

**The release is published and the feed is not updated yet.** Nothing is broken. Either finish by
committing the feed, or leave it: people who downloaded the DMG have a working app, and no installed
copy is looking for that version.

**The feed points at a release that is wrong or gone.** This is the one that hurts, because installed
copies are reading it. Revert the feed repository to its previous commit first, which stops the
damage, then fix the release. Do not delete the release while the feed still points at it.

**Notarization is stuck in progress.** Submissions can take minutes or hours. `notarytool history`
shows where it is. Do not resubmit: a second submission of the same bytes gets a second ticket and
tells you nothing new.

**The published version is broken for everyone.** Release a fixed version rather than trying to undo
one. Mark the bad release as a pre-release or delete it so nobody new downloads it, publish the fix,
and update the feed. Installed copies will update themselves. Never reuse a version number: Sparkle
compares build numbers, and a copy that has already seen that number will not offer it again.

## The runner

The release runs on a pinned runner image and asks for a preferred Xcode major, falling back to the
newest installed Xcode with a macOS SDK of 26.0 or newer. Both are workflow inputs, so a runner image
that changes or is withdrawn can be worked around by dispatching with a different one rather than
editing a file under time pressure.

The SDK floor is the real requirement. The linked SDK decides whether AppKit gives the app its
current appearance or its pre macOS 26 one, and an older SDK builds, signs and notarizes perfectly
while shipping a window that looks years out of date. Every run prints each Xcode on the runner with
its SDK version and records the one it chose, so what shipped is never a matter of inference.
