import Foundation

/// Builds screenshot filenames from a user-configurable template.
///
/// Supported tokens (case-insensitive):
///   {date}      → yyyy-MM-dd
///   {time}      → HH.mm.ss
///   {datetime}  → yyyy-MM-dd 'at' HH.mm.ss
///   {timestamp} → Unix epoch seconds
///   {title}     → captured window title (empty when unavailable)
enum FilenameFormatter {

    /// UserDefaults key holding the user's custom template (if any).
    static let userDefaultsKey = "filenameTemplate"

    /// Default template used when the user hasn't configured one.
    static let defaultTemplate = "Screenshot {datetime}"

    // MARK: - Base names (no extension)

    /// Format a template into a sanitized base filename (without extension).
    static func format(template: String, date: Date = Date(), windowTitle: String? = nil) -> String {
        let df = DateFormatter()

        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: date)

        df.dateFormat = "HH.mm.ss"
        let timeStr = df.string(from: date)

        df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateTimeStr = df.string(from: date)

        let timestampStr = String(Int(date.timeIntervalSince1970))
        let titleStr = (windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""

        var result = template
        let replacements: [(String, String)] = [
            ("{datetime}", dateTimeStr),
            ("{date}", dateStr),
            ("{time}", timeStr),
            ("{timestamp}", timestampStr),
            ("{title}", titleStr),
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(
                of: token, with: value, options: .caseInsensitive)
        }

        let sanitized = sanitize(result)
        return sanitized.isEmpty ? "Screenshot \(dateTimeStr)" : sanitized
    }

    // MARK: - Full filenames (with extension)

    static func defaultImageFilename(windowTitle: String? = nil) -> String {
        let template = UserDefaults.standard.string(forKey: userDefaultsKey) ?? defaultTemplate
        let base = format(template: template, windowTitle: windowTitle)
        return "\(base).\(ImageEncoder.fileExtension)"
    }

    // MARK: - Helpers

    /// Strip characters that are illegal in filenames and collapse whitespace.
    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
