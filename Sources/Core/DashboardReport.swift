import Foundation

enum DashboardPeriod: Hashable {
    case month
    case year
    case allTime

    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    var navigationUnit: Calendar.Component? {
        switch self {
        case .month: .month
        case .year: .year
        case .allTime: nil
        }
    }

    var trendUnit: Calendar.Component {
        switch self {
        case .month: .day
        case .year: .month
        case .allTime: .year
        }
    }

    func filenamePeriod(for date: Date, calendar: Calendar) -> String {
        guard self != .allTime else { return "all-time" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = self == .month ? "yyyy-MM" : "yyyy"
        return formatter.string(from: date)
    }
}

/// プロジェクト・期間・集計時刻をそろえたダッシュボードの集計対象。
struct DashboardReport {
    let period: DashboardPeriod
    let selectedDate: Date
    let calendar: Calendar
    let range: ClosedRange<Date>?
    let logsInRange: [TimeLog]
    private let projectLogs: [TimeLog]
    private let now: Date

    init(
        logs: [TimeLog],
        projectID: UUID? = nil,
        period: DashboardPeriod,
        selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = DashboardPeriod.localCalendar
    ) {
        let projectLogs = projectID.map { id in logs.filter { $0.project?.id == id } } ?? logs
        let range: ClosedRange<Date>?
        if let unit = period.navigationUnit {
            range = calendar.dateInterval(of: unit, for: selectedDate).map { $0.start...$0.end }
        } else if let start = projectLogs.map(\.startDate).min(),
                  let end = projectLogs.map({ $0.endDate ?? now }).max(), end >= start {
            range = start...end
        } else {
            range = nil
        }

        self.period = period
        self.selectedDate = selectedDate
        self.calendar = calendar
        self.range = range
        self.projectLogs = projectLogs
        self.now = now
        logsInRange = range.map { range in
            projectLogs.filter {
                min($0.endDate ?? now, range.upperBound) > max($0.startDate, range.lowerBound)
            }
        } ?? []
    }

    var projectTotals: [ProjectTotal] {
        guard let range else { return [] }
        return ReportAggregator.projectTotals(logs: logsInRange, in: range, now: now)
    }

    var noteTotals: [NoteTotal] {
        guard let range else { return [] }
        return ReportAggregator.noteTotals(logs: logsInRange, in: range, now: now)
    }

    var trendDurations: [PeriodDuration] {
        guard let range else { return [] }
        return ReportAggregator.periodDurations(
            logs: logsInRange, in: range, unit: period.trendUnit, now: now, calendar: calendar)
    }

    /// 年別・月別はローカル時刻の年・月を JST の暦で取り直す。
    /// 全期間では記録の開始・終了時刻をそのまま JST の日付別集計に使う。
    var dailyWorkRange: ClosedRange<Date>? {
        guard let unit = period.navigationUnit else { return range }
        let components: Set<Calendar.Component> = period == .month ? [.year, .month] : [.year]
        let jst = Calendar.jst
        guard let date = jst.date(from: calendar.dateComponents(components, from: selectedDate)),
              let interval = jst.dateInterval(of: unit, for: date) else { return nil }
        return interval.start...interval.end
    }

    var dailyWorkSummaries: [DailyWorkSummary] {
        guard let range = dailyWorkRange else { return [] }
        return ReportAggregator.dailyWorkSummaries(logs: projectLogs, in: range, now: now, calendar: .jst)
    }

    /// 最初と最後の棒が欠けないよう、推移の表示範囲は区間全体に広げる。
    func trendDomain(for range: ClosedRange<Date>) -> ClosedRange<Date> {
        let unit = period.trendUnit
        guard period == .allTime,
              let first = calendar.dateInterval(of: unit, for: range.lowerBound),
              let last = calendar.dateInterval(of: unit, for: range.upperBound) else { return range }
        let end = range.upperBound == last.start ? last.start : last.end
        return first.start...end
    }

    func exportFilename(_ key: String.LocalizationValue, locale: Locale) -> String {
        let format = L10n.string(key, locale: locale)
        return String(format: format, locale: locale, period.filenamePeriod(for: selectedDate, calendar: calendar))
    }
}
