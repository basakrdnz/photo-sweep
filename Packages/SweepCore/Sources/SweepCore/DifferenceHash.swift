/// 64 bitlik görsel parmak izi (dHash). Görüntü 9x8'e küçültülür ve her
/// satırda yan yana iki hücrenin hangisinin daha parlak olduğu bir bit olur.
/// Yeniden boyutlandırma, sıkıştırma ve genel parlaklık değişimi izi pek
/// değiştirmez; farklı sahneler ise ortalama 32 bit civarı farklı çıkar.
public enum DifferenceHash {
    public static func compute(_ image: GrayImage) -> UInt64 {
        let cells = image.averaged(toWidth: 9, height: 8)
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                hash <<= 1
                if cells[y * 9 + x] < cells[y * 9 + x + 1] {
                    hash |= 1
                }
            }
        }
        return hash
    }

    /// İki iz arasındaki farklı bit sayısı (0...64).
    public static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
