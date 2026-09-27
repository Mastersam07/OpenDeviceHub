# Third party notices

OpenDeviceHub is released under the MIT license (see `LICENSE`).

## Adapted code

### idb / FBSimulatorControl

Copyright (c) Meta Platforms, Inc. and affiliates. Licensed under the MIT license.
https://github.com/facebook/idb

The Indigo single touch message layout in
`engine/Sources/OpenDeviceHubEngine/Adapter/IndigoHID.swift` and
`engine/Sources/OpenDeviceHubEngine/Adapter/LegacyHIDInputSession.swift` is adapted from idb's
`PrivateHeaders/SimulatorApp/Indigo.h` and `FBSimulatorControl/HID/SimulatorIndigoHID.swift`.

The hardware button constants in `IndigoHID.swift` come from the same header:

| Ours | idb |
|---|---|
| `Button.eventSources`, home `0`, lock `1`, siri `0x400002` | `ButtonEventSourceHomeButton`, `ButtonEventSourceLock`, `ButtonEventSourceSiri` |
| `buttonTarget` `0x33` | `ButtonEventTargetHardware` |
| `touchTarget` `0x32`, the target an arbitrary HID usage must go to | `ButtonEventTargetDigitizer` |
| `buttonDown` `1`, `buttonUp` `2` | `ButtonEventTypeDown`, `ButtonEventTypeUp` |
| `Button.consumerUsages`, volume up `0xe9`, volume down `0xea` | the Consumer page table |
| `edgeValue`, none `0`, top `1`, left `2`, bottom `3`, right `4` | `IndigoHIDEdgeNone` through `IndigoHIDEdgeRight` |

The eventMask bits idb documents for each edge, and its observation that the guest recognises a
system edge gesture from those bits, were measured on a device rather than taken on trust. Only the bottom
value was found to change behaviour on Xcode 26.5.

### Siniulator

Copyright (c) Krzysztof Magiera. Licensed under the MIT license.
https://github.com/kmagiera/Siniulator

The same message layout was cross checked against Siniulator's
`Sources/SimulatorBridge/SimulatorBridge.m`, which arrived at the same envelope independently. The
argument order that makes the button builder work, `(source, direction, target)` rather than the
order its name suggests, was read from the same file.

`engine/Sources/OpenDeviceHubEngine/Adapter/WorkspaceOrientation.swift` is adapted from
Siniulator's `rotateUsingPurple`: the `PurpleWorkspacePort` lookup, the 112 byte buffer carrying a
108 byte message, the offsets `0`, `4`, `8`, `20`, `0x18`, `0x48` and `0x4c`, the values `0x13`,
`108`, `0x7b`, `50 | 0x20000` and `4`, and the two second send timeout. Siniulator credits idb for
the underlying Purple GSEvent protocol.

The device toolbar in `engine/Sources/OpenDeviceHubViewer/DeviceToolbar.swift` follows
Siniulator's `SimulatorToolbar`: the shortcut in each tooltip, Option on the rotate button turning
the device the other way, and the screenshot button becoming a stop button while a recording runs.

`engine/Sources/OpenDeviceHubEngine/Input/HingeMove.swift` is adapted from Siniulator's
`DuoHingeAnimation`: a fold to a preset takes between 0.35 and 1 second by the distance moved, and
follows a quintic ease in and out, with one clock driving the guest's hinge and the model.

## Dependencies

### swift-argument-parser

Copyright (c) 2020 Apple Inc. and the Swift project authors.
Licensed under the Apache License, Version 2.0.
https://github.com/apple/swift-argument-parser

### create-dmg

Copyright (c) Sindre Sorhus. Licensed under the MIT license.
https://github.com/sindresorhus/create-dmg

The release disk image is made with create-dmg 8.1.0 when it is packaged, and nothing from it is
kept in this repository. Its window background and layout ship inside every disk image. The disk
icon is macOS's removable drive icon, as create-dmg carries it, with the app's icon drawn on top.
