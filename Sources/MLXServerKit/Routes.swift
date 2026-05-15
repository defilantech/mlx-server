import Foundation
import Hummingbird

/// Register all HTTP routes on the router.
func registerRoutes(router: Router<BasicRequestContext>, engine: some Inferencing) {
    // Liveness smoke endpoint.
    router.get("/health") { _, _ -> String in
        "ok"
    }

    // OpenAI model list — reports the single loaded model.
    router.get("/v1/models") { _, _ -> ModelListResponse in
        ModelListResponse(data: [
            ModelObject(id: engine.modelID, created: Int(Date().timeIntervalSince1970))
        ])
    }

    // OpenAI chat completions.
    router.post("/v1/chat/completions") { request, context -> Response in
        try await ChatCompletionsHandler.handle(request: request, context: context, engine: engine)
    }
}
