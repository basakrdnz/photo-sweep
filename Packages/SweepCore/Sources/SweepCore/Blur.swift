/// Belirgin biçimde bulanık fotoğrafları işaretler. Ölçüm, en uzun kenarı
/// 256 piksel olan gri önizlemeden yapılır; bu boyutta hafif odak kayması
/// görünmez, yalnızca ciddi bulanıklık eşiğin altına düşer.
/// Eşikler ilk tahmindir; etiketli test setiyle ayarlanacak.
public enum BlurCheck {
    /// En net bölge bu değerin altındaysa bulanık sayılır.
    public static let focusThreshold = 25.0
    /// Bu kontrastın altındaki (düz, karanlık) kareler değerlendirilmez.
    public static let minimumContrast = 18.0
    /// Odak ölçüsü olmayan eski kayıtlar için tüm görüntünün varyans eşiği.
    public static let sharpnessThreshold = 15.0

    public static func isLikelyBlurry(_ record: PhotoRecord) -> Bool {
        let quality = record.quality
        guard !quality.isFavorite else { return false }
        if let focus = quality.focus {
            guard (quality.contrast ?? .infinity) >= minimumContrast else { return false }
            return focus < focusThreshold
        }
        guard let sharpness = quality.sharpness else { return false }
        return sharpness < sharpnessThreshold
    }
}
