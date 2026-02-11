import Vision
import UIKit

final class VisionClassifier {

    func classify(pixelBuffer: CVPixelBuffer,
                  completion: @escaping (_ identifier: String, _ confidence: Float) -> Void) {

        let request = VNClassifyImageRequest { request, error in
            guard error == nil,
                  let results = request.results as? [VNClassificationObservation],
                  let top = results.first else {
                completion("—", 0)
                return
            }

            completion(top.identifier, top.confidence)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
}
