import Foundation

struct RouteTemplate: Sendable {
    let raw: String
    private let segments: [Segment]
    private let hasParams: Bool

    private enum Segment: Sendable {
        case literal(String)
        case parameter(String)
        case wildcard          // {*rest} — matches remainder
    }

    init(_ template: String) {
        self.raw = template
        var segs: [Segment] = []
        var hasP = false
        let parts = template.split(separator: "/", omittingEmptySubsequences: true)
        for part in parts {
            let s = String(part)
            if s.hasPrefix("{") && s.hasSuffix("}") {
                let name = String(s.dropFirst().dropLast())
                if name.hasPrefix("*") {
                    segs.append(.wildcard)
                } else {
                    segs.append(.parameter(name))
                }
                hasP = true
            } else {
                segs.append(.literal(s.lowercased()))
            }
        }
        self.segments = segs
        self.hasParams = hasP
    }

    /// Returns nil if no match, or a (possibly empty) dict of route values on match.
    func tryMatch(_ path: String) -> [String: String]? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)

        // Fast path for pure-literal templates (no allocation)
        if !hasParams {
            guard parts.count == segments.count else { return nil }
            for (seg, part) in zip(segments, parts) {
                guard case .literal(let lit) = seg,
                      lit == part.lowercased() else { return nil }
            }
            return [:]
        }

        // Check for wildcard (last segment)
        let hasWildcard = segments.last.map { if case .wildcard = $0 { return true }; return false } ?? false
        if hasWildcard {
            guard parts.count >= segments.count - 1 else { return nil }
        } else {
            guard parts.count == segments.count else { return nil }
        }

        var values: [String: String] = [:]
        for (i, seg) in segments.enumerated() {
            switch seg {
            case .literal(let lit):
                guard i < parts.count, parts[i].lowercased() == lit else { return nil }
            case .parameter(let name):
                guard i < parts.count else { return nil }
                values[name] = String(parts[i])
            case .wildcard:
                values["rest"] = parts[i...].joined(separator: "/")
                return values
            }
        }
        return values
    }
}
