import Foundation

/// Turns file names into something you would put on a poster.
/// Camera names like `IMG_4821.MOV` or `PXL_20230712_181502.mp4` carry no meaning,
/// so those become the recording date. Anything else is tidied up and kept.
enum DisplayTitle {
    /// Matched case-insensitively against the file name without its extension.
    static let cameraNamePatterns: [String] = [
        #"^(IMG|MVI|DSC[FN]?|DJI|GOPR|G[HX]\d{2}|VID|PXL|MAH|CLIP|MOV|TRIM|RPReplay)[_ -]?\d[\w.-]*$"#,
        #"^\d{8}[_-]\d{6}\w*$"#,            // Android: 20190714_153012
        #"^C\d{4}$"#,                        // Sony: C0042
        #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#, // exported with UUID names
    ]

    static func isCameraName(_ stem: String) -> Bool {
        cameraNamePatterns.contains { pattern in
            stem.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func make(fileName: String, recordedAt: Date?, locale: Locale = .current) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        if isCameraName(stem), let recordedAt {
            return recordedAt.formatted(
                Date.FormatStyle(locale: locale).weekday(.abbreviated).day().month(.wide).year()
            )
        }
        return clean(stem)
    }

    /// "summer_holiday-2019.final" -> "summer holiday 2019 final"
    static func clean(_ stem: String) -> String {
        let spaced = stem.replacingOccurrences(of: #"[_.\-]+"#, with: " ", options: .regularExpression)
        let collapsed = spaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.isEmpty ? stem : collapsed
    }
}
