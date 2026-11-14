import Foundation

/// Every user-visible word and threshold of the S8 canvas cards, read once from words.json (D-4694): code holds keys only.
public enum Words {
    private struct File: Decodable, Sendable { let words: [String: String]; let numbers: [String: Double] }

    private static let file: File = {
        guard let url = Bundle.module.url(forResource: "words", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data)
        else { fatalError("words.json is missing from the Window Organizer bundle") }
        return file
    }()

    /// The text as written in the file, placeholders unfilled.
    public static func raw(_ key: String) -> String { file.words[key] ?? key }
    public static func has(_ key: String) -> Bool { file.words[key] != nil || file.numbers[key] != nil }
    public static func text(_ key: String, _ arguments: CVarArg...) -> String { String(format: raw(key), arguments: arguments) }
    public static func number(_ key: String) -> Double { file.numbers[key] ?? 0 }
    /// "1 window" / "3 windows": picks base.one or base.other, so every counted noun is worded in the file.
    public static func count(_ base: String, _ n: Int) -> String { n == 1 ? raw(base + ".one") : text(base + ".other", n) }
}
