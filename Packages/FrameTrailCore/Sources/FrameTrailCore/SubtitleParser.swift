import Foundation

public struct SubtitleCue: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(id: String, start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SubtitleFormat: String, Codable, Sendable {
    case auto
    case srt
    case vtt
}

public enum SubtitleParser {
    /// Parses usable cues; malformed blocks are skipped rather than changing their times.
    public static func parse(_ input: String, format: SubtitleFormat = .auto) -> [SubtitleCue] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let isVTT = format == .vtt || (format == .auto && normalized.hasPrefix("WEBVTT"))
        let lines = normalized.components(separatedBy: "\n")
        var result: [SubtitleCue] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if isVTT && (line == "STYLE" || line == "REGION" || line.hasPrefix("NOTE")) {
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
                continue
            }
            guard line.contains("-->") else {
                index += 1
                continue
            }
            let times = line.components(separatedBy: "-->")
            let start = times.count == 2 ? timestamp(times[0].trimmingCharacters(in: .whitespaces)) : nil
            let endText = times.count == 2
                ? times[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first ?? ""
                : ""
            let end = timestamp(endText)
            index += 1
            var body: [String] = []
            while index < lines.count {
                let bodyLine = lines[index].trimmingCharacters(in: .whitespaces)
                if bodyLine.isEmpty || bodyLine.contains("-->") { break }
                body.append(bodyLine)
                index += 1
            }
            guard let start, let end, end > start else { continue }
            let text = clean(body.joined(separator: "\n"))
            guard !text.isEmpty else { continue }
            result.append(SubtitleCue(id: "cue:\(result.count):\(start)", start: start, end: end, text: text))
        }
        return result.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    }

    /// Includes only fully completed cues, so a cue spanning the boundary cannot reveal later dialogue.
    public static func cues(
        from cues: [SubtitleCue],
        through time: TimeInterval,
        maxCharacters: Int = 12_000
    ) -> [SubtitleCue] {
        guard time.isFinite, time >= 0, maxCharacters > 0 else { return [] }
        var remaining = maxCharacters
        var result: [SubtitleCue] = []
        for cue in cues.sorted(by: { $0.start < $1.start }) {
            guard cue.start.isFinite, cue.end.isFinite, cue.start >= 0,
                  cue.end > cue.start, cue.end <= time else { continue }
            let separatorCost = result.isEmpty ? 0 : 1
            let available = remaining - separatorCost
            guard available > 0 else { break }
            var clipped = cue
            clipped.text = String(cue.text.prefix(available))
            guard !clipped.text.isEmpty else { continue }
            result.append(clipped)
            remaining -= separatorCost + clipped.text.count
        }
        return result
    }

    public static func text(from cues: [SubtitleCue], through time: TimeInterval, maxCharacters: Int = 12_000) -> String {
        self.cues(from: cues, through: time, maxCharacters: maxCharacters).map(\.text).joined(separator: "\n")
    }

    private static func timestamp(_ raw: String) -> TimeInterval? {
        let components = raw.replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard components.count == 2 || components.count == 3 else { return nil }
        let secondsParts = components[components.count - 1].components(separatedBy: ".")
        guard secondsParts.count == 2, secondsParts[0].count == 2, secondsParts[1].count == 3,
              secondsParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let seconds = Int(secondsParts[0]), seconds < 60,
              let milliseconds = Int(secondsParts[1]) else { return nil }
        let minuteText = components[components.count - 2]
        guard minuteText.count == 2, minuteText.allSatisfy(\.isNumber), let minutes = Int(minuteText), minutes < 60 else { return nil }
        let hours: Int
        if components.count == 3 {
            let hourText = components[0]
            guard hourText.count >= 2, hourText.allSatisfy(\.isNumber), let value = Int(hourText) else { return nil }
            hours = value
        } else {
            hours = 0
        }
        let result = Double(hours) * 3600 + Double(minutes) * 60 + Double(seconds) + Double(milliseconds) / 1000
        return result.isFinite ? result : nil
    }

    private static func clean(_ input: String) -> String {
        input.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
