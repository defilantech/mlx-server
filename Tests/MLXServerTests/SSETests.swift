import Testing

@testable import MLXServerKit

@Suite("SSE")
struct SSETests {
    @Test("dataLine frames a payload as data: <json>\\n\\n")
    func dataLineFraming() {
        let line = SSE.dataLine(#"{"hello":"world"}"#)
        #expect(line == "data: {\"hello\":\"world\"}\n\n")
    }

    @Test("doneLine is the OpenAI stream terminator")
    func doneTerminator() {
        #expect(SSE.doneLine == "data: [DONE]\n\n")
    }
}
