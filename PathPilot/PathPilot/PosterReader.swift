import Vision
import UIKit

final class PosterReader {

    private let queue = DispatchQueue(label: "poster.reader.queue")

    func read(image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let results = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }

            let lines = results.compactMap { $0.topCandidates(1).first?.string }
            completion(lines.joined(separator: "\n"))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        queue.async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try? handler.perform([request])
        }
    }
}
