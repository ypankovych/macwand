import Foundation

/// One line of the engine's JSON-lines output. Fields are optional because
/// each event `type` uses a different subset (see engine/src/events.rs).
struct EngineEvent: Decodable {
    let type: String
    let path: String?
    let size: Int64?
    let modified: Int64?
    let files: Int64?
    let bytes: Int64?
    let errors: Int64?
    let elapsedMs: Int64?
    let current: String?
    let id: String?
    let name: String?
    let description: String?
    let safety: String?
    let category: String?
    let label: String?
}

/// Runs the bundled `macwand-engine` helper and streams its events.
struct EngineClient {
    enum Failure: LocalizedError {
        case missingEngine
        case exited(Int32)

        var errorDescription: String? {
            switch self {
            case .missingEngine: "The scanning engine is missing from the app bundle."
            case .exited(let code): "The scanning engine stopped unexpectedly (exit code \(code))."
            }
        }
    }

    /// Location of the helper: next to the app executable in Contents/MacOS.
    let executableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "macwand-engine")

    /// Starts a full scan of the home folder and installed apps.
    func scan() -> AsyncThrowingStream<[EngineEvent], Error> {
        run(["scan"])
    }

    /// Sizes the given paths.
    func sizes(of paths: [String]) -> AsyncThrowingStream<[EngineEvent], Error> {
        run(["sizes"] + paths)
    }

    /// Launches the engine and yields events in batches as the engine flushes them.
    /// Cancelling the consuming task terminates the engine.
    private func run(_ arguments: [String]) -> AsyncThrowingStream<[EngineEvent], Error> {
        AsyncThrowingStream { continuation in
            guard let executableURL else {
                continuation.finish(throwing: Failure.missingEngine)
                return
            }
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            let reader = LineReader()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // EOF: every event has been read, so finish from here rather than
                    // from terminationHandler, which can fire before the pipe drains.
                    handle.readabilityHandler = nil
                    process.waitUntilExit()
                    let failed = process.terminationReason == .exit && process.terminationStatus != 0
                    continuation.finish(throwing: failed ? Failure.exited(process.terminationStatus) : nil)
                    return
                }
                let events = reader.consume(chunk)
                if !events.isEmpty { continuation.yield(events) }
            }
            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }
}

/// Splits a byte stream into newline-terminated JSON events, keeping partial lines.
/// Only touched from the pipe's serial readability handler.
private final class LineReader {
    private var pending = Data()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func consume(_ chunk: Data) -> [EngineEvent] {
        pending.append(chunk)
        guard let lastNewline = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[..<lastNewline]
        let events = complete
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(EngineEvent.self, from: Data($0)) }
        pending = Data(pending[pending.index(after: lastNewline)...])
        return events
    }
}
