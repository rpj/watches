import Foundation

public enum Ranking {
    /// First `limit` watches not matching `excludedID`, preserving input order.
    public static func topWatches(_ watches: [WearWatch], limit: Int, excluding excludedID: String? = nil) -> [WearWatch] {
        guard limit > 0 else { return [] }
        var result: [WearWatch] = []
        for watch in watches {
            if let excludedID, watch.id == excludedID { continue }
            result.append(watch)
            if result.count == limit { break }
        }
        return result
    }

    /// "Brand Model" truncated to `maxLength` characters with a trailing "…" when cut.
    public static func shortLabel(for watch: WearWatch, maxLength: Int = 18) -> String {
        truncate(fullLabel(watch), maxLength: maxLength)
    }

    /// De-duplicated labels. Collisions fall back to "<brand initial>. <model>", then " (2)", " (3)"...
    public static func shortLabels(for watches: [WearWatch], maxLength: Int = 18) -> [String] {
        let full = watches.map { shortLabel(for: $0, maxLength: maxLength) }
        var fullCounts: [String: Int] = [:]
        for label in full { fullCounts[label, default: 0] += 1 }

        var labels: [String] = []
        for (index, watch) in watches.enumerated() {
            if fullCounts[full[index], default: 0] > 1 {
                labels.append(truncate(initialLabel(watch), maxLength: maxLength))
            } else {
                labels.append(full[index])
            }
        }

        var seen: [String: Int] = [:]
        var total: [String: Int] = [:]
        for label in labels { total[label, default: 0] += 1 }
        var result: [String] = []
        for label in labels {
            if total[label, default: 0] > 1 {
                let n = seen[label, default: 0] + 1
                seen[label] = n
                result.append(n == 1 ? label : "\(label) (\(n))")
            } else {
                result.append(label)
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func fullLabel(_ watch: WearWatch) -> String {
        "\(watch.brand) \(watch.model)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func initialLabel(_ watch: WearWatch) -> String {
        guard let first = watch.brand.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return fullLabel(watch)
        }
        return "\(String(first).uppercased()). \(watch.model)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        let limit = max(1, maxLength)
        if text.isEmpty { return "Watch" }
        if text.count <= limit { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}
