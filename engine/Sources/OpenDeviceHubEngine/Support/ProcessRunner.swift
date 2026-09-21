import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessRunner {
    static func run(
        _ executable: String,
        _ arguments: [String],
        standardInput: String? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let input = Pipe()
        if standardInput != nil {
            process.standardInput = input
        }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        if let standardInput {
            input.fileHandleForWriting.write(Data(standardInput.utf8))
            try? input.fileHandleForWriting.close()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}
