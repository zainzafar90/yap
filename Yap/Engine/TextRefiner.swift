import Foundation
import FoundationModels

@available(macOS 26.0, *)
@MainActor
class TextRefiner {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func enhance(_ rawText: String, systemPrompt: String) async throws -> String {
        guard TextRefiner.isAvailable else {
            return rawText
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: "Clean up this transcription:\n\n\(rawText)")
        let enhanced = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return enhanced.isEmpty ? rawText : enhanced
    }
}
