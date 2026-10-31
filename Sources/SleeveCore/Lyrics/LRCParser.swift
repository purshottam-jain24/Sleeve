import Foundation

/// Parses LRC, including multi-timestamp lines, `[offset:]` and enhanced `<mm:ss.xx>` word tags.
public enum LRCParser {
    public static func parse(_ text: String) -> [LyricLine] {
        var offset: TimeInterval = 0
        var entries: [(time: TimeInterval, text: String, words: [LyricWord])] = []

        for rawLine in text.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = timestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let ms = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    // Positive LRC offsets make lyrics appear earlier.
                    offset = ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }

            let (plain, words) = parseWords(rest)
            for time in times {
                entries.append((time, plain, words))
            }
        }

        return entries
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { index, entry in
                LyricLine(
                    id: index,
                    time: max(0, entry.time - offset),
                    text: entry.text,
                    words: entry.words.map { LyricWord(time: max(0, $0.time - offset), text: $0.text) }
                )
            }
    }

    /// Accepts `mm:ss`, `mm:ss.xx`, `mm:ss.xxx` and `mm:ss:xx`.
    static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Double(parts[0]), minutes >= 0,
              parts[0].allSatisfy(\.isNumber) else { return nil }
        if parts.count == 2 {
            guard let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        guard let seconds = Double(parts[1]), let fraction = Double("0." + parts[2]) else { return nil }
        return minutes * 60 + seconds + fraction
    }

    private static let wordTag = try! NSRegularExpression(pattern: "<(\\d+:\\d+(?:[.:]\\d+)?)>")

    /// Splits enhanced-LRC text into plain text plus timed words.
    private static func parseWords(_ text: Substring) -> (String, [LyricWord]) {
        let string = String(text)
        let ns = string as NSString
        let matches = wordTag.matches(in: string, range: NSRange(location: 0, length: ns.length))
        guard let first = matches.first else {
            return (string.trimmingCharacters(in: .whitespaces), [])
        }
        var plain = ns.substring(to: first.range.location)
        var words: [LyricWord] = []
        for (i, match) in matches.enumerated() {
            let chunkStart = match.range.location + match.range.length
            let chunkEnd = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let chunk = ns.substring(with: NSRange(location: chunkStart, length: chunkEnd - chunkStart))
            plain += chunk
            if let time = timestamp(Substring(ns.substring(with: match.range(at: 1)))),
               !chunk.trimmingCharacters(in: .whitespaces).isEmpty {
                words.append(LyricWord(time: time, text: chunk))
            }
        }
        return (plain.trimmingCharacters(in: .whitespaces), words)
    }
}
