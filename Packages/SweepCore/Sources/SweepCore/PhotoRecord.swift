import Foundation

/// Bir fotoğrafın analiz sonucu. Kimlik, uygulamadaki PHAsset kimliğidir.
public struct PhotoRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let differenceHash: UInt64?
    public let features: FeatureVector?
    public let quality: QualitySignals

    public init(
        id: String,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        differenceHash: UInt64?,
        features: FeatureVector?,
        quality: QualitySignals = QualitySignals()
    ) {
        self.id = id
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.differenceHash = differenceHash
        self.features = features
        self.quality = quality
    }

    var pixelCount: Int { pixelWidth * pixelHeight }

    var aspectRatio: Double? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

/// Grupta hangi fotoğrafın saklanacağını önermek için kullanılan sinyaller.
/// Eksik olanlar nil kalır ve puana katılmaz.
public struct QualitySignals: Sendable, Equatable {
    /// Laplace varyansı; yalnızca grup içinde göreli kullanılır.
    public var sharpness: Double?
    /// En iyi yüzün çekim kalitesi (0...1); yüz yoksa nil.
    public var faceQuality: Double?
    /// Sistemin estetik puanı (-1...1); iOS 18 öncesinde nil.
    public var aesthetics: Double?
    public var isFavorite: Bool

    public init(
        sharpness: Double? = nil,
        faceQuality: Double? = nil,
        aesthetics: Double? = nil,
        isFavorite: Bool = false
    ) {
        self.sharpness = sharpness
        self.faceQuality = faceQuality
        self.aesthetics = aesthetics
        self.isFavorite = isFavorite
    }
}
