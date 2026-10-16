/// Bir görüntünün anlamsal imzası. Uygulamada Vision'ın feature print
/// çıktısından doldurulur; aynı sahnenin kareleri birbirine yakın düşer.
public struct FeatureVector: Sendable, Equatable {
    public let values: [Float]

    public init(_ values: [Float]) {
        self.values = values
    }

    /// Öklid uzaklığı. Boyutlar uyuşmuyorsa (farklı model sürümü) nil.
    public func distance(to other: FeatureVector) -> Float? {
        guard values.count == other.values.count, !values.isEmpty else { return nil }
        var sum: Float = 0
        for index in values.indices {
            let difference = values[index] - other.values[index]
            sum += difference * difference
        }
        return sum.squareRoot()
    }
}
