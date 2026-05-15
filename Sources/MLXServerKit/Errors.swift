import Foundation

/// Errors surfaced by the server, each carrying an OpenAI-style error `type`.
public enum ServerError: Error, Sendable {
    /// Model weights or tokenizer failed to load at startup.
    case modelLoadFailed(String)
    /// Inference failed while generating a completion.
    case inferenceFailed(String)
    /// The request was malformed or semantically invalid.
    case badRequest(String)
    /// A request parameter is recognized but not yet supported.
    case unsupportedParameter(String)

    /// Human-readable message for the error body.
    public var message: String {
        switch self {
        case .modelLoadFailed(let detail): "Model load failed: \(detail)"
        case .inferenceFailed(let detail): "Inference failed: \(detail)"
        case .badRequest(let detail): detail
        case .unsupportedParameter(let detail): "Unsupported parameter: \(detail)"
        }
    }

    /// OpenAI error `type` discriminator.
    public var type: String {
        switch self {
        case .modelLoadFailed, .inferenceFailed: "server_error"
        case .badRequest: "invalid_request_error"
        case .unsupportedParameter: "invalid_request_error"
        }
    }
}

/// OpenAI error envelope: `{ "error": { message, type, param?, code? } }`.
public struct OpenAIErrorResponse: Encodable, Sendable {
    public struct Body: Encodable, Sendable {
        public var message: String
        public var type: String
        public var param: String?
        public var code: String?
    }

    public var error: Body

    public init(message: String, type: String, param: String? = nil, code: String? = nil) {
        self.error = Body(message: message, type: type, param: param, code: code)
    }

    public init(_ error: ServerError) {
        self.init(message: error.message, type: error.type)
    }
}
