import SwiftUI

struct EnhancementTab: View {
    @AppStorage(AppPreferenceKey.transcriptionEngine)    private var engineRaw          = TranscriptionEngine.dictation.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode)        private var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) private var systemPrompt      = AppPreferenceKey.defaultEnhancementPrompt

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .dictation
    }

    private var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextRefiner.isAvailable
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsSection("Apple Intelligence") {
                Toggle(isOn: Binding(
                    get: { enhancementModeRaw == EnhancementMode.appleIntelligence.rawValue },
                    set: { enhancementModeRaw = ($0 ? EnhancementMode.appleIntelligence : EnhancementMode.off).rawValue }
                )) {
                    Text("Polish text before pasting")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(selectedEngine != .dictation)

                if selectedEngine != .dictation {
                    Text("AI engines handle this already — their output is clean.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !appleIntelligenceAvailable {
                    Text("Your Mac doesn't support Apple Intelligence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if enhancementModeRaw == EnhancementMode.appleIntelligence.rawValue, selectedEngine == .dictation {
                Divider()

                settingsSection("Prompt") {
                    TextEditor(text: $systemPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )

                    HStack {
                        Text("Tells Apple Intelligence how to shape your text.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Reset") {
                            systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
                        }
                        .controlSize(.small)
                        .disabled(systemPrompt == AppPreferenceKey.defaultEnhancementPrompt)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}
