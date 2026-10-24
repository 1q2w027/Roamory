import Foundation
import os

/// The edit spec to render and where it came from.
public struct PlanOutcome: Sendable {
    public enum Source: Sendable, Equatable {
        case cloud
        case fallback(reason: String)
    }

    public var spec: EditSpec
    public var source: Source
    /// Rules the spec still breaks. Empty for a cloud spec; for a fallback spec usually empty, or only
    /// "too short" when there wasn't enough footage. The fallback is rendered either way.
    public var violations: [EditSpecError]
}

/// Cloud plan when allowed and valid, otherwise the fallback planner (TRD 9.1, contracts README).
/// It never retries the cloud: any error, timeout or invalid spec goes straight to the fallback.
public struct EditPlanner: Sendable {
    public var preset: StylePreset
    public var config: EditConfig
    /// Nil when no backend is configured.
    public var service: (any PlanService)?

    static let log = Logger(subsystem: "app.roamory", category: "plan")

    public init(preset: StylePreset, config: EditConfig, service: (any PlanService)?) {
        self.preset = preset
        self.config = config
        self.service = service
    }

    public func plan(_ request: PlanRequest, thumbnails: [String: [Data]], allowCloud: Bool) async -> PlanOutcome {
        let reason: String
        if !allowCloud {
            reason = "cloud analysis is off"
        } else if let service {
            do {
                let spec = try await service.plan(request, thumbnails: thumbnails)
                // A spec from the server is still checked on the phone.
                let violations = EditSpecValidator.validate(spec, request: request, preset: preset)
                if violations.isEmpty { return PlanOutcome(spec: spec, source: .cloud, violations: []) }
                reason = "cloud spec invalid: " + violations.map(\.description).joined(separator: "; ")
            } catch {
                reason = "cloud plan failed: \(error)"
            }
        } else {
            reason = "no backend configured"
        }

        Self.log.notice("Using the fallback planner: \(reason)")
        let spec = FallbackPlanner.plan(request, preset: preset, endCardText: config.endCardText)
        let violations = EditSpecValidator.validate(spec, request: request, preset: preset)
        if !violations.isEmpty {
            Self.log.notice("Fallback plan breaks: \(violations.map(\.description).joined(separator: "; "))")
        }
        return PlanOutcome(spec: spec, source: .fallback(reason: reason), violations: violations)
    }
}
