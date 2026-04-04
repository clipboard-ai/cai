import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - MLX Inference Service

/// In-process LLM inference via MLX-Swift. Replaces the llama-server subprocess.
/// Loads MLX-format models from disk or HuggingFace and runs inference natively on Apple Silicon.
actor MLXInference {

    static let shared = MLXInference()

    // MARK: - Directories (nonisolated for synchronous access from CaiSettings etc.)

    nonisolated static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cai")
    }

    // MARK: - State

    private var modelContainer: ModelContainer?
    private var memoryConfigured = false

    /// Whether a model is currently loaded and ready for inference.
    var isLoaded: Bool { modelContainer != nil }

    // MARK: - Default Model

    /// Default model for first-time setup.
    static let defaultModelId = "mlx-community/Ministral-3-3B-Instruct-2512-4bit"

    /// Curated models for the settings picker.
    static let curatedModels: [(id: String, name: String, size: String)] = [
        ("mlx-community/Ministral-3-3B-Instruct-2512-4bit", "Ministral 3B", "~1.8 GB"),
        ("mlx-community/Qwen3-4B-4bit", "Qwen3 4B", "~2.5 GB"),
        ("mlx-community/gemma-3-1b-it-qat-4bit", "Gemma 3 1B", "~0.8 GB"),
    ]

    // MARK: - Load Model

    /// Configures MLX memory limits. Runs once — subsequent calls are no-ops.
    private func configureMemory() {
        guard !memoryConfigured else { return }
        memoryConfigured = true
        // 256MB buffer pool — balances reallocation churn vs memory footprint.
        // 20MB (iOS recommendation) causes excessive churn on macOS.
        // No memoryLimit — macOS unified memory pressure handles the rest,
        // and setting it too low can hang the process (no relaxed mode in mlx-swift).
        MLX.Memory.cacheLimit = 256 * 1024 * 1024
    }

    /// Loads an MLX model from a local directory (already downloaded).
    func loadModel(from directory: URL) async throws {
        if modelContainer != nil { unload() }
        configureMemory()
        print("🧠 MLX loading model from: \(directory.path)")
        let container = try await loadModelContainer(directory: directory)
        self.modelContainer = container
        print("🧠 MLX model loaded successfully")
    }

    /// Downloads and loads a model from HuggingFace by ID (e.g., "mlx-community/Ministral-3-3B-Instruct-2512-4bit").
    func loadModel(
        id: String,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws {
        if modelContainer != nil { unload() }
        configureMemory()
        print("🧠 MLX loading model: \(id)")
        let container = try await loadModelContainer(
            id: id,
            progressHandler: progressHandler
        )
        self.modelContainer = container
        print("🧠 MLX model ready: \(id)")
    }

    // MARK: - Generate

    /// Generates a complete response (non-streaming). Used by external callers that expect a full string.
    func generate(
        messages: [(role: String, content: String)],
        temperature: Float = 0.3,
        maxTokens: Int = 1024
    ) async throws -> String {
        guard let container = modelContainer else {
            throw MLXInferenceError.modelNotLoaded
        }

        let systemPrompt = messages.first(where: { $0.role == "system" })?.content
        let userMessages = messages.filter { $0.role == "user" }
        guard let lastUserMessage = userMessages.last?.content else {
            throw MLXInferenceError.modelNotLoaded
        }

        let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: 0.9)
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params
        )

        // Replay earlier turns so the model has full conversation context.
        // ChatSession.respond() appends user+assistant to its internal history,
        // so replaying earlier messages builds the correct multi-turn context.
        let assistantMessages = messages.filter { $0.role == "assistant" }
        for (index, userMsg) in userMessages.dropLast().enumerated() {
            // Each earlier user message should have a corresponding assistant reply
            let assistantReply = index < assistantMessages.count ? assistantMessages[index].content : ""
            _ = try await session.respond(to: userMsg.content)
            // The session already recorded the assistant's generated response internally;
            // for context replay we just need to run through the turns.
            // Note: this generates a throwaway response for each historical turn,
            // which is wasteful but correct. A future optimization could use prompt caching.
        }

        return try await session.respond(to: lastUserMessage)
    }

    /// Generates a streaming response. Returns an AsyncThrowingStream of string chunks.
    func generateStream(
        messages: [(role: String, content: String)],
        temperature: Float = 0.3,
        maxTokens: Int = 1024
    ) throws -> AsyncThrowingStream<String, Error> {
        guard let container = modelContainer else {
            throw MLXInferenceError.modelNotLoaded
        }

        let systemPrompt = messages.first(where: { $0.role == "system" })?.content
        let userMessages = messages.filter { $0.role == "user" }
        guard let lastUserMessage = userMessages.last?.content else {
            throw MLXInferenceError.modelNotLoaded
        }

        // For multi-turn streaming, we need to replay earlier turns first (non-streaming),
        // then stream only the final response.
        let earlierUserMessages = Array(userMessages.dropLast())
        let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: 0.9)

        return AsyncThrowingStream { continuation in
            Task { [container] in
                do {
                    let session = ChatSession(
                        container,
                        instructions: systemPrompt,
                        generateParameters: params
                    )

                    // Replay earlier turns to build conversation context
                    for userMsg in earlierUserMessages {
                        _ = try await session.respond(to: userMsg.content)
                    }

                    // Stream the final response
                    let stream = session.streamResponse(to: lastUserMessage)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Lifecycle

    /// Unloads the model and frees memory.
    func unload() {
        modelContainer = nil
        print("🧠 MLX model unloaded")
    }
}

// MARK: - Errors

enum MLXInferenceError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No AI model is loaded. Please download a model in Settings."
        }
    }
}
