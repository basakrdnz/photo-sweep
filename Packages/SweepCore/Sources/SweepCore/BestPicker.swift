/// Grup içinde hangi fotoğrafın saklanacağını önerir. Netlik ve çözünürlük
/// grup içinde göreli ölçülür (en iyisi 1, diğerleri oranla).
public enum BestPicker {
    public static func rank(_ records: [PhotoRecord]) -> [PhotoRecord] {
        let maxSharpness = records.compactMap(\.quality.sharpness).max() ?? 0
        let maxPixels = records.map(\.pixelCount).max() ?? 0

        func score(_ record: PhotoRecord) -> Double {
            let quality = record.quality
            var total = 0.0
            if quality.isFavorite { total += 100 }
            if let sharpness = quality.sharpness, maxSharpness > 0 {
                total += 30 * sharpness / maxSharpness
            }
            if let face = quality.faceQuality { total += 20 * face }
            if let aesthetics = quality.aesthetics { total += 10 * aesthetics }
            if maxPixels > 0 {
                total += 15 * Double(record.pixelCount) / Double(maxPixels)
            }
            return total
        }

        return records
            .map { (record: $0, score: score($0)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                // Eşitlikte önce çekileni (çoğu zaman asıl olanı) tut.
                switch (lhs.record.creationDate, rhs.record.creationDate) {
                case let (left?, right?) where left != right: return left < right
                default: return lhs.record.id < rhs.record.id
                }
            }
            .map(\.record)
    }
}
