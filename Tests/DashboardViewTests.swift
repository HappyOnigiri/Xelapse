import Foundation
import Testing
@testable import TimeTracker

struct DashboardViewTests {
    @Test("日付別 CSV の範囲は海外の選択月でも JST の月初から月末までを含む")
    func dailyWorkRangeUsesJSTMonthBoundariesOutsideJapan() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selectedMonth = losAngeles.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let calendar = Calendar.jst
        let januaryStart = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let februaryStart = calendar.date(from: DateComponents(year: 2025, month: 2, day: 1))!

        let project = Project(name: "A")
        let firstDayLog = TimeLog(
            project: project,
            startDate: calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 0, minute: 30))!,
            endDate: calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 1, minute: 30))!)
        let lastDayLog = TimeLog(
            project: project,
            startDate: calendar.date(from: DateComponents(year: 2025, month: 1, day: 31, hour: 22, minute: 30))!,
            endDate: calendar.date(from: DateComponents(year: 2025, month: 1, day: 31, hour: 23, minute: 30))!)

        let report = DashboardReport(
            logs: [firstDayLog, lastDayLog], period: .month, selectedDate: selectedMonth, calendar: losAngeles)
        #expect(report.dailyWorkRange == januaryStart...februaryStart)
        let summaries = report.dailyWorkSummaries
        #expect(summaries.count == 31)
        #expect(summaries.first?.seconds == 3600)
        #expect(summaries.last?.seconds == 3600)
    }

    @Test("月別は選択中の暦の月境界を使い、CSV のファイル名はグレゴリオ暦で表示する")
    func monthlyReportUsesNonGregorianBoundaries() {
        var calendar = Calendar(identifier: .islamicCivil)
        calendar.timeZone = TestSupport.utcCalendar.timeZone
        let date = TestSupport.date(2025, 7, 1, 12)
        let month = calendar.dateInterval(of: .month, for: date)!
        let log = TimeLog(
            project: Project(name: "A"), startDate: month.start.addingTimeInterval(-3600),
            endDate: month.start.addingTimeInterval(3600))
        let report = DashboardReport(logs: [log], period: .month, selectedDate: month.start, calendar: calendar)

        #expect(report.range == month.start...month.end)
        #expect(report.projectTotals.map(\.seconds) == [3600])
        #expect(report.trendDurations.map(\.start) == [month.start])
        let csv = CSVExporter.makeCSV(logs: report.logsInRange, clipTo: report.range, locale: Locale(identifier: "en"))
        #expect(csv.contains(",3600,"))
        #expect(report.exportFilename("filename.timelogs", locale: Locale(identifier: "en")) == "timelogs-2025-06.csv")

        calendar.timeZone = Calendar.jst.timeZone
        let jstMonth = calendar.dateInterval(of: .month, for: date)!
        #expect(report.dailyWorkRange == jstMonth.start...jstMonth.end)
    }

    @Test("年別はプロジェクトで絞り、選択年の稼働を月の境界で分割する")
    func yearlyReportGroupsByMonthWithinSelectedProject() {
        let selectedProject = Project(name: "A")
        let otherProject = Project(name: "B")
        let outside = TimeLog(
            project: selectedProject, startDate: TestSupport.date(2024, 12, 31, 22),
            endDate: TestSupport.date(2025, 1, 1), notes: ["実装"])
        let startOfYear = TimeLog(
            project: selectedProject, startDate: TestSupport.date(2024, 12, 31, 23),
            endDate: TestSupport.date(2025, 1, 1, 1), notes: ["実装"])
        let monthBoundary = TimeLog(
            project: selectedProject, startDate: TestSupport.date(2025, 1, 31, 23),
            endDate: TestSupport.date(2025, 2, 1, 2), notes: ["実装", "レビュー"])
        let otherLog = TimeLog(
            project: otherProject, startDate: TestSupport.date(2025, 1, 1),
            endDate: TestSupport.date(2025, 1, 1, 1), notes: ["レビュー"])
        let report = DashboardReport(
            logs: [outside, startOfYear, monthBoundary, otherLog], projectID: selectedProject.id,
            period: .year, selectedDate: TestSupport.date(2025, 7, 1), calendar: TestSupport.utcCalendar)

        #expect(report.range == TestSupport.date(2025, 1, 1)...TestSupport.date(2026, 1, 1))
        #expect(report.logsInRange.map(\.id) == [startOfYear.id, monthBoundary.id])
        let durations = report.trendDurations
        #expect(durations.map(\.start) == [TestSupport.date(2025, 1, 1), TestSupport.date(2025, 2, 1)])
        #expect(durations.map(\.seconds) == [7200, 7200])
        #expect(report.projectTotals.map(\.seconds) == [14400])
        #expect(report.noteTotals.map(\.seconds) == [9000, 5400])
    }

    @Test("年別はローカル暦か JST で稼働のある最後の年まで選べる", arguments: [
        ("America/Los_Angeles", 15), ("Pacific/Auckland", 11)
    ])
    func latestSelectableYearIncludesWorkAfterEitherYearBoundary(timeZone: String, boundaryHour: Int) {
        var calendar = TestSupport.utcCalendar
        calendar.timeZone = TimeZone(identifier: timeZone)!
        let current = TestSupport.date(2025, 6, 1)
        let boundary = TestSupport.date(2025, 12, 31, boundaryHour)
        let project = Project(name: "A")
        let work = TimeLog(project: project, startDate: boundary.addingTimeInterval(-3600), endDate: boundary)
        let other = TimeLog(project: Project(name: "B"), startDate: current, endDate: TestSupport.date(2027, 1, 1))

        let atBoundary = DashboardReport(
            logs: [work, other], projectID: project.id, period: .year,
            selectedDate: current, now: current, calendar: calendar)
        #expect(atBoundary.latestYearStart == calendar.date(from: DateComponents(year: 2025)))

        work.endDate = boundary.addingTimeInterval(1)
        let afterBoundary = DashboardReport(
            logs: [work, other], projectID: project.id, period: .year,
            selectedDate: current, now: current, calendar: calendar)
        #expect(afterBoundary.latestYearStart == calendar.date(from: DateComponents(year: 2026)))
    }

    @Test("全期間は対象ログの開始から計測中の時刻までを年ごとに集計し、同じ作業内容を合算する")
    func allTimeReportSplitsYearsAndSumsNotes() {
        let project = Project(name: "A")
        let start = TestSupport.date(2024, 12, 31, 23)
        let now = TestSupport.date(2026, 1, 2, 3)
        let crossing = TimeLog(
            project: project, startDate: start, endDate: TestSupport.date(2025, 1, 1, 2), notes: ["実装"])
        let active = TimeLog(project: project, startDate: TestSupport.date(2026, 1, 2, 2), notes: ["実装"])
        let other = TimeLog(
            project: Project(name: "B"), startDate: TestSupport.date(2023, 1, 1),
            endDate: TestSupport.date(2027, 1, 1))
        let report = DashboardReport(
            logs: [crossing, active, other], projectID: project.id, period: .allTime,
            selectedDate: now, now: now, calendar: TestSupport.utcCalendar)

        #expect(report.range == start...now)
        let durations = report.trendDurations
        #expect(durations.map(\.start) == (2024...2026).map { TestSupport.date($0, 1, 1) })
        #expect(durations.map(\.seconds) == [3600, 7200, 3600])
        #expect(report.noteTotals.map(\.note) == ["実装"])
        #expect(report.noteTotals.map(\.seconds) == [14400])

        let summaries = report.dailyWorkSummaries
        #expect(summaries.first?.day == Calendar.jst.startOfDay(for: start))
        #expect(summaries.last?.day == Calendar.jst.startOfDay(for: now))
        #expect(summaries.first?.seconds == 10800)
        #expect(summaries.last?.seconds == 3600)
        #expect(summaries.contains { $0.seconds == 0 })
    }

    @Test("対象プロジェクトが空なら全期間の範囲と集計結果は空になる")
    func allTimeReportIsEmptyWhenNoProjectLogsMatch() {
        let start = TestSupport.date(2025, 1, 1)
        let log = TimeLog(project: Project(name: "A"), startDate: start, endDate: start.addingTimeInterval(3600))
        let report = DashboardReport(logs: [log], projectID: UUID(), period: .allTime, selectedDate: start)
        #expect(report.range == nil)
        #expect(report.logsInRange.isEmpty)
        #expect(report.projectTotals.isEmpty)
        #expect(report.noteTotals.isEmpty)
        #expect(report.trendDurations.isEmpty)
        #expect(report.dailyWorkSummaries.isEmpty)
    }

    @Test("稼働時間がゼロの記録は全期間の推移や日付別 CSV の範囲を広げない")
    func allTimeReportIgnoresZeroDurationBounds() {
        let project = Project(name: "A")
        let start = TestSupport.date(2025, 6, 1, 9)
        let end = start.addingTimeInterval(3600)
        let zeroDates = [TestSupport.date(2023, 1, 1, 9), TestSupport.date(2027, 1, 1, 9)]
        let zeroLogs = zeroDates.map { TimeLog(project: project, startDate: $0, endDate: $0) }
        let work = TimeLog(project: project, startDate: start, endDate: end)
        let report = DashboardReport(
            logs: zeroLogs + [work], period: .allTime, selectedDate: start, calendar: TestSupport.utcCalendar)

        #expect(report.range == start...end)
        #expect(report.logsInRange.map(\.id) == [work.id])
        #expect(report.dailyWorkSummaries.map(\.seconds) == [3600])

        let emptyReport = DashboardReport(logs: zeroLogs, period: .allTime, selectedDate: start)
        #expect(emptyReport.range == nil)
        #expect(emptyReport.dailyWorkSummaries.isEmpty)
    }

    @Test("海外の選択年でも日付別 CSV は JST の年初から翌年初まで出力する")
    func dailyWorkRangeUsesJSTYearBoundariesOutsideJapan() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selectedDate = losAngeles.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let jst = Calendar.jst
        let start = jst.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let end = jst.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let project = Project(name: "A")
        let first = TimeLog(project: project, startDate: start, endDate: start.addingTimeInterval(3600))
        let last = TimeLog(project: project, startDate: end.addingTimeInterval(-3600), endDate: end)
        let nextYear = TimeLog(project: project, startDate: end, endDate: end.addingTimeInterval(3600))
        let report = DashboardReport(
            logs: [first, last, nextYear], projectID: project.id,
            period: .year, selectedDate: selectedDate, calendar: losAngeles)

        #expect(report.dailyWorkRange == start...end)
        #expect(report.logsInRange.map(\.id) == [last.id, nextYear.id])
        let summaries = report.dailyWorkSummaries
        #expect(summaries.count == 366)
        #expect(summaries.first?.seconds == 3600)
        #expect(summaries.last?.seconds == 3600)
        let csv = CSVExporter.makeDailyWorkCSV(summaries: summaries, calendar: jst)
        let rows = csv.split(separator: "\n")
        #expect(rows.dropFirst().first?.hasPrefix("2024-01-01,") == true)
        #expect(rows.last?.hasPrefix("2024-12-31,") == true)
    }

    @Test("各 CSV のファイル名に選択期間が入る", arguments: [
        (DashboardPeriod.month, "2025-07"), (.year, "2025"), (.allTime, "all-time")
    ])
    func csvFilenamesUseSelectedPeriod(period: DashboardPeriod, suffix: String) {
        let report = DashboardReport(
            logs: [], period: period, selectedDate: TestSupport.date(2025, 7, 1), calendar: TestSupport.utcCalendar)
        let locale = Locale(identifier: "en")
        #expect(report.exportFilename("filename.timelogs", locale: locale) == "timelogs-\(suffix).csv")
        #expect(report.exportFilename("filename.note_summary", locale: locale) == "note-summary-\(suffix).csv")
        #expect(report.exportFilename("filename.daily_work", locale: locale) == "daily-work-\(suffix).csv")
    }
}
