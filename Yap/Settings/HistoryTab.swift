import SwiftUI
import AppKit

struct HistoryTab: View {
    var activityLog: ActivityLog

    var body: some View {
        VStack(spacing: 0) {
            if activityLog.records.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No transcriptions yet")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Say something and it'll show up here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                HStack {
                    Text("\(activityLog.records.count) transcription\(activityLog.records.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        activityLog.clear()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activityLog.records) { record in
                            historyRow(for: record)

                            if record.id != activityLog.records.last?.id {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func historyRow(for record: ActivityRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: engineIconName(for: record.engine))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(record.timestamp.relativeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if record.wasEnhanced {
                        Text("Enhanced")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(.blue.opacity(0.12))
                            )
                            .foregroundStyle(.blue)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 8)
    }

    private func engineIconName(for engine: String) -> String {
        switch engine {
        case TranscriptionEngine.whisper.rawValue:   return "waveform"
        case TranscriptionEngine.parakeet.rawValue:  return "bird"
        default:                                     return "mic.fill"
        }
    }
}
