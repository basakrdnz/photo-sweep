import Foundation
import Testing
@testable import SweepCore

private let base = Date(timeIntervalSince1970: 1_700_000_000)

private func record(
    _ id: String,
    seconds: TimeInterval? = 0,
    hash: UInt64? = nil,
    features: [Float]? = nil,
    size: (Int, Int) = (4032, 3024),
    quality: QualitySignals = QualitySignals()
) -> PhotoRecord {
    PhotoRecord(
        id: id,
        creationDate: seconds.map { base.addingTimeInterval($0) },
        pixelWidth: size.0,
        pixelHeight: size.1,
        differenceHash: hash,
        features: features.map(FeatureVector.init),
        quality: quality
    )
}

@Suite struct GrouperTests {
    @Test func duplicatesAreFoundAcrossTheWholeLibrary() {
        let groups = Grouper.group([
            record("a", seconds: 0, hash: 0xFFFF_0000_FFFF_0000),
            record("b", seconds: 86_400 * 300, hash: 0xFFFF_0000_FFFF_0001, size: (1600, 1200)),
            record("c", seconds: 50, hash: 0x0F0F_0F0F_0F0F_0F0F),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].kind == .duplicate)
        #expect(Set(groups[0].memberIDs) == ["a", "b"])
        // Tam çözünürlüklü olan saklanmalı.
        #expect(groups[0].suggestedKeepID == "a")
    }

    @Test func croppedCopyIsNotADuplicate() {
        let groups = Grouper.group([
            record("a", seconds: 0, hash: 42),
            record("b", seconds: 86_400, hash: 42, size: (3024, 3024)),
        ])
        #expect(groups.isEmpty)
    }

    @Test func similarShotsOnlyWithinTimeWindow() {
        let groups = Grouper.group([
            record("a", seconds: 0, hash: 0, features: [0, 0]),
            record("b", seconds: 10, hash: UInt64.max, features: [0.3, 0]),
            record("c", seconds: 10_000, hash: 0xAAAA_AAAA_AAAA_AAAA, features: [0.1, 0]),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].kind == .similar)
        #expect(Set(groups[0].memberIDs) == ["a", "b"])
    }

    @Test func burstChainsIntoOneGroup() {
        let groups = Grouper.group([
            record("a", seconds: 0, features: [0.0]),
            record("b", seconds: 2, features: [0.4]),
            record("c", seconds: 4, features: [0.8]),
            record("d", seconds: 6, features: [5.0]),
        ])
        #expect(groups.count == 1)
        #expect(Set(groups[0].memberIDs) == ["a", "b", "c"])
    }

    @Test func longChainIsSplit() {
        // Her kare bir öncekine benziyor ama ilk ve son kare çok farklı.
        let groups = Grouper.group((0..<12).map { step in
            record("p\(step)", seconds: Double(step) * 30, features: [Float(step) * 0.4])
        })
        #expect(groups.count > 1)
        for group in groups {
            let positions = group.memberIDs.map { Int($0.dropFirst())! }
            #expect(positions.max()! - positions.min()! <= 3)
        }
    }

    @Test func duplicatesStayTogetherWhenChainSplits() {
        let groups = Grouper.group([
            record("a", seconds: 0, hash: 1, features: [0.0]),
            record("b", seconds: 30, hash: 0xF0F0, features: [0.4]),
            record("c", seconds: 60, hash: 0xFF00_FF00, features: [0.8]),
            record("d", seconds: 90, hash: 0xFFFF_0000_FFFF_0000, features: [1.2]),
            record("d-copy", seconds: 86_400, hash: 0xFFFF_0000_FFFF_0000, features: [1.2]),
        ])
        let withD = groups.first { $0.memberIDs.contains("d") }
        #expect(withD?.memberIDs.contains("d-copy") == true)
    }

    @Test func closeHashDoesNotOverrideDistantFeatures() {
        let groups = Grouper.group([
            record("a", seconds: 0, hash: 0, features: [0]),
            record("b", seconds: 5, hash: 0b111, features: [2]),
        ])
        #expect(groups.isEmpty)
    }

    @Test func mixedGroupIsSimilar() {
        let groups = Grouper.group([
            record("a", seconds: 0, hash: 7, features: [0]),
            record("b", seconds: 1, hash: 7, features: [0]),
            record("c", seconds: 3, hash: 0xFFFF_FFFF_0000_0000, features: [0.2]),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].kind == .similar)
        #expect(groups[0].memberIDs.count == 3)
    }

    @Test func photosWithoutSignalsStayAlone() {
        let groups = Grouper.group([
            record("a", seconds: nil),
            record("b", seconds: nil),
        ])
        #expect(groups.isEmpty)
    }

    @Test func largerGroupsComeFirst() {
        let groups = Grouper.group([
            record("x1", seconds: 0, features: [0]),
            record("x2", seconds: 1, features: [0]),
            record("y1", seconds: 1_000, features: [0]),
            record("y2", seconds: 1_001, features: [0]),
            record("y3", seconds: 1_002, features: [0]),
        ])
        #expect(groups.map(\.memberIDs.count) == [3, 2])
    }
}

@Suite struct BlurCheckTests {
    @Test func blurryOnlyWhenEveryRegionIsSoft() {
        #expect(BlurCheck.isLikelyBlurry(record("a", quality: QualitySignals(focus: 5, contrast: 40))))
        // Konusu net, arka planı bulanık portre.
        #expect(!BlurCheck.isLikelyBlurry(record("b", quality: QualitySignals(sharpness: 3, focus: 300, contrast: 40))))
        // Düz gökyüzü: kontrast düşük, değerlendirilmez.
        #expect(!BlurCheck.isLikelyBlurry(record("c", quality: QualitySignals(focus: 2, contrast: 5))))
    }

    @Test func lowSharpnessIsBlurry() {
        #expect(BlurCheck.isLikelyBlurry(record("a", quality: QualitySignals(sharpness: 3))))
        #expect(!BlurCheck.isLikelyBlurry(record("b", quality: QualitySignals(sharpness: 400))))
    }

    @Test func favoritesAndUnmeasuredAreNeverFlagged() {
        #expect(!BlurCheck.isLikelyBlurry(record("a", quality: QualitySignals(sharpness: 3, isFavorite: true))))
        #expect(!BlurCheck.isLikelyBlurry(record("b")))
    }
}

@Suite struct ContentCategoryTests {
    @Test func foodLabelsMatch() {
        let pizza = PhotoRecord(id: "p", creationDate: nil, pixelWidth: 1, pixelHeight: 1,
                                differenceHash: nil, features: nil, labels: ["food": 0.9])
        #expect(ContentCategory.food.matches(pizza))
        #expect(!ContentCategory.landscape.matches(pizza))
    }

    @Test func lowConfidenceIsIgnored() {
        let maybe = PhotoRecord(id: "m", creationDate: nil, pixelWidth: 1, pixelHeight: 1,
                                differenceHash: nil, features: nil, labels: ["food": 0.2])
        #expect(!ContentCategory.food.matches(maybe))
    }

    @Test func landscapeWithPeopleIsNotLandscape() {
        let selfie = PhotoRecord(id: "s", creationDate: nil, pixelWidth: 1, pixelHeight: 1,
                                 differenceHash: nil, features: nil,
                                 quality: QualitySignals(faceQuality: 0.7), labels: ["beach": 0.9])
        let view = PhotoRecord(id: "v", creationDate: nil, pixelWidth: 1, pixelHeight: 1,
                               differenceHash: nil, features: nil, labels: ["beach": 0.9])
        #expect(!ContentCategory.landscape.matches(selfie))
        #expect(ContentCategory.landscape.matches(view))
    }
}

@Suite struct BestPickerTests {
    @Test func favoriteAlwaysWins() {
        let ranked = BestPicker.rank([
            record("sharp", quality: QualitySignals(sharpness: 900, faceQuality: 0.9)),
            record("fav", quality: QualitySignals(sharpness: 100, isFavorite: true)),
        ])
        #expect(ranked.first?.id == "fav")
    }

    @Test func sharperPhotoWins() {
        let ranked = BestPicker.rank([
            record("blurry", quality: QualitySignals(sharpness: 50)),
            record("sharp", quality: QualitySignals(sharpness: 500)),
        ])
        #expect(ranked.map(\.id) == ["sharp", "blurry"])
    }

    @Test func betterFaceOutweighsSmallSharpnessGap() {
        let ranked = BestPicker.rank([
            record("eyesClosed", quality: QualitySignals(sharpness: 500, faceQuality: 0.2)),
            record("smiling", quality: QualitySignals(sharpness: 450, faceQuality: 0.8)),
        ])
        #expect(ranked.first?.id == "smiling")
    }

    @Test func tieKeepsTheEarlierShot() {
        let ranked = BestPicker.rank([
            record("later", seconds: 5),
            record("earlier", seconds: 1),
        ])
        #expect(ranked.first?.id == "earlier")
    }
}
