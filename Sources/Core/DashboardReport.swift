import Foundation

enum DashboardPeriod: Hashable {
    case month
    case year
    case allTime

    var reportCalendar: Calendar {
        self == .month ? .current : Self.gregorianCalendar(timeZone: .current)
    }

    static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
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

    func filenamePeriod(for date: Date, timeZone: TimeZone) -> String {
        guard self != .allTime else { return "all-time" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Self.gregorianCalendar(timeZone: timeZone)
        formatter.timeZone = timeZone
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
        calendar: Calendar? = nil
    ) {
        let calendar = calendar ?? period.reportCalendar
        let projectLogs = projectID.map { id in logs.filter { $0.project?.id == id } } ?? logs
        let range: ClosedRange<Date>?
        if let unit = period.navigationUnit {
            range = calendar.dateInterval(of: unit, for: selectedDate).map { $0.start...$0.end }
        } else {
            range = Self.allTimeRange(logs: projectLogs, now: now)
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

    private static func allTimeRange(logs: [TimeLog], now: Date) -> ClosedRange<Date>? {
        var range: ClosedRange<Date>?
        for log in logs {
            let start = log.startDate
            let end = log.endDate ?? now
            guard start < end else { continue }
            if let previous = range {
                range = min(previous.lowerBound, start)...max(previous.upperBound, end)
            } else {
                range = start...end
            }
        }
        return range
    }

    /// 画面または日付別 CSV に稼働がある年まで移動できるようにする。
    var latestYearStart: Date {
        let current = calendar.dateInterval(of: .year, for: now)?.start ?? now
        guard let end = Self.allTimeRange(logs: projectLogs, now: now)?.upperBound else { return current }
        let localStart = Self.yearStart(before: end, calendar: calendar)
        let jst = Calendar.jst
        let jstStart = Self.yearStart(before: end, calendar: jst)
        let jstYearInLocalTime = jstStart.flatMap { calendar.date(from: jst.dateComponents([.era, .year], from: $0)) }
        return max(current, localStart ?? current, jstYearInLocalTime ?? current)
    }

    private static func yearStart(before end: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .year, for: end) else { return nil }
        if end == interval.start {
            return calendar.dateInterval(of: .year, for: end.addingTimeInterval(-1))?.start
        }
        return interval.start
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

    /// 年別・月別は選択中の暦の年・月を日本時間で取り直す。
    /// 全期間では記録の開始・終了時刻をそのまま JST の日付別集計に使う。
    var dailyWorkRange: ClosedRange<Date>? {
        guard let unit = period.navigationUnit else { return range }
        let units: Set<Calendar.Component> = period == .month ? [.era, .year, .month] : [.era, .year]
        var exportCalendar = calendar
        exportCalendar.timeZone = Calendar.jst.timeZone
        let components = calendar.dateComponents(units, from: selectedDate)
        guard let date = exportCalendar.date(from: components),
              let interval = exportCalendar.dateInterval(of: unit, for: date) else { return nil }
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
        let label = period.filenamePeriod(for: selectedDate, timeZone: calendar.timeZone)
        return String(format: format, locale: locale, label)
    }
}
