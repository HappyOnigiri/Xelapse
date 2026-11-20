import Foundation

/// プロジェクト別の合計稼働時間。
struct ProjectTotal: Identifiable {
    let projectID: UUID
    let name: String
    let colorHex: String
    let seconds: TimeInterval
    var id: UUID { projectID }
}

/// 日・月・年の区間 × プロジェクトごとの稼働時間。
struct PeriodDuration: Identifiable {
    let start: Date
    let projectID: UUID
    let name: String
    let colorHex: String
    let seconds: TimeInterval
    var id: String { "\(projectID.uuidString)-\(start.timeIntervalSince1970)" }
}

/// 1 日の稼働時間と、その日に稼働のあった作業内容。
struct DailyWorkSummary: Identifiable {
    /// その日の 0:00（集計に用いたカレンダー基準）。
    let day: Date
    let seconds: TimeInterval
    /// 出現順（ログの開始時刻昇順）に重複を除いた作業内容。
    let notes: [String]
    var id: Date { day }
}

/// 作業内容ごとの合計稼働時間。
struct NoteTotal: Identifiable {
    /// nil は作業内容が入力されていないログの集計を表す。
    let note: String?
    let seconds: TimeInterval
    var id: String { note ?? "__uncategorized__" }
}

/// TimeLog 群を期間で切り出し、合計や推移を集計する純粋ロジック。
enum ReportAggregator {
    /// 集計途中の値を保持する内部アキュムレータ。
    private struct Accumulator {
        let projectID: UUID
        let name: String
        let colorHex: String
        var start: Date = .distantPast
        var seconds: TimeInterval = 0
    }

    /// プロジェクト別の合計稼働秒数を、稼働時間の降順で返す。
    static func projectTotals(
        logs: [TimeLog],
        in range: ClosedRange<Date>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectTotal] {
        var totals: [UUID: Accumulator] = [:]
        for log in logs {
            guard let project = log.project else { continue }
            let seconds = clippedDuration(for: log, in: range, now: now)
            guard seconds > 0 else { continue }
            var entry = totals[project.id]
                ?? Accumulator(projectID: project.id, name: project.name, colorHex: project.colorHex)
            entry.seconds += seconds
            totals[project.id] = entry
        }
        return totals.values
            .map { ProjectTotal(projectID: $0.projectID, name: $0.name, colorHex: $0.colorHex, seconds: $0.seconds) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// 区間 × プロジェクトの稼働秒数を、区間の開始時刻順で返す。
    static func periodDurations(
        logs: [TimeLog],
        in range: ClosedRange<Date>,
        unit: Calendar.Component,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PeriodDuration] {
        var grouped: [String: Accumulator] = [:]
        for log in logs {
            guard let project = log.project else { continue }
            for segment in segments(for: log, in: range, unit: unit, now: now, calendar: calendar) {
                let key = "\(project.id.uuidString)-\(segment.start.timeIntervalSince1970)"
                var entry = grouped[key] ?? Accumulator(
                    projectID: project.id,
                    name: project.name,
                    colorHex: project.colorHex,
                    start: segment.start
                )
                entry.seconds += segment.seconds
                grouped[key] = entry
            }
        }
        return grouped.values
            .map {
                PeriodDuration(start: $0.start, projectID: $0.projectID,
                               name: $0.name, colorHex: $0.colorHex, seconds: $0.seconds)
            }
            .sorted { $0.start < $1.start }
    }

    /// 作業内容（note）ごとの合計稼働秒数を、稼働時間の降順で返す。
    /// 1 ログに複数 note がある場合は note 数で均等割りし、合計が実稼働と一致するようにする。
    static func noteTotals(
        logs: [TimeLog],
        in range: ClosedRange<Date>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [NoteTotal] {
        var totals: [String?: TimeInterval] = [:]
        for log in logs {
            let seconds = clippedDuration(for: log, in: range, now: now)
            guard seconds > 0 else { continue }
            let uniqueNotes = Set(
                log.notes
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
            if uniqueNotes.isEmpty {
                totals[nil, default: 0] += seconds
            } else {
                let share = seconds / Double(uniqueNotes.count)
                for note in uniqueNotes {
                    totals[note, default: 0] += share
                }
            }
        }
        return totals
            .map { NoteTotal(note: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// 1 日ごとの稼働秒数と作業内容を、日付昇順で返す。
    ///
    /// プロジェクトの区別はせず、その日の稼働を合算する。日付をまたぐログは
    /// 日付境界で分割し、作業内容はまたいだ双方の日に記録する。
    ///
    /// 稼働のない日も 0 秒・作業内容なしの要素として含めるため、返り値は `range` に含まれる
    /// すべての日を隙間なく網羅する（`range` の上限が属する日は、上限がその日の 0:00 のとき
    /// 稼働しうる時間が無いため除く）。
    static func dailyWorkSummaries(
        logs: [TimeLog],
        in range: ClosedRange<Date>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyWorkSummary] {
        var seconds: [Date: TimeInterval] = [:]
        var notes: [Date: [String]] = [:]
        var seenNotes: [Date: Set<String>] = [:]

        for log in logs.sorted(by: { $0.startDate < $1.startDate }) {
            let dailySegments = segments(for: log, in: range, unit: .day, now: now, calendar: calendar)
            guard !dailySegments.isEmpty else { continue }
            let logNotes = log.notes
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            for segment in dailySegments {
                seconds[segment.start, default: 0] += segment.seconds
                var seen = seenNotes[segment.start] ?? []
                for note in logNotes where seen.insert(note).inserted {
                    notes[segment.start, default: []].append(note)
                }
                seenNotes[segment.start] = seen
            }
        }

        return allDays(in: range, calendar: calendar).map { day in
            DailyWorkSummary(day: day, seconds: seconds[day] ?? 0, notes: notes[day] ?? [])
        }
    }

    // MARK: - 内部

    /// 期間に含まれるすべての日の 0:00 を昇順で返す。
    ///
    /// 上限が 0:00 ちょうどの日は、その日に稼働しうる時間が無いため含めない。
    private static func allDays(in range: ClosedRange<Date>, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: range.lowerBound)
        while cursor < range.upperBound {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// 期間でクリップした合計秒数。
    private static func clippedDuration(for log: TimeLog, in range: ClosedRange<Date>, now: Date) -> TimeInterval {
        let start = max(log.startDate, range.lowerBound)
        let end = min(log.endDate ?? now, range.upperBound)
        return max(0, end.timeIntervalSince(start))
    }

    /// 期間でクリップしつつ、区間の境界で分割した (開始時刻, 秒数) を返す。
    private static func segments(
        for log: TimeLog,
        in range: ClosedRange<Date>,
        unit: Calendar.Component,
        now: Date,
        calendar: Calendar
    ) -> [(start: Date, seconds: TimeInterval)] {
        let start = max(log.startDate, range.lowerBound)
        let end = min(log.endDate ?? now, range.upperBound)
        guard end > start else { return [] }

        var segments: [(Date, TimeInterval)] = []
        var cursor = start
        while cursor < end {
            guard let interval = calendar.dateInterval(of: unit, for: cursor), interval.end > cursor else { break }
            let segmentEnd = min(interval.end, end)
            segments.append((interval.start, segmentEnd.timeIntervalSince(cursor)))
            cursor = segmentEnd
        }
        return segments
    }
}
