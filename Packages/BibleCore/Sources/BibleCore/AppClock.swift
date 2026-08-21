import Foundation

/// The single source of "now" and "what day is it" for the whole app.
///
/// Design doc §14: the date source is injectable, so anything that depends on
/// time is testable in milliseconds. Nothing below this line — and nothing in
/// the session engine — may call `Date()` directly.
///
/// Named `AppClock` rather than `Clock` to stay out of the way of the standard
/// library's concurrency `Clock` protocol.
public protocol AppClock: Sendable {
    var now: Date { get }
    /// The device's local calendar.
    var calendar: Calendar { get }
}

extension AppClock {
    /// Midnight at the start of the current local day.
    public var today: Date { calendar.startOfDay(for: now) }
}

public struct SystemClock: AppClock {
    public init() {}
    public var now: Date { Date() }
    public var calendar: Calendar { Calendar.current }
}

/// A clock the tests drive by hand. `advance(days:)` is what makes M5
/// testable in milliseconds instead of overnight.
public final class TestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    public let calendar: Calendar

    /// Defaults to 2026-01-15 09:00 UTC — mid-morning, so that a test which
    /// advances by a few hours stays inside the same calendar day unless it
    /// means not to.
    public init(now: Date = Date(timeIntervalSince1970: 1_768_467_600), calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()) {
        self._now = now
        self.calendar = calendar
    }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    public func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }

    public func advance(seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }

    public func advance(days: Int) {
        lock.lock(); defer { lock.unlock() }
        _now = calendar.date(byAdding: .day, value: days, to: _now) ?? _now
    }
}
