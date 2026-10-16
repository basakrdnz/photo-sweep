import Foundation

public enum GroupKind: Sendable, Equatable {
    /// Aynı fotoğrafın kopyası ya da küçültülmüş/sıkıştırılmış hali.
    case duplicate
    /// Aynı anda aynı sahneden çekilmiş, birbirine çok benzeyen kareler.
    case similar
}

public struct SimilarityGroup: Sendable, Equatable, Identifiable {
    public let kind: GroupKind
    /// En iyiden en kötüye sıralı; ilk eleman saklanması önerilen fotoğraf.
    public let memberIDs: [String]

    public init(kind: GroupKind, memberIDs: [String]) {
        precondition(!memberIDs.isEmpty, "Grup boş olamaz")
        self.kind = kind
        self.memberIDs = memberIDs
    }

    public var id: String { memberIDs[0] }
    public var suggestedKeepID: String { memberIDs[0] }
}

/// Eşikler. Varsayılanlar ilk tahmindir; etiketli test setiyle ayarlanacak.
public struct GroupingOptions: Sendable, Equatable {
    /// dHash farkı bu değere eşit ya da küçükse "kopya" sayılır (tüm arşivde).
    public var duplicateHashDistance: Int
    /// Benzer kare araması yalnızca bu kadar saniye içinde çekilenler arasında yapılır.
    public var similarTimeWindow: TimeInterval
    /// Zaman penceresinde dHash farkı bu değere kadar olanlar benzer sayılır.
    public var similarHashDistance: Int
    /// Zaman penceresinde feature print uzaklığı bu değere kadar olanlar benzer sayılır.
    public var similarFeatureDistance: Float
    /// Kopya için en-boy oranı farkı en fazla bu kadar olabilir (kırpılmışları ayırır).
    public var aspectRatioTolerance: Double

    public init(
        duplicateHashDistance: Int = 4,
        similarTimeWindow: TimeInterval = 120,
        similarHashDistance: Int = 10,
        similarFeatureDistance: Float = 0.5,
        aspectRatioTolerance: Double = 0.02
    ) {
        self.duplicateHashDistance = duplicateHashDistance
        self.similarTimeWindow = similarTimeWindow
        self.similarHashDistance = similarHashDistance
        self.similarFeatureDistance = similarFeatureDistance
        self.aspectRatioTolerance = aspectRatioTolerance
    }
}

public enum Grouper {
    /// Fotoğrafları kopya ve benzer gruplarına ayırır. Tek başına kalan
    /// fotoğraflar sonuçta yer almaz. Gruplar büyükten küçüğe sıralıdır.
    public static func group(
        _ records: [PhotoRecord],
        options: GroupingOptions = GroupingOptions()
    ) -> [SimilarityGroup] {
        guard records.count > 1 else { return [] }

        var duplicates = UnionFind(count: records.count)
        var similar = UnionFind(count: records.count)

        // Kopyalar tüm arşivde aranır: 20 bin fotoğrafta ~2e8 bit karşılaştırması,
        // telefonda bir saniye mertebesi. Daha büyük arşivler için BK-ağacına geçilebilir.
        let hashed = records.indices.compactMap { index in
            records[index].differenceHash.map { (index, $0) }
        }
        for first in hashed.indices {
            let (i, hashA) = hashed[first]
            for second in hashed.indices[(first + 1)...] {
                let (j, hashB) = hashed[second]
                if DifferenceHash.distance(hashA, hashB) <= options.duplicateHashDistance,
                   aspectRatiosMatch(records[i], records[j], tolerance: options.aspectRatioTolerance) {
                    duplicates.union(i, j)
                    similar.union(i, j)
                }
            }
        }

        // Benzer kareler yalnızca zamanca yakın fotoğraflar arasında aranır.
        let dated = records.indices
            .compactMap { index in records[index].creationDate.map { (index, $0) } }
            .sorted { $0.1 < $1.1 }
        for first in dated.indices {
            let (i, dateA) = dated[first]
            var second = first + 1
            while second < dated.count {
                let (j, dateB) = dated[second]
                if dateB.timeIntervalSince(dateA) > options.similarTimeWindow { break }
                if areSimilar(records[i], records[j], options: options) {
                    similar.union(i, j)
                }
                second += 1
            }
        }

        var members: [Int: [Int]] = [:]
        for index in records.indices {
            members[similar.find(index), default: []].append(index)
        }

        return members.values
            .filter { $0.count > 1 }
            .map { indices in
                let allDuplicates = Set(indices.map { duplicates.find($0) }).count == 1
                let ranked = BestPicker.rank(indices.map { records[$0] })
                return SimilarityGroup(
                    kind: allDuplicates ? .duplicate : .similar,
                    memberIDs: ranked.map(\.id)
                )
            }
            .sorted { lhs, rhs in
                lhs.memberIDs.count != rhs.memberIDs.count
                    ? lhs.memberIDs.count > rhs.memberIDs.count
                    : lhs.id < rhs.id
            }
    }

    private static func areSimilar(
        _ a: PhotoRecord,
        _ b: PhotoRecord,
        options: GroupingOptions
    ) -> Bool {
        if let featuresA = a.features, let featuresB = b.features,
           let distance = featuresA.distance(to: featuresB),
           distance <= options.similarFeatureDistance {
            return true
        }
        if let hashA = a.differenceHash, let hashB = b.differenceHash,
           DifferenceHash.distance(hashA, hashB) <= options.similarHashDistance {
            return true
        }
        return false
    }

    private static func aspectRatiosMatch(
        _ a: PhotoRecord,
        _ b: PhotoRecord,
        tolerance: Double
    ) -> Bool {
        guard let ratioA = a.aspectRatio, let ratioB = b.aspectRatio else { return true }
        return abs(ratioA - ratioB) / max(ratioA, ratioB) <= tolerance
    }
}

struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }
    }
}
