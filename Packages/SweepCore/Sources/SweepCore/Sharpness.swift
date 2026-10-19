/// Netlik ölçüsü: Laplace süzgecinin varyansı. Bulanık görüntüde kenarlar
/// yumuşak olduğu için değer düşer. Mutlak değer çözünürlüğe bağlıdır; bu
/// yüzden yalnızca aynı boyuttaki önizlemeler arasında karşılaştırılmalıdır.
public enum Sharpness {
    public static func laplacianVariance(_ image: GrayImage) -> Double {
        guard image.width >= 3, image.height >= 3 else { return 0 }
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0
        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let center = 4 * Int(image[x, y])
                let neighbours = Int(image[x - 1, y]) + Int(image[x + 1, y])
                    + Int(image[x, y - 1]) + Int(image[x, y + 1])
                let value = Double(neighbours - center)
                sum += value
                sumOfSquares += value * value
                count += 1
            }
        }
        let mean = sum / count
        return sumOfSquares / count - mean * mean
    }

    /// Odak ölçüsü: görüntü 4x4 bölgeye ayrılır, en net bölgenin Laplace
    /// varyansı döner. Arka planı bulanık portrede konu net olduğu için
    /// değer yüksek kalır; yalnızca her yeri bulanık kareler düşük çıkar.
    public static func focus(_ image: GrayImage, tiles: Int = 4) -> Double {
        let tileWidth = image.width / tiles
        let tileHeight = image.height / tiles
        guard tileWidth >= 3, tileHeight >= 3 else { return laplacianVariance(image) }
        var best = 0.0
        for ty in 0..<tiles {
            for tx in 0..<tiles {
                var pixels = [UInt8]()
                pixels.reserveCapacity(tileWidth * tileHeight)
                for y in (ty * tileHeight)..<((ty + 1) * tileHeight) {
                    let row = y * image.width
                    pixels.append(contentsOf: image.pixels[(row + tx * tileWidth)..<(row + (tx + 1) * tileWidth)])
                }
                if let tile = GrayImage(width: tileWidth, height: tileHeight, pixels: pixels) {
                    best = max(best, laplacianVariance(tile))
                }
            }
        }
        return best
    }

    /// Parlaklığın standart sapması (0...127). Düz duvar, gökyüzü ya da
    /// karanlık kareler düşük çıkar; bunlar bulanık sayılmaz.
    public static func contrast(_ image: GrayImage) -> Double {
        var sum = 0.0
        var sumOfSquares = 0.0
        for pixel in image.pixels {
            let value = Double(pixel)
            sum += value
            sumOfSquares += value * value
        }
        let count = Double(image.pixels.count)
        let mean = sum / count
        return max(0, sumOfSquares / count - mean * mean).squareRoot()
    }
}
