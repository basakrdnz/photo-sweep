/// 8 bit gri tonlamalı görüntü. Uygulama, küçük önizlemeleri bu biçime
/// çevirip çekirdeğe verir; çekirdek Apple görüntü türlerini hiç görmez.
public struct GrayImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Satır satır, soldan sağa; 0 siyah, 255 beyaz.
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    /// Alan ortalamasıyla küçültür; her hedef hücre, kapsadığı kaynak
    /// piksellerin ortalamasıdır. Hedef kaynaktan büyükse en yakın piksel alınır.
    public func averaged(toWidth targetWidth: Int, height targetHeight: Int) -> [Double] {
        precondition(targetWidth > 0 && targetHeight > 0)
        var result = [Double](repeating: 0, count: targetWidth * targetHeight)
        for ty in 0..<targetHeight {
            let y0 = ty * height / targetHeight
            let y1 = max(y0 + 1, (ty + 1) * height / targetHeight)
            for tx in 0..<targetWidth {
                let x0 = tx * width / targetWidth
                let x1 = max(x0 + 1, (tx + 1) * width / targetWidth)
                var sum = 0
                for y in y0..<y1 {
                    let row = y * width
                    for x in x0..<x1 {
                        sum += Int(pixels[row + x])
                    }
                }
                result[ty * targetWidth + tx] = Double(sum) / Double((y1 - y0) * (x1 - x0))
            }
        }
        return result
    }
}
