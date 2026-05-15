import Foundation
import Hummingbird

/// Server-Sent Events framing for streamed chat completions.
///
/// Each event is `data: <json>\n\n`; the stream terminates with
/// `data: [DONE]\n\n` per the OpenAI streaming convention.
enum SSE {
    /// The terminating `[DONE]` line.
    static let doneLine = "data: [DONE]\n\n"

    /// Wrap an already-encoded JSON payload in a `data:` frame.
    static func dataLine(_ json: String) -> String {
        "data: \(json)\n\n"
    }

    /// Encode an event payload as a `data:` frame buffer.
    static func event(_ value: some Encodable) throws -> ByteBuffer {
        let data = try JSONEncoder().encode(value)
        let json = String(decoding: data, as: UTF8.self)
        return ByteBuffer(string: dataLine(json))
    }

    /// The terminating `[DONE]` frame buffer.
    static func done() -> ByteBuffer {
        ByteBuffer(string: doneLine)
    }
}
