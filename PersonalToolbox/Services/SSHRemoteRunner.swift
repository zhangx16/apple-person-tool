import Foundation
import Citadel
import NIOCore

/// Runs non-interactive SSH commands via Citadel (SwiftNIO SSH).
/// Full interactive PTY terminal is out of scope for now.
enum SSHRemoteRunner {
    struct RunResult: Sendable {
        var exitOK: Bool
        var output: String
        var errorText: String?
    }

    /// Connect with password auth and execute one command (stdout; stderr appended on failure).
    static func run(
        host: String,
        port: Int,
        username: String,
        password: String,
        command: String,
        maxBytes: Int = 512_000
    ) async throws -> RunResult {
        let settings = SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: {
                .passwordBased(username: username, password: password)
            },
            // Prefer proper host-key pinning later; acceptAnything is OK for personal toolbox v1.
            hostKeyValidator: .acceptAnything()
        )

        let client = try await SSHClient.connect(to: settings)
        defer {
            Task {
                try? await client.close()
            }
        }

        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: maxBytes)
            return RunResult(exitOK: true, output: bufferString(buffer), errorText: nil)
        } catch let failed as SSHClient.CommandFailed {
            return RunResult(
                exitOK: false,
                output: "",
                errorText: "命令退出码 \(failed.exitCode)"
            )
        } catch {
            // stderr-only failures / Citadel errors — show description
            let desc = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return RunResult(exitOK: false, output: "", errorText: desc)
        }
    }

    private static func bufferString(_ buffer: ByteBuffer) -> String {
        var buf = buffer
        return buf.readString(length: buf.readableBytes) ?? ""
    }
}
