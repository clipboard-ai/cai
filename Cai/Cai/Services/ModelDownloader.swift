import Foundation

/// Downloads MLX model files from Hugging Face with progress tracking and cancellation.
/// Delegates to MLXInference which uses HubApi internally to download model repositories
/// (*.safetensors, *.json, tokenizer files) to the HuggingFace cache directory.
class ModelDownloader: NSObject, ObservableObject {
    /// Shared instance — survives window close so downloads continue in background.
    static let shared = ModelDownloader()

    @Published var progress: Double = 0          // 0.0 to 1.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var isDownloading: Bool = false
    @Published var error: String?

    private var downloadTask: Task<Void, Error>?

    // MARK: - Default Model

    /// The recommended model shipped with Cai's built-in LLM
    static let defaultModel = ModelInfo(
        id: "mlx-community/Ministral-3-3B-Instruct-2512-4bit",
        name: "Ministral 3B",
        sizeBytes: 1_930_000_000, // ~1.8 GB
        description: "Fast, concise output. Recommended for clipboard actions."
    )

    // MARK: - Models Directory (legacy, for GGUF migration detection)

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cai")
            .appendingPathComponent("models")
    }

    // MARK: - Download

    /// Downloads an MLX model from HuggingFace and loads it into MLXInference.
    /// Progress is tracked via @Published properties for the UI.
    func download(model: ModelInfo) async throws {
        // Check available disk space before starting download
        let requiredSpace = model.sizeBytes + 500_000_000 // model + 500MB buffer
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let available = attrs[.systemFreeSize] as? Int64,
           available < requiredSpace {
            throw ModelDownloadError.insufficientDiskSpace(
                needed: model.sizeBytes, available: available
            )
        }

        await MainActor.run {
            self.isDownloading = true
            self.progress = 0
            self.downloadedBytes = 0
            self.totalBytes = model.sizeBytes
            self.error = nil
        }

        let task = Task {
            try await MLXInference.shared.loadModel(id: model.id) { [weak self] progress in
                guard let self else { return }
                let completed = progress.completedUnitCount
                let total = progress.totalUnitCount
                Task { @MainActor in
                    self.downloadedBytes = completed
                    if total > 0 {
                        self.totalBytes = total
                        self.progress = Double(completed) / Double(total)
                    }
                }
            }
        }
        self.downloadTask = task

        do {
            try await task.value

            await MainActor.run {
                self.isDownloading = false
                self.progress = 1.0
            }

            print("⬇️ MLX model downloaded and loaded: \(model.id)")
        } catch {
            // Don't report cancellation as an error
            if Task.isCancelled { return }

            await MainActor.run {
                self.isDownloading = false
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    /// Cancels the active download.
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil

        Task { @MainActor in
            self.isDownloading = false
            self.progress = 0
        }
    }

    // MARK: - GGUF Migration

    /// Checks if there are old GGUF files that should be cleaned up after MLX migration.
    static func hasLegacyGGUFModels() -> Bool {
        guard FileManager.default.fileExists(atPath: modelsDirectory.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path)) ?? []
        return contents.contains { $0.hasSuffix(".gguf") }
    }

    /// Removes old GGUF files to reclaim disk space after successful MLX migration.
    static func removeLegacyGGUFModels() {
        guard FileManager.default.fileExists(atPath: modelsDirectory.path) else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path)) ?? []
        for file in contents where file.hasSuffix(".gguf") || file.hasSuffix(".gguf.part") {
            let path = modelsDirectory.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: path)
            print("🗑️ Removed legacy GGUF model: \(file)")
        }
    }

}

// MARK: - Model Catalog

/// Curated model list and default model ID. Configuration data — separate from inference.
enum ModelCatalog {

    /// Default model for first-time setup.
    static let defaultModelId = "mlx-community/Ministral-3-3B-Instruct-2512-4bit"

    /// Curated models for the settings picker.
    static let curatedModels: [(id: String, name: String, size: String)] = [
        ("mlx-community/Ministral-3-3B-Instruct-2512-4bit", "Ministral 3B", "~1.8 GB"),
        ("mlx-community/Qwen3-4B-4bit", "Qwen3 4B", "~2.5 GB"),
        ("mlx-community/gemma-3-1b-it-qat-4bit", "Gemma 3 1B", "~0.8 GB"),
        ("mlx-community/Qwen2.5-7B-Instruct-4bit", "Qwen 2.5 7B (16 GB+ RAM)", "~4.3 GB"),
    ]
}

// MARK: - Model Info

struct ModelInfo {
    let id: String              // HuggingFace model ID: "mlx-community/Ministral-3-3B-Instruct-2512-4bit"
    let name: String            // Display name: "Ministral 3B"
    let sizeBytes: Int64        // Approximate download size
    let description: String     // User-facing description

    /// Human-readable file size (e.g. "1.8 GB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Errors

enum ModelDownloadError: LocalizedError {
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case networkError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let needed, let available):
            let neededStr = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Not enough disk space. Need \(neededStr), only \(availStr) available."
        case .networkError(let message):
            return "Download failed: \(message)"
        case .cancelled:
            return "Download cancelled."
        }
    }
}
