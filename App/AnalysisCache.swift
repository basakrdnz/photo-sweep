import Foundation
import SweepCore

/// Bir fotoğrafın analiz sonucu; değişiklik tarihiyle birlikte saklanır.
/// Fotoğraf düzenlenmediyse sonraki taramada yeniden analiz edilmez.
struct CachedAnalysis: Codable, Sendable {
    var modified: Date?
    /// dHash; plist işaretsiz 64 bit tutamadığı için bit deseniyle saklanır.
    var hashBits: Int64?
    /// Feature print, ham Float baytları olarak (plist'te binlerce nesne yerine tek blok).
    var features: Data?
    var sharpness: Double?
    var focus: Double?
    var contrast: Double?
    var faceQuality: Double?
    var aesthetics: Double?
    var labels: [String: Float]

    init(modified: Date?, result: ImageAnalyzer.Result) {
        self.modified = modified
        hashBits = result.differenceHash.map { Int64(bitPattern: $0) }
        features = result.features.map { vector in
            vector.values.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        sharpness = result.sharpness
        focus = result.focus
        contrast = result.contrast
        labels = result.labels
        faceQuality = result.faceQuality
        aesthetics = result.aesthetics
    }

    var differenceHash: UInt64? { hashBits.map { UInt64(bitPattern: $0) } }

    var featureVector: FeatureVector? {
        features.map { data in
            FeatureVector(data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) })
        }
    }
}

/// Analiz sonuçlarını Application Support altında tek dosyada tutar.
enum AnalysisCache {
    /// Analiz yöntemi değişirse artırılır; eski önbellek yok sayılır.
    private static let version = 3

    private struct Payload: Codable {
        var version: Int
        var entries: [String: CachedAnalysis]
    }

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "analysis-cache.plist")
    }

    static func load() -> [String: CachedAnalysis] {
        guard let data = try? Data(contentsOf: url),
              let payload = try? PropertyListDecoder().decode(Payload.self, from: data),
              payload.version == version
        else { return [:] }
        return payload.entries
    }

    static func save(_ entries: [String: CachedAnalysis]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Payload(version: version, entries: entries)) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
