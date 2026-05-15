import Testing

@testable import MLXServerKit

@Suite("ServerConfig")
struct ServerConfigTests {
    @Test("stores the values it is constructed with")
    func storesValues() {
        let config = ServerConfig(
            model: "/models/Qwen3-4B-4bit",
            host: "0.0.0.0",
            port: 8080,
            maxSlots: 4
        )

        #expect(config.model == "/models/Qwen3-4B-4bit")
        #expect(config.host == "0.0.0.0")
        #expect(config.port == 8080)
        #expect(config.maxSlots == 4)
        #expect(config.toolCallFormat == nil)
    }
}
