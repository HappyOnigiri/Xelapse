import Charts
import SwiftData
import SwiftUI

/// 稼働時間レポートのダッシュボード。選択期間の合計と推移を表示し、CSV 出力も行う。
struct DashboardView: View {
    @Environment(\.locale) private var locale
    @Query private var logs: [TimeLog]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var period: DashboardPeriod = .month
    @State private var selectedMonth: Date
    @State private var selectedYear: Date
    /// 絞り込み対象のプロジェクト ID。nil のときはすべて表示。
    @State private var selectedProjectID: UUID?
    @State private var exportMessage: String?

    init(selectedMonth: Date = ScreenshotSampleData.initialMonth(fallback: DashboardView.currentMonthStart)) {
        _selectedMonth = State(initialValue: selectedMonth)
        _selectedYear = State(initialValue: selectedMonth)
    }

    var body: some View {
        let report = report
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls(report)
                if let range = report.range, !report.logsInRange.isEmpty {
                    totalsSection(report.projectTotals)
                    trendSection(report, range: range)
                    notesSection(report.noteTotals)
                } else {
                    ContentUnavailableView("データがありません", systemImage: "chart.bar",
                                           description: Text("この期間に記録された稼働時間はありません。"))
                        .frame(height: 200)
                }
            }
            .padding(20)
        }
        .navigationTitle("ダッシュボード")
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - 操作部

    private func controls(_ report: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("集計期間", selection: $period) {
                    Text("月別").tag(DashboardPeriod.month)
                    Text("年別").tag(DashboardPeriod.year)
                    Text("全期間").tag(DashboardPeriod.allTime)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: period) { oldPeriod, newPeriod in
                    if oldPeriod == .month && newPeriod == .year {
                        selectedYear = selectedMonth
                    }
                }
                Spacer()
                projectFilterMenu
                Menu {
                    Button("時間別 CSV") { exportCSV() }
                    Button("作業内容別 CSV") { exportNoteSummaryCSV() }
                    Button("日付別 CSV") { exportDailyWorkCSV() }
                } label: {
                    Label("CSV 出力", systemImage: "square.and.arrow.up")
                }
            }
            if let unit = period.navigationUnit {
                periodNavigation(unit: unit, report: report)
            }
            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func periodNavigation(unit: Calendar.Component, report: DashboardReport) -> some View {
        let isMonth = unit == .month
        let selection = isMonth ? $selectedMonth : $selectedYear
        let calendar = report.calendar
        let date = selection.wrappedValue
        let now = Date()
        let start = calendar.dateInterval(of: unit, for: date)?.start ?? date
        let current = calendar.dateInterval(of: unit, for: now)?.start ?? now
        let latest = isMonth ? current : report.latestYearStart
        let previousLabel: LocalizedStringKey = isMonth ? "前の月" : "前の年"
        let nextLabel: LocalizedStringKey = isMonth ? "次の月" : "次の年"
        let currentLabel: LocalizedStringKey = isMonth ? "今月" : "今年"

        return HStack(spacing: 12) {
            Button {
                selection.wrappedValue = calendar.date(byAdding: unit, value: -1, to: start) ?? start
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(previousLabel)
            .accessibilityLabel(previousLabel)
            Text(periodLabel(for: date, calendar: calendar, isMonth: isMonth))
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 110)
            Button {
                selection.wrappedValue = min(calendar.date(byAdding: unit, value: 1, to: start) ?? start, latest)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(nextLabel)
            .accessibilityLabel(nextLabel)
            .disabled(start >= latest)
            Button(currentLabel) { selection.wrappedValue = current }
                .disabled(start == current)
        }
    }

    private func periodLabel(for date: Date, calendar: Calendar, isMonth: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = DashboardPeriod.gregorianCalendar(timeZone: calendar.timeZone)
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(isMonth ? "yMMMM" : "y")
        return formatter.string(from: date)
    }

    /// プロジェクト絞り込み用のメニュー。「すべて」または 1 つを選択する。
    private var projectFilterMenu: some View {
        Menu {
            Picker("プロジェクト", selection: $selectedProjectID) {
                Text("すべてのプロジェクト").tag(UUID?.none)
                ForEach(projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(projectFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("表示するプロジェクトを絞り込む")
    }

    /// フィルタメニューのラベル。選択状況に応じて表示を変える。
    private var projectFilterLabel: String {
        guard let id = selectedProjectID,
              let project = projects.first(where: { $0.id == id }) else {
            return L10n.string("すべてのプロジェクト", locale: locale)
        }
        return project.name
    }

    // MARK: - 合計

    private func totalsSection(_ projectTotals: [ProjectTotal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プロジェクト別 合計稼働時間").font(.headline)
            Chart(projectTotals) { total in
                BarMark(
                    x: .value(L10n.string("時間", locale: locale), DurationFormatter.hours(from: total.seconds)),
                    y: .value(L10n.string("プロジェクト", locale: locale), total.name)
                )
                .foregroundStyle(by: .value(L10n.string("プロジェクト", locale: locale), total.name))
                .annotation(position: .trailing) {
                    Text(DurationFormatter.compactHours(from: total.seconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale(range: projectTotals.map { Color(hex: $0.colorHex) ?? .gray })
            .chartXAxisLabel("時間")
            .chartLegend(.hidden)
            .frame(height: max(120, CGFloat(projectTotals.count) * 44))
        }
    }

    // MARK: - 作業内容別

    private func notesSection(_ noteTotals: [NoteTotal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("作業内容別 稼働時間")
                .font(.headline)
            if noteTotals.count > 1 {
                Text("1つの記録に複数の作業内容がある場合、時間を均等に配分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart(noteTotals) { total in
                BarMark(
                    x: .value("時間", DurationFormatter.hours(from: total.seconds)),
                    y: .value(
                        L10n.string("作業内容", locale: locale),
                        total.note ?? L10n.string("未分類", locale: locale)
                    )
                )
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .annotation(position: .trailing) {
                    Text(DurationFormatter.compactHours(from: total.seconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxisLabel("時間")
            .chartLegend(.hidden)
            .frame(height: max(120, CGFloat(noteTotals.count) * 32))
        }
    }

    // MARK: - 集計・CSV

    private static var currentMonthStart: Date {
        let now = Date()
        return DashboardPeriod.month.reportCalendar.dateInterval(of: .month, for: now)?.start ?? now
    }

    private var report: DashboardReport {
        DashboardReport(logs: logs, projectID: selectedProjectID, period: period,
                        selectedDate: period == .year ? selectedYear : selectedMonth)
    }

    private func exportCSV() {
        let report = report
        handleExport(CSVExportService.export(
            logs: report.logsInRange, clipTo: report.range,
            suggestedName: report.exportFilename("filename.timelogs", locale: locale),
            locale: locale))
    }

    private func exportNoteSummaryCSV() {
        let report = report
        handleExport(CSVExportService.exportNoteSummary(
            totals: report.noteTotals,
            suggestedName: report.exportFilename("filename.note_summary", locale: locale),
            locale: locale))
    }

    private func exportDailyWorkCSV() {
        let report = report
        handleExport(CSVExportService.exportDailyWork(
            summaries: report.dailyWorkSummaries, calendar: .jst,
            suggestedName: report.exportFilename("filename.daily_work", locale: locale),
            locale: locale))
    }

    private func handleExport(_ result: CSVExportService.ExportResult) {
        switch result {
        case .saved(let url):
            exportMessage = String(
                format: L10n.string("export.saved", locale: locale),
                locale: locale, url.lastPathComponent
            )
        case .cancelled: exportMessage = nil
        case .failed(let message):
            exportMessage = String(
                format: L10n.string("export.failed", locale: locale),
                locale: locale, message
            )
        }
    }
}

private extension DashboardView {
    // MARK: - 推移

    func trendSection(_ report: DashboardReport, range: ClosedRange<Date>) -> some View {
        let durations = report.trendDurations
        let totals = Dictionary(grouping: durations, by: \.start)
            .map { (start: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
            .sorted { $0.start < $1.start }
        let calendar = report.calendar
        let unit = report.period.trendUnit
        let dateLabel = L10n.string("日付", locale: locale)
        let hoursLabel = L10n.string("時間", locale: locale)
        let projectLabel = L10n.string("プロジェクト", locale: locale)
        var seen = Set<String>()
        let colors = durations.filter { seen.insert($0.name).inserted }.map { Color(hex: $0.colorHex) ?? .gray }

        return VStack(alignment: .leading, spacing: 8) {
            Text(trendTitle(for: report.period)).font(.headline)
            Chart {
                ForEach(durations) { item in
                    BarMark(
                        x: .value(dateLabel, item.start, unit: unit, calendar: calendar),
                        y: .value(hoursLabel, DurationFormatter.hours(from: item.seconds))
                    )
                    .foregroundStyle(by: .value(projectLabel, item.name))
                }
                ForEach(totals, id: \.start) { total in
                    PointMark(
                        x: .value(dateLabel, total.start, unit: unit, calendar: calendar),
                        y: .value(hoursLabel, DurationFormatter.hours(from: total.seconds))
                    )
                    .opacity(0)
                    .annotation(position: .top) {
                        Text(DurationFormatter.compactHours(from: total.seconds))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartForegroundStyleScale(range: colors)
            .chartXScale(domain: report.trendDomain(for: range))
            .chartXAxis {
                AxisMarks(values: .stride(by: unit, calendar: calendar)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: trendAxisFormat(for: report))
                }
            }
            .chartYAxisLabel("時間")
            .frame(height: 260)
        }
    }

    func trendTitle(for period: DashboardPeriod) -> LocalizedStringKey {
        switch period {
        case .month: "1日ごとの稼働時間推移"
        case .year: "月ごとの稼働時間推移"
        case .allTime: "年ごとの稼働時間推移"
        }
    }

    func trendAxisFormat(for report: DashboardReport) -> Date.FormatStyle {
        let format = Date.FormatStyle(locale: locale, calendar: report.calendar, timeZone: report.calendar.timeZone)
        switch report.period {
        case .month: return format.day()
        case .year: return format.month(.abbreviated)
        case .allTime: return format.year()
        }
    }
}
