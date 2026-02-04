import SwiftUI
import Foundation

/// Log viewer screen to display and export app/widget logs
/// Useful for debugging widget updates and data sharing issues
struct LogViewerView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss

    // MARK: - State
    @State private var logs: [SharedLogger.LogEntry] = []
    @State private var selectedLevel: SharedLogger.Level? = nil
    @State private var selectedSource: String? = nil
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                filterBar

                // Log list
                if filteredLogs.isEmpty {
                    emptyState
                } else {
                    logList
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        // Debug: Close button tapped
                        print("[LogViewer] Close button tapped")
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportLogs(format: .text)
                        } label: {
                            Label("Export TXT", systemImage: "doc.text")
                        }

                        Button {
                            exportLogs(format: .json)
                        } label: {
                            Label("Export JSON", systemImage: "doc.badge.gearshape")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Button {
                        loadLogs()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                loadLogs()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Clear all logs?", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearLogs()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredLogs: [SharedLogger.LogEntry] {
        var result = logs

        if let level = selectedLevel {
            result = result.filter { $0.level == level }
        }

        if let source = selectedSource {
            result = result.filter { $0.source == source }
        }

        return result
    }

    private var uniqueSources: [String] {
        Array(Set(logs.map { $0.source })).sorted()
    }

    // MARK: - Subviews

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Source filter
                Menu {
                    Button("All") {
                        selectedSource = nil
                    }
                    Divider()
                    ForEach(uniqueSources, id: \.self) { source in
                        Button(source) {
                            selectedSource = source
                        }
                    }
                } label: {
                    filterChip(
                        title: selectedSource ?? String(localized: "Source"),
                        isActive: selectedSource != nil,
                        icon: "antenna.radiowaves.left.and.right"
                    )
                }

                // Level filter
                Menu {
                    Button("All") {
                        selectedLevel = nil
                    }
                    Divider()
                    ForEach(SharedLogger.Level.allCases, id: \.self) { level in
                        Button(level.rawValue) {
                            selectedLevel = level
                        }
                    }
                } label: {
                    filterChip(
                        title: selectedLevel?.rawValue ?? String(localized: "Level"),
                        isActive: selectedLevel != nil,
                        icon: "line.3.horizontal.decrease.circle"
                    )
                }

                Spacer()

                // Count
                Text(
                    String(
                        format: NSLocalizedString("%d logs", comment: "Log count"),
                        filteredLogs.count
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func filterChip(title: String, isActive: Bool, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.2) : Color(.secondarySystemBackground))
        .foregroundStyle(isActive ? .blue : .primary)
        .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No logs")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Logs will appear here when the app or widget generates events.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var logList: some View {
        List {
            ForEach(filteredLogs) { entry in
                LogEntryRow(entry: entry)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func loadLogs() {
        logs = SharedLogger.shared.loadLogs()
    }

    private func clearLogs() {
        SharedLogger.shared.clearLogs()
        logs = []
    }

    private func exportLogs(format: SharedLogger.ExportFormat) {
        if let url = SharedLogger.shared.createExportFile(format: format) {
            exportURL = url
            showingExportSheet = true
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: SharedLogger.LogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 6) {
                // Level indicator
                Circle()
                    .fill(levelColor)
                    .frame(width: 8, height: 8)

                // Timestamp
                Text(entry.formattedTimestamp)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                // Source badge
                Text(entry.source)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.source == "Widget" ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                    .foregroundStyle(entry.source == "Widget" ? .purple : .blue)
                    .clipShape(Capsule())

                // Category
                Text(entry.category)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()
            }

            // Message
            Text(entry.message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        }
        .padding(.vertical, 4)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .widget: return .purple
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    // Add some sample logs for preview
    SharedLogger.shared.debug("App launched", category: "Lifecycle")
    SharedLogger.shared.info("Location permission granted", category: "Location")
    SharedLogger.shared.warning("Weather API slow response", category: "Weather")
    SharedLogger.shared.error("Failed to save to UserDefaults", category: "Storage")
    SharedLogger.shared.widget("Timeline requested", category: "Timeline")
    SharedLogger.shared.widget("Loaded cached data: Chandler, 69°F", category: "Data")

    return LogViewerView()
}
