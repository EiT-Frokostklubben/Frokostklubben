import Vision
import UIKit

final class PosterReader {

    private let queue = DispatchQueue(label: "poster.reader.queue")
    private let minimumConfidence: Float = 0.3
    private let minimumHeight: CGFloat = 0.03
    private let minimumWordCharacters = 3
    private let minimumSentenceWords = 2

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

            let lines = self.posterLines(from: results)
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

    private func posterLines(from observations: [VNRecognizedTextObservation]) -> [String] {
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

        let sorted = filtered.sorted {
            if abs($0.box.midY - $1.box.midY) > 0.02 {
                return $0.box.midY > $1.box.midY
            }
            return $0.box.minX < $1.box.minX
        }

        return sorted.map(\.text)
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
}
