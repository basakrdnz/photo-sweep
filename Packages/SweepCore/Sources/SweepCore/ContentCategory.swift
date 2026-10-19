/// Cihazdaki görüntü sınıflandırıcısının etiketlerinden türetilen içerik
/// kategorileri. Sınıflandırıcı hiyerarşik etiketler döndürür (ör. "pizza"
/// ile birlikte "food"); listede olmayan etiketler zararsızca yok sayılır.
public enum ContentCategory: String, CaseIterable, Sendable {
    case food
    case landscape
    case document
    case pet

    /// Uygulamanın belge algılayıcısı, sayfa karenin büyük bölümünü
    /// kapladığında bu etiketi ekler (güven = algılama güveni).
    public static let documentSegmentLabel = "document_segment"

    public var identifiers: Set<String> {
        switch self {
        case .food:
            [
                "food", "meal", "dessert", "baked_goods", "bread", "cake", "cookie", "pastry",
                "fruit", "vegetable", "salad", "pizza", "sandwich", "burger", "hamburger",
                "sushi", "pasta", "noodles", "soup", "meat", "seafood", "rice", "breakfast",
                "ice_cream", "chocolate", "coffee", "drink", "cocktail", "wine", "beer",
            ]
        case .landscape:
            [
                "landscape", "mountain", "hill", "beach", "shore", "sea", "ocean", "lake",
                "river", "waterfall", "forest", "desert", "canyon", "cliff", "valley",
                "sunset_sunrise", "field", "snow", "glacier", "volcano", "island", "coast",
            ]
        case .document:
            [
                Self.documentSegmentLabel, "document", "paper", "handwriting", "receipt",
                "printed_page", "whiteboard", "blackboard", "menu", "notebook", "book",
            ]
        case .pet:
            [
                "cat", "dog", "kitten", "puppy", "animal", "pet", "bird", "parrot", "rabbit",
                "hamster", "guinea_pig", "horse", "fish", "turtle",
            ]
        }
    }

    /// Bu güvenin altındaki etiketler dikkate alınmaz.
    public static let minimumConfidence: Float = 0.5

    /// Önbellekte saklanacak etiketler: tüm kategorilerin birleşimi.
    public static let allIdentifiers: Set<String> = allCases.reduce(into: []) { $0.formUnion($1.identifiers) }

    public func matches(_ record: PhotoRecord) -> Bool {
        let hit = record.labels.contains { identifiers.contains($0.key) && $0.value >= Self.minimumConfidence }
        switch self {
        case .food, .pet:
            return hit
        case .landscape, .document:
            // İnsan olan kareler manzara ya da belge sayılmaz; anı fotoğrafı olabilir.
            return hit && record.quality.faceQuality == nil
        }
    }
}
