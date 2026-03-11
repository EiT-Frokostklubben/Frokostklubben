import Vision
import CoreML
import CoreGraphics

struct Detection {
    let label: String
    let confidence: Float
    let bbox: CGRect
    let area: Float
}

final class ObjectDetector {

    private let model: VNCoreMLModel
    private let request: VNCoreMLRequest
    private let labels: [String]
    private let inputSize: CGFloat
    private let isCriticalOnlyMode: Bool

    // COCO can detect these critical classes out of the box.
    // "door" and "stairs" are not COCO classes and require another model.
    nonisolated private static let criticalLabels: Set<String> = [
        "person",
        "stop sign",
        "car",
        "bus",
        "truck",
        "motorcycle",
        "bicycle",
        "chair",
        "bench",
        "couch",
        "potted plant",
        "fire hydrant"
    ]

    nonisolated private static let confidenceThresholdByLabel: [String: Float] = [
        "person": 0.45,
        "stop sign": 0.55,
        "car": 0.5,
        "bus": 0.5,
        "truck": 0.5,
        "motorcycle": 0.5,
        "bicycle": 0.5,
        "chair": 0.45,
        "bench": 0.45,
        "couch": 0.45,
        "potted plant": 0.45,
        "fire hydrant": 0.45
    ]

    nonisolated init?(modelName: String, labels: [String], inputSize: CGFloat = 640, isCriticalOnlyMode: Bool = true) {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
              let coreMLModel = try? MLModel(contentsOf: modelURL, configuration: MLModelConfiguration()),
              let visionModel = try? VNCoreMLModel(for: coreMLModel) else {
            print("Failed to load model:", modelName)
            return nil
        }
        self.model = visionModel
        self.labels = labels
        self.request = VNCoreMLRequest(model: visionModel)
        self.inputSize = inputSize
        self.isCriticalOnlyMode = isCriticalOnlyMode
    }

    nonisolated func detect(pixelBuffer: CVPixelBuffer,
                            completion: @escaping (_ detections: [Detection]) -> Void) {

        request.imageCropAndScaleOption = .scaleFit
        let sourceWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard sourceWidth > 0, sourceHeight > 0 else {
            completion([])
            return
        }

        let scale = min(inputSize / sourceWidth, inputSize / sourceHeight)
        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale
        let padX = (inputSize - scaledWidth) * 0.5
        let padY = (inputSize - scaledHeight) * 0.5

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            completion([])
            return
        }

        guard let results = request.results as? [VNCoreMLFeatureValueObservation],
              let first = results.first,
              let multiArray = first.featureValue.multiArrayValue else {
            completion([])
            return
        }

        let confidenceThreshold: Float = 0.5
        let nmsThreshold: Float = 0.45

        let numPredictions = multiArray.shape[2].intValue
        let numClasses = multiArray.shape[1].intValue - 4

        var candidates: [Detection] = []
        candidates.reserveCapacity(numPredictions)

        for i in 0..<numPredictions {
            var bestScore: Float = 0
            var bestClass: Int = -1

            for c in 0..<numClasses {
                let score = multiArray[[0, NSNumber(value: c + 4), NSNumber(value: i)]].floatValue
                if score > bestScore {
                    bestScore = score
                    bestClass = c
                }
            }

            guard bestClass >= 0 else { continue }

            let label = bestClass < labels.count ? labels[bestClass] : "class_\(bestClass)"
            let normalizedLabel = label.lowercased()
            if isCriticalOnlyMode && !Self.criticalLabels.contains(normalizedLabel) { continue }
            let requiredConfidence = Self.confidenceThresholdByLabel[normalizedLabel] ?? confidenceThreshold
            guard bestScore >= requiredConfidence else { continue }

            let cx = multiArray[[0, 0, NSNumber(value: i)]].floatValue
            let cy = multiArray[[0, 1, NSNumber(value: i)]].floatValue
            let w = multiArray[[0, 2, NSNumber(value: i)]].floatValue
            let h = multiArray[[0, 3, NSNumber(value: i)]].floatValue

            let modelX = CGFloat(cx - w / 2)
            let modelY = CGFloat(cy - h / 2)
            let modelWidth = CGFloat(w)
            let modelHeight = CGFloat(h)

            // Convert from scale-fit model coordinates (with letterbox padding)
            // back to normalized source-image coordinates.
            let x = (modelX - padX) / scaledWidth
            let y = (modelY - padY) / scaledHeight
            let width = modelWidth / scaledWidth
            let height = modelHeight / scaledHeight

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            if clamped.isNull || clamped.width <= 0 || clamped.height <= 0 { continue }

            let area = Float(clamped.width * clamped.height)
            candidates.append(Detection(label: label, confidence: bestScore, bbox: clamped, area: area))
        }

        let finalDetections = nonMaxSuppression(detections: candidates, iouThreshold: nmsThreshold)
        completion(finalDetections)
    }

    nonisolated private func nonMaxSuppression(detections: [Detection], iouThreshold: Float) -> [Detection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [Detection] = []
        var suppressed = Array(repeating: false, count: sorted.count)

        for i in 0..<sorted.count {
            if suppressed[i] { continue }
            let candidate = sorted[i]
            kept.append(candidate)

            for j in (i + 1)..<sorted.count {
                if suppressed[j] { continue }
                if iou(candidate.bbox, sorted[j].bbox) > iouThreshold {
                    suppressed[j] = true
                }
            }
        }
        return kept
    }

    nonisolated private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        let interArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        if unionArea <= 0 { return 0 }
        return Float(interArea / unionArea)
    }

    nonisolated static let cocoLabels: [String] = [
        "person","bicycle","car","motorcycle","airplane","bus","train","truck","boat","traffic light",
        "fire hydrant","stop sign","parking meter","bench","bird","cat","dog","horse","sheep","cow",
        "elephant","bear","zebra","giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee",
        "skis","snowboard","sports ball","kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket","bottle",
        "wine glass","cup","fork","knife","spoon","bowl","banana","apple","sandwich","orange",
        "broccoli","carrot","hot dog","pizza","donut","cake","chair","couch","potted plant","bed",
        "dining table","toilet","tv","laptop","mouse","remote","keyboard","cell phone","microwave","oven",
        "toaster","sink","refrigerator","book","clock","vase","scissors","teddy bear","hair drier","toothbrush"
    ]
}
