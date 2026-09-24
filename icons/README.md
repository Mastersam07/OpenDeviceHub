# Icons

Every file here is generated, not hand drawn. `packaging/make-icon.swift` is the source:

```sh
xcrun swiftc -O -o /tmp/make-icon packaging/make-icon.swift
/tmp/make-icon icons --marketing   # the PNGs below
/tmp/make-icon icons --social      # social-preview.png
```

The app's own `.icns` is built from the same file by `scripts/build-app.sh`, so the icon on disk and
the icon in the app can never disagree.

| File | Use it for |
| --- | --- |
| `icon-16.png` to `icon-48.png` | favicons |
| `icon-128.png`, `icon-180.png`, `icon-256.png` | a README header, docs, a touch icon |
| `icon-512.png`, `icon-1024.png` | store listings, anything print or retina |
| `icon-square-400.png`, `-512.png`, `-1024.png` | avatars: GitHub, X, Discord, anywhere the picture is cropped |
| `social-preview.png` | GitHub's repository social preview, 1280x640 |
| `icon.svg` | vector, for any size that is not here |

The square files fill the frame instead of rounding their own corners, because an avatar is cropped
again by whoever shows it, and a picture that rounds itself first loses a ring of artwork to the
second rounding. Everywhere else, use the rounded ones.

The SVG is a close copy rather than an exact one: its gradient renders slightly lighter than the
PNGs, which are what the app ships. Where the two would sit side by side, use a PNG.
