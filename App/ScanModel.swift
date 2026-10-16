import Observation
import Photos
import SweepCore

@MainActor
@Observable
final class ScanModel {
    enum Phase: Equatable {
        case idle
        case denied
        case scanning(done: Int, total: Int)
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [SimilarityGroup] = []
    private(set) var records: [String: PhotoRecord] = [:]
    private(set) var assets: [String: PHAsset] = [:]
    var selectedForDeletion: Set<String> = []
    var errorMessage: String?

    /// Aynı anda analiz edilen fotoğraf sayısı.
    private let concurrency = 4

    var selectedCount: Int { selectedForDeletion.count }

    func scan() async {
        guard await PhotoLibrary.requestAccess() else {
            phase = .denied
            return
        }

        let library = PhotoLibrary.fetchImageAssets()
        assets = Dictionary(uniqueKeysWithValues: library.map { ($0.localIdentifier, $0) })
        phase = .scanning(done: 0, total: library.count)

        var analyzed: [PhotoRecord] = []
        analyzed.reserveCapacity(library.count)
        await withTaskGroup(of: PhotoRecord?.self) { group in
            var next = 0
            func enqueue() {
                guard next < library.count else { return }
                let asset = library[next]
                next += 1
                group.addTask { await Self.record(for: asset) }
            }
            for _ in 0..<concurrency { enqueue() }
            for await record in group {
                if let record { analyzed.append(record) }
                if case let .scanning(done, total) = phase {
                    phase = .scanning(done: done + 1, total: total)
                }
                enqueue()
            }
        }

        records = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })
        // Gruplama büyük arşivde bir saniyeyi bulabilir; arayüzü kilitlemesin.
        groups = await Task.detached(priority: .userInitiated) { Grouper.group(analyzed) }.value
        selectedForDeletion = defaultSelection(for: groups)
        phase = .finished
    }

    func toggle(_ id: String) {
        if selectedForDeletion.contains(id) {
            selectedForDeletion.remove(id)
        } else {
            selectedForDeletion.insert(id)
        }
    }

    func deleteSelected() async {
        let ids = Array(selectedForDeletion)
        guard !ids.isEmpty else { return }
        do {
            try await PhotoLibrary.delete(ids: ids)
            let removed = Set(ids)
            selectedForDeletion.removeAll()
            groups = groups.compactMap { group in
                let remaining = group.memberIDs.filter { !removed.contains($0) }
                guard remaining.count > 1 else { return nil }
                return SimilarityGroup(kind: group.kind, memberIDs: remaining)
            }
        } catch {
            // Kullanıcı iOS onayında "Vazgeç" derse de buraya düşer.
            errorMessage = "Silme tamamlanmadı: \(error.localizedDescription)"
        }
    }

    /// Önerilen dışındakiler seçili gelir; favoriler asla otomatik seçilmez.
    private func defaultSelection(for groups: [SimilarityGroup]) -> Set<String> {
        var selection = Set<String>()
        for group in groups {
            for id in group.memberIDs.dropFirst() where records[id]?.quality.isFavorite != true {
                selection.insert(id)
            }
        }
        return selection
    }

    private nonisolated static func record(for asset: PHAsset) async -> PhotoRecord? {
        guard let image = await PhotoLibrary.analysisImage(for: asset) else { return nil }
        let analysis = await ImageAnalyzer.analyze(image)
        return PhotoRecord(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            differenceHash: analysis.differenceHash,
            features: analysis.features,
            quality: QualitySignals(
                sharpness: analysis.sharpness,
                faceQuality: analysis.faceQuality,
                aesthetics: analysis.aesthetics,
                isFavorite: asset.isFavorite
            )
        )
    }
}
