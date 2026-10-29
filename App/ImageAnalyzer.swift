import CoreGraphics
import Foundation
import SweepCore
import Vision

/// Bir önizlemeden çekirdeğin ihtiyaç duyduğu sinyalleri çıkarır.
/// Vision istekleri cihazın yapay zekâ çipinde çalışır; hiçbir veri cihazdan çıkmaz.
enum ImageAnalyzer {
    struct Result {
        var differenceHash: UInt64?
        var features: FeatureVector?
        var sharpness: Double?
        var focus: Double?
        var contrast: Double?
        var faceQuality: Double?
        /// Yalnızca içerik kategorilerinde kullanılan etiketler.
        var labels: [String: Float] = [:]
        var aesthetics: Double?
    }

    /// Sınıflandırıcının belge olasılığına işaret eden etiketleri.
    private static let documentHints = ContentCategory.document.identifiers
        .union(["text", "screenshot", "poster", "sign", "chart", "diagram", "calendar"])

    /// Vision istekleri ve piksel işleri çağıran iş parçacığını bloklar.
    /// Swift'in ortak iş parçacığı havuzunda çalışırlarsa havuz dolar; zaman
    /// aşımı dahil hiçbir async iş ilerleyemez ve tarama kilitlenir. Bu yüzden
    /// ayrı bir GCD kuyruğunda çalışırlar; eşzamanlılığı tarama sınırlar.
    private static let queue = DispatchQueue(
        label: "photosweep.analysis",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func analyze(_ image: CGImage) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: analyzeBlocking(image)) }
        }
    }

    private static func analyzeBlocking(_ image: CGImage) -> Result {
        var result = Result()
        if let gray = grayImage(from: image) {
            result.differenceHash = DifferenceHash.compute(gray)
            result.sharpness = Sharpness.laplacianVariance(gray)
            result.focus = Sharpness.focus(gray)
            result.contrast = Sharpness.contrast(gray)
        }

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([featureRequest, faceRequest, classifyRequest])
            let classes = classifyRequest.results ?? []
            for observation in classes
            where observation.confidence >= 0.3 && ContentCategory.allIdentifiers.contains(observation.identifier) {
                result.labels[observation.identifier] = observation.confidence
            }

            // Belge ve hayvan algılayıcıları pahalı; yalnızca sınıflandırıcı
            // en ufak bir ihtimal gördüğünde çalışır.
            func hints(_ identifiers: Set<String>) -> Bool {
                classes.contains { $0.confidence >= 0.05 && identifiers.contains($0.identifier) }
            }
            var extra: [VNRequest] = []
            let documentRequest = VNDetectDocumentSegmentationRequest()
            if hints(documentHints) { extra.append(documentRequest) }
            let animalRequest = VNRecognizeAnimalsRequest()
            if hints(ContentCategory.pet.identifiers) { extra.append(animalRequest) }
            if !extra.isEmpty { try handler.perform(extra) }

            // Kâğıt, kitap sayfası, soru: sayfa karenin en az üçte birini kaplamalı.
            if let page = documentRequest.results?.first {
                let box = page.boundingBox
                if box.width * box.height >= 0.33 {
                    result.labels[ContentCategory.documentSegmentLabel] = page.confidence
                }
            }
            for animal in animalRequest.results ?? [] {
                for label in animal.labels {
                    let key = label.identifier.lowercased()
                    result.labels[key] = max(result.labels[key] ?? 0, label.confidence)
                }
            }
            if let observation = featureRequest.results?.first {
                result.features = featureVector(from: observation)
            }
            let faceScores = (faceRequest.results ?? []).compactMap { number($0.faceCaptureQuality) }
            result.faceQuality = faceScores.max()
        } catch {
            // Analiz edilemeyen fotoğraf yalnızca dHash ile karşılaştırılır.
        }
        // Estetik puanı bilerek hesaplanmıyor: en pahalı istekti, öneriye katkısı küçüktü.
        return result
    }

    // SDK sürümüne göre faceCaptureQuality NSNumber? ya da Float? olarak gelebiliyor.
    private static func number(_ value: NSNumber?) -> Double? { value?.doubleValue }
    private static func number(_ value: Float?) -> Double? { value.map(Double.init) }

    private static func featureVector(from observation: VNFeaturePrintObservation) -> FeatureVector? {
        guard observation.elementType == .float else { return nil }
        let values = observation.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(observation.elementCount))
        }
        return FeatureVector(values)
    }

    /// CGImage'ı en uzun kenarı en fazla `maxSide` olan gri görüntüye çevirir.
    static func grayImage(from image: CGImage, maxSide: Int = 256) -> GrayImage? {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? GrayImage(width: width, height: height, pixels: pixels) : nil
    }
}
