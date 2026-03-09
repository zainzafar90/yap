import SwiftUI
import AVFoundation

struct EngineTab: View {
    var whisperCatalog: WhisperCatalog
    var fluidCatalog:   FluidCatalog

    @AppStorage(AppPreferenceKey.transcriptionEngine) private var engineRaw = TranscriptionEngine.dictation.rawValue
    @AppStorage(AppPreferenceKey.selectedMicrophoneID) private var selectedMicrophoneID = ""

    @State private var availableDevices: [AudioDevice] = []
    @State private var deviceObserver = AudioDeviceWatcher()

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .dictation
    }

    private var isWhisperBusy: Bool {
        switch whisperCatalog.state {
        case .downloading, .loading: return true
        default: return false
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding(
            get: {
                guard !selectedMicrophoneID.isEmpty else { return "" }
                return availableDevices.contains(where: { $0.uid == selectedMicrophoneID }) ? selectedMicrophoneID : ""
            },
            set: { selectedMicrophoneID = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                settingsSection("Speech Models") {
                    VStack(spacing: 0) {
                        ForEach(Array(TranscriptionEngine.allCases.enumerated()), id: \.element) { index, engine in
                            engineRow(engine)
                            if index < TranscriptionEngine.allCases.count - 1 {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .background(.quaternary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                }

                Divider()

                settingsSection("Microphone") {
                    Picker("Microphone", selection: microphoneSelection) {
                        Text("System Default").tag("")
                        ForEach(availableDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .onAppear {
            refreshDevices()
            deviceObserver.onChange = { refreshDevices() }
            deviceObserver.start()
        }
        .onDisappear {
            deviceObserver.stop()
        }
    }


    @ViewBuilder
    private func engineRow(_ engine: TranscriptionEngine) -> some View {
        let isSelected = engine == selectedEngine

        Button {
            if engine.requiresModelDownload {
                engineRaw = engine.rawValue
            } else {
                engineRaw = engine.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(engine.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)

                            if !engine.requiresModelDownload {
                                Text("Built-in")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }

                        Text(engine.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if isSelected && engine == .whisper {
                    VStack(alignment: .leading, spacing: 8) {
                        whisperVariantPicker
                        whisperStatusRow
                    }
                    .padding(.leading, 36)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }

                if isSelected && engine == .parakeet {
                    parakeetStatusRow
                        .padding(.leading, 36)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }


    private var whisperVariantPicker: some View {
        HStack(spacing: 4) {
            ForEach(WhisperModelVariant.allCases) { variant in
                let isSelected = whisperCatalog.selectedVariant == variant
                Button {
                    whisperCatalog.selectedVariant = variant
                } label: {
                    VStack(spacing: 1) {
                        Text(variant.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(variant.sizeDescription)
                            .font(.system(size: 8))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .white : .primary)
                .disabled(isWhisperBusy)
            }
        }
    }


    @ViewBuilder
    private var whisperStatusRow: some View {
        switch whisperCatalog.state {
        case .notDownloaded:
            HStack(spacing: 8) {
                Text("Not downloaded · \(whisperCatalog.selectedVariant.sizeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    Task { await whisperCatalog.downloadModel() }
                }
                .controlSize(.small)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(maxWidth: 120)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .destructive) {
                    whisperCatalog.cancelDownload()
                }
                .controlSize(.small)
            }

        case .downloaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Downloaded")
                if !whisperCatalog.diskSizeLabel.isEmpty {
                    Text("· \(whisperCatalog.diskSizeLabel)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    whisperCatalog.deleteModel()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Ready")
                if !whisperCatalog.diskSizeLabel.isEmpty {
                    Text("· \(whisperCatalog.diskSizeLabel)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    whisperCatalog.deleteModel()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .error(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") {
                    whisperCatalog.deleteModel()
                    Task { await whisperCatalog.downloadModel() }
                }
                .controlSize(.small)
            }
        }
    }


    @ViewBuilder
    private var parakeetStatusRow: some View {
        switch fluidCatalog.parakeetState {
        case .notDownloaded:
            HStack(spacing: 8) {
                Text("Not downloaded · ~600 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    Task { await fluidCatalog.downloadParakeet() }
                }
                .controlSize(.small)
            }

        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .destructive) {
                    fluidCatalog.cancelParakeetDownload()
                }
                .controlSize(.small)
            }

        case .downloaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Downloaded")
                if !fluidCatalog.parakeetDiskLabel.isEmpty {
                    Text("· \(fluidCatalog.parakeetDiskLabel)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    fluidCatalog.deleteParakeet()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Ready")
                if !fluidCatalog.parakeetDiskLabel.isEmpty {
                    Text("· \(fluidCatalog.parakeetDiskLabel)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    fluidCatalog.deleteParakeet()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .error(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") {
                    fluidCatalog.deleteParakeet()
                    Task { await fluidCatalog.downloadParakeet() }
                }
                .controlSize(.small)
            }
        }
    }


    private func refreshDevices() {
        availableDevices = AudioDevice.all()
        guard !selectedMicrophoneID.isEmpty else { return }
        if !AudioDevice.isValid(uid: selectedMicrophoneID) {
            selectedMicrophoneID = ""
        }
    }
}
