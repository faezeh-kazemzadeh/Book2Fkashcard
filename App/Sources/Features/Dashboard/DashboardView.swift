import SwiftUI
import Charts
import SwiftData
import B2FCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var viewModel = DashboardViewModel()
    @Query private var reviewLogs: [ReviewLogEntity]   // drives refresh when reviews change

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                syncBanner

                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(title: "Books", value: "\(viewModel.snapshot.books)", systemImage: "books.vertical")
                    StatTile(title: "Lessons", value: "\(viewModel.snapshot.lessons)", systemImage: "list.bullet.rectangle")
                    StatTile(title: "Cards Generated", value: "\(viewModel.snapshot.cards)", systemImage: "rectangle.stack")
                    StatTile(title: "Reviews Today", value: "\(viewModel.snapshot.summary?.reviewsToday ?? 0)",
                             systemImage: "checkmark.circle", tint: .green)
                    StatTile(title: "Due Now", value: "\(viewModel.snapshot.dueNow)", systemImage: "clock", tint: .orange)
                    StatTile(title: "Retention Rate", value: viewModel.retentionText, systemImage: "brain.head.profile", tint: .purple)
                    StatTile(title: "Learning Streak", value: viewModel.streakText, systemImage: "flame", tint: .red)
                    StatTile(title: "Anki Exports", value: "\(viewModel.snapshot.exports)", systemImage: "square.and.arrow.up")
                }

                if let summary = viewModel.snapshot.summary {
                    chartCard(title: "Weekly Progress", data: summary.weekly, unit: .day, format: .dateTime.weekday(.abbreviated))
                    chartCard(title: "Monthly Progress", data: summary.monthly, unit: .day, format: .dateTime.day())
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Study Heatmap").font(.headline)
                        StudyHeatmapView(counts: summary.heatmap)
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if viewModel.snapshot.dueNow > 0 {
                    NavigationLink {
                        StudySessionView(scope: .all)
                    } label: {
                        Label("Study \(viewModel.snapshot.dueNow) due cards", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .onAppear { viewModel.refresh(repository: model.repository) }
        .onChange(of: reviewLogs.count) { _, _ in viewModel.refresh(repository: model.repository) }
        .refreshable { viewModel.refresh(repository: model.repository) }
    }

    @ViewBuilder
    private var syncBanner: some View {
        let monitor = model.syncMonitor
        if !monitor.isOnline || model.settings.cloudSyncEnabled {
            Label(monitor.statusText, systemImage: monitor.isOnline ? "icloud" : "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func chartCard(title: LocalizedStringKey, data: [DailyActivity], unit: Calendar.Component,
                           format: Date.FormatStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(data) { day in
                BarMark(x: .value("Day", day.day, unit: unit), y: .value("Reviews", day.reviews))
                    .foregroundStyle(Color.accentColor.gradient)
                    .accessibilityLabel(day.day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(day.reviews) reviews, \(day.correct) correct")
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisValueLabel(format: format)
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Calendar heatmap of daily review counts for the last 26 weeks (scrolls to today).
struct StudyHeatmapView: View {
    let counts: [Date: Int]
    private let calendar = Calendar.current

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let weeks = 26
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let offset = (weeks - 1 - week) * 7 + (6 - weekday)
                            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                            let count = counts[day] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: StudyAnalytics.heatLevel(count)))
                                .frame(width: 12, height: 12)
                                .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(count) reviews")
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.15)
        case 1: return Color.green.opacity(0.35)
        case 2: return Color.green.opacity(0.55)
        case 3: return Color.green.opacity(0.75)
        default: return Color.green
        }
    }
}
