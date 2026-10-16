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
}
