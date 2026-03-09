import SwiftUI
import AppKit

struct HistoryTab: View {
    var activityLog: ActivityLog

    var body: some View {
        VStack(spacing: 0) {
            if activityLog.records.isEmpty {
                emptyState
            } else {
                HStack {
                    Text("\(activityLog.records.count) \(activityLog.records.count == 1 ? "transcription" : "transcriptions")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(role: .destructive) {
                        activityLog.clear()
                    } label: {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(activityLog.records) { record in
                            historyRow(for: record)
                            if record.id != activityLog.records.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                    .background(.quaternary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }


    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.quaternary.opacity(0.5))
                        .frame(width: 52, height: 52)
                    Image(systemName: "clock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text("No transcriptions yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("Say something and it'll show up here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }


    private func historyRow(for record: ActivityRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: engineIconName(for: record.engine))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(record.timestamp.relativeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if record.wasEnhanced {
                        Text("Enhanced")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }


    private func engineIconName(for engine: String) -> String {
        switch engine {
        case TranscriptionEngine.whisper.rawValue:   return "sparkles"
        case TranscriptionEngine.parakeet.rawValue:  return "bolt.fill"
        default:                                     return "waveform"
        }
    }
}
