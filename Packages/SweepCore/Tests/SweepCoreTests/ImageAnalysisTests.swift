import Foundation
import Testing
@testable import SweepCore

func makeImage(width: Int, height: Int, _ pixel: (Int, Int) -> Int) -> GrayImage {
    var pixels = [UInt8]()
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels.append(UInt8(clamping: pixel(x, y)))
        }
    }
    return GrayImage(width: width, height: height, pixels: pixels)!
}

/// Yumuşak geçişli, düzensiz bir "sahne": birkaç sinüsün toplamı.
func scene(width: Int, height: Int, seed: Double, brightness: Int = 0) -> GrayImage {
    makeImage(width: width, height: height) { x, y in
        let u = Double(x) / Double(width)
        let v = Double(y) / Double(height)
        let value = 128 + 60 * sin(6 * u + seed) + 50 * cos(5 * v * (1 + seed / 3) + 2 * u)
        return Int(value) + brightness
    }
}

func boxBlur(_ image: GrayImage) -> GrayImage {
    makeImage(width: image.width, height: image.height) { x, y in
        var sum = 0
        var count = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let nx = x + dx, ny = y + dy
                if nx >= 0, ny >= 0, nx < image.width, ny < image.height {
                    sum += Int(image[nx, ny])
                    count += 1
                }
            }
        }
        return sum / count
    }
}

@Suite struct GrayImageTests {
    @Test func rejectsMismatchedPixelCount() {
        #expect(GrayImage(width: 2, height: 2, pixels: [0, 0, 0]) == nil)
        #expect(GrayImage(width: 0, height: 2, pixels: []) == nil)
    }

    @Test func averagingKeepsMean() {
        let image = makeImage(width: 4, height: 2) { x, _ in x < 2 ? 0 : 200 }
        #expect(image.averaged(toWidth: 2, height: 1) == [0, 200])
        #expect(image.averaged(toWidth: 1, height: 1) == [100])
    }
}

@Suite struct DifferenceHashTests {
    @Test func identicalImagesMatch() {
        let a = scene(width: 120, height: 90, seed: 1)
        #expect(DifferenceHash.distance(DifferenceHash.compute(a), DifferenceHash.compute(a)) == 0)
    }

    @Test func resizedAndBrightenedCopyStaysClose() {
        let original = scene(width: 240, height: 180, seed: 1)
        let smaller = scene(width: 120, height: 90, seed: 1, brightness: 20)
        let distance = DifferenceHash.distance(
            DifferenceHash.compute(original),
            DifferenceHash.compute(smaller)
        )
        #expect(distance <= 4)
    }

    @Test func differentScenesAreFar() {
        let a = scene(width: 120, height: 90, seed: 1)
        let b = scene(width: 120, height: 90, seed: 4)
        let distance = DifferenceHash.distance(DifferenceHash.compute(a), DifferenceHash.compute(b))
        #expect(distance > 12)
    }
}

@Suite struct SharpnessTests {
    @Test func flatImageHasNoSharpness() {
        let flat = makeImage(width: 32, height: 32) { _, _ in 90 }
        #expect(Sharpness.laplacianVariance(flat) == 0)
    }

    @Test func blurLowersSharpness() {
        let sharp = makeImage(width: 64, height: 64) { x, y in (x / 4 + y / 4) % 2 == 0 ? 20 : 230 }
        let blurred = boxBlur(sharp)
        #expect(Sharpness.laplacianVariance(sharp) > 2 * Sharpness.laplacianVariance(blurred))
    }
}

@Suite struct FeatureVectorTests {
    @Test func euclideanDistance() {
        let a = FeatureVector([0, 0, 0])
        let b = FeatureVector([3, 4, 0])
        #expect(a.distance(to: b) == 5)
    }

    @Test func mismatchedDimensionsAreIncomparable() {
        #expect(FeatureVector([1, 2]).distance(to: FeatureVector([1, 2, 3])) == nil)
    }
}

@Suite struct FocusTests {
    @Test func sharpSubjectOnBlurryBackgroundKeepsFocus() {
        let sharp = makeImage(width: 128, height: 128) { x, y in ((x / 2 + y / 2) % 2) * 255 }
        let blurred = boxBlur(boxBlur(scene(width: 128, height: 128, seed: 1)))
        // Sol üst çeyrek net, gerisi bulanık.
        let mixed = makeImage(width: 128, height: 128) { x, y in
            x < 32 && y < 32 ? Int(sharp[x, y]) : Int(blurred[x, y])
        }
        #expect(Sharpness.focus(mixed) > 10 * Sharpness.focus(blurred))
    }

    @Test func flatImageHasNoContrast() {
        let flat = makeImage(width: 64, height: 64) { _, _ in 120 }
        #expect(Sharpness.contrast(flat) == 0)
        let stripes = makeImage(width: 64, height: 64) { x, _ in x % 2 == 0 ? 0 : 255 }
        #expect(Sharpness.contrast(stripes) > 100)
    }
}
