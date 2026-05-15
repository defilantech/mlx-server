import Foundation
import MLXLMCommon
import Testing

@testable import MLXServerKit

@Suite("ChatMapping")
struct ChatMappingTests {
    @Test("maps OpenAI roles to Chat.Message roles")
    func toChatMessages() {
        let mapped = ChatMapping.toChatMessages([
            ChatMessage(role: "system", content: .text("sys")),
            ChatMessage(role: "user", content: .text("hello")),
            ChatMessage(role: "assistant", content: .text("hi")),
        ])

        #expect(mapped.count == 3)
        #expect(mapped[0].role == .system)
        #expect(mapped[1].role == .user)
        #expect(mapped[1].content == "hello")
        #expect(mapped[2].role == .assistant)
    }

    @Test("unknown role falls back to user")
    func unknownRole() {
        let mapped = ChatMapping.toChatMessages([ChatMessage(role: "weird", content: .text("x"))])
        #expect(mapped[0].role == .user)
    }

    @Test("converts tool definitions to ToolSpec dictionaries")
    func toToolSpecs() {
        let tools = [
            ToolDefinition(
                function: FunctionSchema(
                    name: "get_weather",
                    description: "look up weather",
                    parameters: .object(["type": .string("object")])
                )
            )
        ]
        let specs = ChatMapping.toToolSpecs(tools)

        #expect(specs?.count == 1)
        #expect(specs?.first?["type"] as? String == "function")
        let function = specs?.first?["function"] as? [String: any Sendable]
        #expect(function?["name"] as? String == "get_weather")
        #expect(function?["description"] as? String == "look up weather")
    }

    @Test("absent or empty tools yield nil")
    func emptyTools() {
        #expect(ChatMapping.toToolSpecs(nil) == nil)
        #expect(ChatMapping.toToolSpecs([]) == nil)
    }

    @Test("resolveGenerateParameters applies values and clamps max_tokens")
    func generateParameters() {
        let applied = ChatMapping.resolveGenerateParameters(
            ChatCompletionRequest(model: "m", messages: [], temperature: 0.3, topP: 0.8, maxTokens: 100)
        )
        #expect(applied.temperature == Float(0.3))
        #expect(applied.topP == Float(0.8))
        #expect(applied.maxTokens == 100)

        let huge = ChatMapping.resolveGenerateParameters(
            ChatCompletionRequest(model: "m", messages: [], maxTokens: 9_000_000)
        )
        #expect(huge.maxTokens == ChatMapping.maxTokensCeiling)

        let defaulted = ChatMapping.resolveGenerateParameters(
            ChatCompletionRequest(model: "m", messages: [])
        )
        #expect(defaulted.maxTokens == ChatMapping.defaultMaxTokens)
    }

    @Test("argumentsJSONString produces valid JSON")
    func argumentsJSON() throws {
        let arguments: [String: JSONValue] = ["city": .string("Paris"), "days": .int(3)]
        let string = ChatMapping.argumentsJSONString(arguments)

        let parsed = try JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any]
        #expect(parsed?["city"] as? String == "Paris")
        #expect(parsed?["days"] as? Int == 3)
    }
}
