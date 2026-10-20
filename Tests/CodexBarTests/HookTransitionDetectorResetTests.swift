import CodexBarCore
import Foundation
import Testing

struct HookTransitionDetectorResetTests {
    private let config = HooksConfig(
        enabled: true,
        events: [HookRule(event: .quotaReset, executable: "/usr/bin/true")])

    private func observe(
        _ detector: HookTransitionDetector,
        usedPercent: Double,
        resetsAt: Date?,
        at now: Date) -> [HookEventType]
    {
        let lane = HookQuotaLaneObservation(
            key: HookQuotaLaneKey(provider: "codex", window: .session),
            label: "Session",
            rateWindow: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: resetsAt,
                resetDescription: nil))
        return detector
            .evaluate(
                observation: HookProviderObservation(provider: "codex", lanes: [lane], status: .unknown),
                config: self.config,
                now: now)
            .map(\.event.event)
    }

    @Test
    func `idle window whose boundary slides with the clock is not a reset`() {
        let detector = HookTransitionDetector()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var events: [HookEventType] = []
        for poll in 0..<12 {
            let now = start.addingTimeInterval(Double(poll) * 300)
            events += self.observe(detector, usedPercent: 0, resetsAt: now.addingTimeInterval(5 * 3600), at: now)
        }
        #expect(!events.contains(.quotaReset))
    }

    @Test
    func `boundary jitter of a few seconds is not a reset`() {
        let detector = HookTransitionDetector()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = start.addingTimeInterval(3 * 3600)
        _ = self.observe(detector, usedPercent: 37, resetsAt: boundary, at: start)
        let events = self.observe(
            detector,
            usedPercent: 38,
            resetsAt: boundary.addingTimeInterval(2),
            at: start.addingTimeInterval(300))
        #expect(!events.contains(.quotaReset))
    }

    @Test
    func `reaching the previous boundary with a new one is a reset`() {
        let detector = HookTransitionDetector()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = start.addingTimeInterval(200)
        _ = self.observe(detector, usedPercent: 10, resetsAt: boundary, at: start)
        // Next poll is past the old boundary; usage barely moved, so only the boundary signals it.
        let next = start.addingTimeInterval(300)
        let events = self.observe(detector, usedPercent: 5, resetsAt: next.addingTimeInterval(5 * 3600), at: next)
        #expect(events.contains(.quotaReset))
    }

    @Test
    func `large usage drop without a boundary is still a reset`() {
        let detector = HookTransitionDetector()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = self.observe(detector, usedPercent: 80, resetsAt: nil, at: start)
        let events = self.observe(detector, usedPercent: 10, resetsAt: nil, at: start.addingTimeInterval(300))
        #expect(events.contains(.quotaReset))
    }

    @Test
    func `first sample only establishes the baseline`() {
        let detector = HookTransitionDetector()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(self.observe(detector, usedPercent: 0, resetsAt: now, at: now).isEmpty)
    }
}
