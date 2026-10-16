/// Belirgin biçimde bulanık fotoğrafları işaretler. Netlik, analizdeki en
/// uzun kenarı 256 piksel olan gri önizlemeden ölçülür; bu boyutta hafif
/// odak kayması görünmez, yalnızca ciddi bulanıklık eşiğin altına düşer.
/// Eşik ilk tahmindir; etiketli test setiyle ayarlanacak.
public enum BlurCheck {
    public static let defaultThreshold = 15.0

    public static func isLikelyBlurry(_ record: PhotoRecord, threshold: Double = defaultThreshold) -> Bool {
        guard !record.quality.isFavorite, let sharpness = record.quality.sharpness else { return false }
        return sharpness < threshold
    }
}
