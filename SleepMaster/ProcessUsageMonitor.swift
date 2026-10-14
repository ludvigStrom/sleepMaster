import AppKit
import Darwin
import Foundation

@MainActor
protocol ProcessUsageSampling: AnyObject {
    func cpuPercent(for bundleID: String) -> Double
    func sample(bundleIDs: [String])
}

struct BusyHysteresis: Equatable {
    var overNeeded: Int = 2
    var underNeeded: Int = 10
    private(set) var isBusy = false
    private var overCount = 0
    private var underCount = 0

    mutating func sample(_ percent: Double, threshold: Double) -> Bool {
        if percent >= threshold {
            overCount += 1
            underCount = 0
            if overCount >= overNeeded {
                isBusy = true
            }
        } else {
            underCount += 1
            overCount = 0
            if underCount >= underNeeded {
                isBusy = false
            }
        }
        return isBusy
    }
}

@MainActor
final class IdleProcessUsage: ProcessUsageSampling {
    var percents: [String: Double] = [:]

    func cpuPercent(for bundleID: String) -> Double {
        percents[bundleID] ?? 0
    }

    func sample(bundleIDs: [String]) {}
}

@MainActor
final class ProcessUsageMonitor: ProcessUsageSampling {
    private var lastTimes: [pid_t: UInt64] = [:]
    private var lastSampleAt: Date?
    private var lastPercents: [String: Double] = [:]

    func cpuPercent(for bundleID: String) -> Double {
        lastPercents[bundleID] ?? 0
    }

    func sample(bundleIDs: [String]) {
        let now = Date()
        let elapsed = lastSampleAt.map { now.timeIntervalSince($0) } ?? 0
        lastSampleAt = now

        var nextTimes: [pid_t: UInt64] = [:]
        var nextPercents: [String: Double] = [:]

        for bundleID in Set(bundleIDs) {
            let pids = processTree(for: bundleID)
            var totalDelta: UInt64 = 0
            for pid in pids {
                guard let total = cpuTime(for: pid) else { continue }
                nextTimes[pid] = total
                if elapsed > 0, let previous = lastTimes[pid], total >= previous {
                    totalDelta += total - previous
                }
            }
            if elapsed > 0 {
                let elapsedNs = elapsed * 1_000_000_000
                nextPercents[bundleID] = (Double(totalDelta) / elapsedNs) * 100
            } else {
                nextPercents[bundleID] = lastPercents[bundleID] ?? 0
            }
        }

        lastTimes = nextTimes
        lastPercents = nextPercents
    }

    private func processTree(for bundleID: String) -> Set<pid_t> {
        let roots = rootPids(for: bundleID)
        guard !roots.isEmpty else { return [] }

        let parents = parentMap()
        var tree = Set(roots)
        var added = true
        while added {
            added = false
            for (pid, parent) in parents where !tree.contains(pid) && tree.contains(parent) {
                tree.insert(pid)
                added = true
            }
        }
        return tree
    }

    private func rootPids(for bundleID: String) -> [pid_t] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier else { return nil }
            if id == bundleID || id.hasPrefix(bundleID + ".") {
                return app.processIdentifier
            }
            return nil
        }
    }

    private func parentMap() -> [pid_t: pid_t] {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(needed))
        let filled = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard filled > 0 else { return [:] }

        var map: [pid_t: pid_t] = [:]
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.stride
            let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
            if written == size {
                map[pid] = pid_t(info.pbi_ppid)
            }
        }
        return map
    }

    private func cpuTime(for pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard written == size else { return nil }
        return info.pti_total_user + info.pti_total_system
    }
}
