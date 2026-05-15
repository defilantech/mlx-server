import Hummingbird

// Hummingbird response conformances for the OpenAI JSON types. Kept separate
// so OpenAITypes.swift stays free of the HTTP framework.
extension ModelListResponse: ResponseEncodable {}
extension ChatCompletionResponse: ResponseEncodable {}
