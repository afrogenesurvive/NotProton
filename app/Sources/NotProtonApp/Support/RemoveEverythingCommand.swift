import Foundation

enum RemoveEverythingCommand {
    static let flag = "--remove-everything"

    static func run() -> Never {
        Task.detached { exit(await perform()) }
        dispatchMain()
    }

    private static func perform() async -> Int32 {
        do {
            let lock = try DeploymentContent.acquireInstallationLock(for: SupportPaths.Steam.app)
            defer { close(lock) }
            let output = Output()
            let result = try await Uninstall.run { phase in
                if case .restoring(.finished) = phase { return }
                output.say(phase.label)
            }
            output.say(
                result.restoredValveSignature
                    ? "NotProton has been removed."
                    : "NotProton has been removed. Steam needs to be redownloaded. "
                        + "Please run Repair Steam again once you are online."
            )
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var last: String?

        func say(_ line: String) {
            lock.withLock {
                guard line != last else { return }
                last = line
                FileHandle.standardOutput.write(Data("\(line)\n".utf8))
            }
        }
    }
}
