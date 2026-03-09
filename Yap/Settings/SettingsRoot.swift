import SwiftUI
import AVFoundation

private enum SettingsTab: String, CaseIterable {
    case engine
    case preferences
    case enhancement
    case vocabulary
    case history
    case about

    var title: String {
        switch self {
        case .engine:      return "Engine"
        case .preferences: return "Prefs"
        case .enhancement: return "Enhance"
        case .vocabulary:  return "Dictionary"
        case .history:     return "History"
        case .about:       return "About"
        }
    }

    var icon: String {
        switch self {
        case .engine:      return "brain.head.profile"
        case .preferences: return "slider.horizontal.3"
        case .enhancement: return "wand.and.stars"
        case .vocabulary:  return "character.book.closed"
        case .history:     return "clock.arrow.circlepath"
        case .about:       return "info.circle"
        }
    }
}

struct SettingsRoot: View {
    var whisperCatalog: WhisperCatalog
    var fluidCatalog:   FluidCatalog
    var activityLog:    ActivityLog
    var wordBank:       WordBank

    @State private var selectedTab: SettingsTab = .engine

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            Group {
                switch selectedTab {
                case .engine:
                    EngineTab(whisperCatalog: whisperCatalog, fluidCatalog: fluidCatalog)
                case .preferences:
                    PreferencesTab()
                case .enhancement:
                    EnhancementTab()
                case .vocabulary:
                    VocabularyTab(wordBank: wordBank)
                case .history:
                    HistoryTab(activityLog: activityLog)
                case .about:
                    AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }


    private func tabButton(for tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16))
                    .frame(width: 24, height: 20)
                Text(tab.title)
                    .font(.system(size: 9))
            }
            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

        content()
    }
    .padding(.vertical, 12)
}


final class AudioDeviceWatcher: @unchecked Sendable {
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: AVCaptureDevice.wasConnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.onChange?() },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.onChange?() }
        ]
    }

    func stop() {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    deinit { stop() }
}


struct KeyCapView: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 22, minHeight: 20)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}
