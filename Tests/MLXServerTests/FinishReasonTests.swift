import Testing

@testable import MLXServerKit

@Suite("finishReason")
struct FinishReasonTests {
    @Test("tool calls take precedence over everything else")
    func toolCalls() {
        #expect(
            InferenceEngine.finishReason(
                hasToolCalls: true, generatedTokens: 999, maxTokens: 10) == "tool_calls")
    }

    @Test("output truncated at the token limit reports length")
    func length() {
        #expect(
            InferenceEngine.finishReason(
                hasToolCalls: false, generatedTokens: 512, maxTokens: 512) == "length")
        #expect(
            InferenceEngine.finishReason(
                hasToolCalls: false, generatedTokens: 600, maxTokens: 512) == "length")
    }

    @Test("a natural stop reports stop")
    func stop() {
        #expect(
            InferenceEngine.finishReason(
                hasToolCalls: false, generatedTokens: 40, maxTokens: 512) == "stop")
        #expect(
            InferenceEngine.finishReason(
                hasToolCalls: false, generatedTokens: 40, maxTokens: nil) == "stop")
    }
}
