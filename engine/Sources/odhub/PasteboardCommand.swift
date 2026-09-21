import ArgumentParser
import Foundation
import OpenDeviceHubEngine

struct Paste: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "paste",
        abstract: "Put text on a simulator's pasteboard, reading standard input when no text is given."
    )

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    @Argument(help: "The text to place. Standard input is used when this is omitted.")
    var text: String?

    func run() throws {
        let value: String
        if let text {
            value = text
        } else {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            value = String(decoding: data, as: UTF8.self)
        }
        try SimctlService().pasteboardCopy(value, udid: udid)
        print("copied \(value.count) characters to the device pasteboard")
    }
}

struct Copy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Print a simulator's pasteboard contents."
    )

    @Argument(help: "The UDID of the simulator.")
    var udid: String

    func run() throws {
        print(try SimctlService().pasteboardPaste(udid: udid), terminator: "")
    }
}
