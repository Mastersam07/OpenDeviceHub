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

### Siniulator

Copyright (c) Krzysztof Magiera. Licensed under the MIT license.
https://github.com/kmagiera/Siniulator

The same message layout was cross checked against Siniulator's
`Sources/SimulatorBridge/SimulatorBridge.m`, which arrived at the same envelope independently.

The device toolbar in `engine/Sources/OpenDeviceHubViewer/DeviceToolbar.swift` follows
Siniulator's `SimulatorToolbar`: the shortcut in each tooltip, Option on the rotate button turning
the device the other way, and the screenshot button becoming a stop button while a recording runs.

## Dependencies

### swift-argument-parser

Copyright (c) 2020 Apple Inc. and the Swift project authors.
Licensed under the Apache License, Version 2.0.
https://github.com/apple/swift-argument-parser
