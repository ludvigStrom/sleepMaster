import Foundation

enum ScheduleWindow {
    static func isActive(
        now: Date,
        days: Set<Int>,
        startMinutes: Int,
        endMinutes: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard !days.isEmpty else { return false }
        let weekday = calendar.component(.weekday, from: now)
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        if startMinutes == endMinutes {
            return false
        }

        if startMinutes < endMinutes {
            return days.contains(weekday) && minutes >= startMinutes && minutes < endMinutes
        }

        let yesterday = weekday == 1 ? 7 : weekday - 1
        if days.contains(weekday) && minutes >= startMinutes {
            return true
        }
        if days.contains(yesterday) && minutes < endMinutes {
            return true
        }
        return false
    }
}
