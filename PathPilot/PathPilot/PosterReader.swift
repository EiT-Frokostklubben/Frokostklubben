import Vision
import UIKit

final class PosterReader {

    private let queue = DispatchQueue(label: "poster.reader.queue")
    private let minimumConfidence: Float = 0.3
    private let minimumHeight: CGFloat = 0.03
    private let minimumWordCharacters = 3
    private let minimumSentenceWords = 2
    private let maximumHighlights = 6

    func read(pixelBuffer: CVPixelBuffer,
              regionOfInterest: CGRect,
              completion: @escaping (String) -> Void) {
        let request = makeTextRequest(completion: completion)
        request.regionOfInterest = clampedRegion(regionOfInterest)

        queue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try? handler.perform([request])
        }
    }

    func read(image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }

        let request = makeTextRequest(completion: completion)

        queue.async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try? handler.perform([request])
        }
    }

    private func makeTextRequest(completion: @escaping (String) -> Void) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let results = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }

            let lines = self.posterHighlights(from: results)
            completion(lines.joined(separator: "\n"))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        return request
    }

    private func clampedRegion(_ region: CGRect) -> CGRect {
        let safe = CGRect(x: 0, y: 0, width: 1, height: 1)
        let standardized = region.standardized
        let clamped = standardized.intersection(safe)
        return clamped.isNull ? safe : clamped
    }

    private func posterHighlights(from observations: [VNRecognizedTextObservation]) -> [String] {
        let candidates = observations.compactMap { observation -> OCRLine? in
            guard let top = observation.topCandidates(1).first else { return nil }
            let normalizedText = normalize(top.string)
            guard !normalizedText.isEmpty else { return nil }
            return OCRLine(
                text: normalizedText,
                confidence: top.confidence,
                box: observation.boundingBox
            )
        }

        let filtered = candidates
            .filter { $0.confidence >= minimumConfidence }
            .filter { $0.box.height >= minimumHeight }
            .filter { !$0.isNearBottomEdge }
            .filter { !isLikelyURL($0.text) }
            .filter { !isLikelyKeyboardNoise($0.text) }
            .filter { isLikelyPosterLine($0.text) }

        let ranked = deduplicatedLines(filtered)
            .map { (line: $0, score: importanceScore(for: $0)) }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.05 {
                    return lhs.score > rhs.score
                }
                return readingOrder(lhs.line, rhs.line)
            }

        let selected = Array(ranked.prefix(maximumHighlights)).map(\.line)
        return selected
            .sorted(by: readingOrder)
            .map(\.text)
    }

    private func readingOrder(_ lhs: OCRLine, _ rhs: OCRLine) -> Bool {
        if abs(lhs.box.midY - rhs.box.midY) > 0.02 {
            return lhs.box.midY > rhs.box.midY
        }
        return lhs.box.minX < rhs.box.minX
    }

    private func deduplicatedLines(_ lines: [OCRLine]) -> [OCRLine] {
        var seen = Set<String>()
        return lines.filter { line in
            seen.insert(canonicalKey(for: line.text)).inserted
        }
    }

    private func canonicalKey(for text: String) -> String {
        let pieces = text.lowercased().unicodeScalars.compactMap { scalar -> String? in
            if CharacterSet.alphanumerics.contains(scalar) {
                return String(scalar)
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return " "
            }
            return nil
        }

        return pieces.joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func importanceScore(for line: OCRLine) -> Float {
        let heightScore = Float(line.box.height) * 4.8
        let widthScore = Float(line.box.width) * 1.4
        let topPlacementBonus = Float(max(0, line.box.midY - 0.24)) * 0.9
        let conciseBonus: Float = line.wordCount <= 7 ? 0.28 : 0
        let headlineBonus: Float = line.looksLikeHeadline ? 0.22 : 0
        let largeTextBonus: Float = line.box.height >= 0.07 ? 0.32 : 0
        let longLinePenalty: Float = line.wordCount > 12 ? 0.55 : 0
        let numberPenalty: Float = line.numericRatio > 0.45 ? 0.25 : 0
        let punctuationPenalty: Float = line.symbolRatio > 0.18 ? 0.18 : 0

        return line.confidence
            + heightScore
            + widthScore
            + topPlacementBonus
            + conciseBonus
            + headlineBonus
            + largeTextBonus
            - longLinePenalty
            - numberPenalty
            - punctuationPenalty
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func isLikelyURL(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.contains("http://") || lowercased.contains("https://") || lowercased.contains("www.") {
            return true
        }

        let patterns = [
            #"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#,
            #"\b[a-z0-9-]+\.(com|net|org|io|no|co|edu|gov|app|ai)\b"#
        ]
        return patterns.contains { lowercased.range(of: $0, options: .regularExpression) != nil }
    }

    private func isLikelyKeyboardNoise(_ text: String) -> Bool {
        let lettersOnly = text.unicodeScalars.filter(CharacterSet.letters.contains)
        let digitsOnly = text.unicodeScalars.filter(CharacterSet.decimalDigits.contains)

        if lettersOnly.count <= 1 && digitsOnly.isEmpty { return true }
        if text.count <= 2 && text == text.uppercased() { return true }

        let compact = text.replacingOccurrences(of: " ", with: "")
        if compact.count <= 4 && compact == compact.uppercased() && compact.rangeOfCharacter(from: .letters) != nil {
            return true
        }

        return false
    }

    private func isLikelyPosterLine(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        let meaningfulWords = words.filter { $0.count >= minimumWordCharacters }
        if words.count >= minimumSentenceWords && !meaningfulWords.isEmpty {
            return true
        }

        if words.count == 1, let first = words.first, first.count >= 6 {
            return true
        }

        return false
    }
}

private struct OCRLine {
    let text: String
    let confidence: Float
    let box: CGRect

    var isNearBottomEdge: Bool {
        box.maxY < 0.15
    }

    var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    var numericRatio: Double {
        ratio(for: .decimalDigits)
    }

    var symbolRatio: Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        let symbolCount = scalars.filter { scalar in
            !CharacterSet.alphanumerics.contains(scalar) && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.count
        return Double(symbolCount) / Double(scalars.count)
    }

    var looksLikeHeadline: Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        if words.count == 1 {
            return text.count >= 6
        }
        if words.count > 8 {
            return false
        }

        let capitalizedWords = words.filter { word in
            guard let scalar = word.unicodeScalars.first else { return false }
            return CharacterSet.uppercaseLetters.contains(scalar)
        }

        return Double(capitalizedWords.count) / Double(words.count) >= 0.6
    }

    private func ratio(for set: CharacterSet) -> Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        let matching = scalars.filter(set.contains).count
        return Double(matching) / Double(scalars.count)
    }
}
