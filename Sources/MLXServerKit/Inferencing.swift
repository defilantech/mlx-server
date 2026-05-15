/// The inference surface the HTTP layer depends on.
///
/// `InferenceEngine` is the production implementation; tests substitute a
/// lightweight stub so routes can be exercised without loading a model.
protocol Inferencing: Sendable {
    /// Model id reported by `/v1/models`.
    var modelID: String { get }
    /// Run a non-streaming completion.
    func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    /// Run a streaming completion, yielding events as they arrive.
    func stream(_ request: ChatCompletionRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

extension InferenceEngine: Inferencing {}
