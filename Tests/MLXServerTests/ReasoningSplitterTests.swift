import Testing

@testable import MLXServerKit

@Suite("ReasoningSplitter")
struct ReasoningSplitterTests {
    /// Feed all chunks through a splitter, then flush; return the accumulated split.
    private func run(mode: ReasoningMode, _ chunks: [String]) -> ReasoningSplitter.Split {
        var splitter = ReasoningSplitter(mode: mode)
        var accumulated = ReasoningSplitter.Split()
        for chunk in chunks {
            let split = splitter.push(chunk)
            accumulated.reasoning += split.reasoning
            accumulated.content += split.content
        }
        let tail = splitter.flush()
        accumulated.reasoning += tail.reasoning
        accumulated.content += tail.content
        return accumulated
    }

    @Test("auto mode splits a <think> block from the answer")
    func autoSplit() {
        let result = run(mode: .auto, ["<think>reasoning here</think>the answer"])
        #expect(result.reasoning == "reasoning here")
        #expect(result.content == "the answer")
    }

    @Test("auto mode passes plain output through as content")
    func autoNoMarkers() {
        let result = run(mode: .auto, ["just a plain answer"])
        #expect(result.reasoning == "")
        #expect(result.content == "just a plain answer")
    }

    @Test("prefilled mode treats leading text as reasoning until </think>")
    func prefilledSplit() {
        let result = run(mode: .prefilled, ["thinking out loud</think>final answer"])
        #expect(result.reasoning == "thinking out loud")
        #expect(result.content == "final answer")
    }

    @Test("off mode keeps everything as content")
    func offMode() {
        let result = run(mode: .off, ["<think>x</think>y"])
        #expect(result.reasoning == "")
        #expect(result.content == "<think>x</think>y")
    }

    @Test("a closing marker split across chunk boundaries is reassembled")
    func partialCloseMarker() {
        let result = run(mode: .prefilled, ["abc</thi", "nk>def"])
        #expect(result.reasoning == "abc")
        #expect(result.content == "def")
    }

    @Test("an opening marker split across chunk boundaries is reassembled")
    func partialOpenMarker() {
        let result = run(mode: .auto, ["<thi", "nk>r</think>c"])
        #expect(result.reasoning == "r")
        #expect(result.content == "c")
    }

    @Test("token-by-token streaming classifies each phase correctly")
    func tokenByToken() {
        let tokens = ["<", "think", ">", "deep ", "thoughts", "</think>", "the ", "answer"]
        let result = run(mode: .auto, tokens)
        #expect(result.reasoning == "deep thoughts")
        #expect(result.content == "the answer")
    }

    @Test("flush emits a held-back partial marker that never completed")
    func flushIncompletePartial() {
        let result = run(mode: .prefilled, ["reasoning</thi"])
        #expect(result.reasoning == "reasoning</thi")
        #expect(result.content == "")
    }
}
