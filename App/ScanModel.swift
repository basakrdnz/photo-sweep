import Observation
import Photos
import SweepCore

/// Tek tek listelenen (gruplanmayan) temizlik kategorileri.
enum FlatCategory: Hashable {
    case screenshots
    case blurry
    case largeVideos

    var title: String {
        switch self {
        case .screenshots: "Ekran görüntüleri"
        case .blurry: "Bulanık olabilir"
        case .largeVideos: "Büyük videolar"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .blurry: "aqi.low"
        case .largeVideos: "video"
        }
    }
}

@MainActor
@Observable
final class ScanModel {
    enum Phase: Equatable {
        case idle
        case denied
        case scanning(done: Int, total: Int)
        case organizing
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [SimilarityGroup] = []
    private(set) var screenshotIDs: [String] = []
    private(set) var blurryIDs: [String] = []
    private(set) var largeVideoIDs: [String] = []
    private(set) var records: [String: PhotoRecord] = [:]
    private(set) var assets: [String: PHAsset] = [:]
    /// Bayt cinsinden boyut; yalnızca temizlik adayları ve videolar için.
    private(set) var sizes: [String: Int64] = [:]
    /// Telefonda önizlemesi olmadığı (yalnızca iCloud'da durduğu) için analiz edilemeyenler.
    private(set) var skippedCount = 0
    private(set) var wasCancelled = false
    /// Kullanıcı yalnızca seçtiği fotoğraflara erişim verdiyse.
    private(set) var isLimitedAccess = false
    var selectedForDeletion: Set<String> = []
    var errorMessage: String?
    /// Silmeden sonra gösterilen bilgi.
    var notice: String?

    private var scanTask: Task<Void, Never>?
    /// Aynı anda analiz edilen fotoğraf sayısı.
    private let concurrency = 4
    /// Bu boyutun üstündeki videolar "büyük" sayılır.
    private let largeVideoBytes: Int64 = 100_000_000

    func startScan() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    /// Taramayı durdurur; o ana kadar analiz edilenlerle sonuç gösterilir
    /// ve bir sonraki tarama kaldığı yerden devam eder.
    func cancelScan() {
        scanTask?.cancel()
    }

    func groups(of kind: GroupKind) -> [SimilarityGroup] {
        groups.filter { $0.kind == kind }
    }

    func ids(for category: FlatCategory) -> [String] {
        switch category {
        case .screenshots: screenshotIDs
        case .blurry: blurryIDs
        case .largeVideos: largeVideoIDs
        }
    }

    func totalSize(of ids: some Sequence<String>) -> Int64 {
        ids.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    func toggle(_ id: String) {
        if selectedForDeletion.contains(id) {
            selectedForDeletion.remove(id)
        } else {
            selectedForDeletion.insert(id)
        }
    }

    func setSelected(_ ids: [String], _ selected: Bool) {
        if selected {
            selectedForDeletion.formUnion(ids)
        } else {
            selectedForDeletion.subtract(ids)
        }
    }

    /// Verilen öğelerden seçili olanları siler.
    func deleteSelected(among ids: [String]) async {
        let targets = selectedForDeletion.intersection(ids)
        guard !targets.isEmpty else { return }
        do {
            let bytes = totalSize(of: targets)
            try await PhotoLibrary.delete(ids: Array(targets))
            remove(targets)
            notice = "\(targets.count) öğe silindi. \"Son Silinenler\" albümü boşaltılınca \(bytes.formatted(.byteCount(style: .file))) yer açılacak."
        } catch {
            // Kullanıcı iOS onayında "Vazgeç" derse de buraya düşer.
            errorMessage = "Silme tamamlanmadı: \(error.localizedDescription)"
        }
    }

    private func scan() async {
        guard await PhotoLibrary.requestAccess() else {
            phase = .denied
            return
        }
        wasCancelled = false
        isLimitedAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited

        let library = PhotoLibrary.fetchImageAssets()
        let videos = PhotoLibrary.fetchVideoAssets()
        assets = Dictionary(
            (library + videos).map { ($0.localIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        phase = .scanning(done: 0, total: library.count)

        // Değişmemiş fotoğraflar önbellekten gelir; yalnızca yeniler analiz edilir.
        let cache = await Task.detached(priority: .userInitiated) { AnalysisCache.load() }.value
        var analyses: [String: CachedAnalysis] = [:]
        var pending: [PHAsset] = []
        for asset in library {
            if let entry = cache[asset.localIdentifier], entry.modified == asset.modificationDate {
                analyses[asset.localIdentifier] = entry
            } else {
                pending.append(asset)
            }
        }
        phase = .scanning(done: analyses.count, total: library.count)

        var skipped = 0
        await withTaskGroup(of: (String, CachedAnalysis?).self) { group in
            var next = 0
            func enqueue() {
                guard next < pending.count, !Task.isCancelled else { return }
                let asset = pending[next]
                next += 1
                group.addTask { (asset.localIdentifier, await Self.analyze(asset)) }
            }
            for _ in 0..<concurrency { enqueue() }
            for await (id, entry) in group {
                if let entry {
                    analyses[id] = entry
                } else {
                    skipped += 1
                }
                if case let .scanning(done, total) = phase {
                    phase = .scanning(done: done + 1, total: total)
                }
                enqueue()
            }
        }
        wasCancelled = Task.isCancelled
        skippedCount = skipped
        phase = .organizing

        // Silinmiş fotoğrafların kayıtları da böylece önbellekten düşer.
        let toSave = analyses
        Task.detached(priority: .utility) { AnalysisCache.save(toSave) }

        let analyzed = library.compactMap { asset in
            analyses[asset.localIdentifier].map { Self.record(for: asset, analysis: $0) }
        }
        records = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })

        let screenshots = library
            .filter { $0.mediaSubtypes.contains(.photoScreenshot) }
            .map(\.localIdentifier)
        let screenshotSet = Set(screenshots)
        // Gruplama büyük arşivde bir saniyeyi bulabilir; arayüzü kilitlemesin.
        groups = await Task.detached(priority: .userInitiated) { Grouper.group(analyzed) }.value
        screenshotIDs = screenshots.reversed()
        blurryIDs = analyzed
            .filter { !screenshotSet.contains($0.id) && BlurCheck.isLikelyBlurry($0) }
            .sorted { ($0.quality.sharpness ?? 0) < ($1.quality.sharpness ?? 0) }
            .map(\.id)
        selectedForDeletion = defaultSelection(for: groups)

        let candidates = Set(groups.flatMap(\.memberIDs)).union(screenshotIDs).union(blurryIDs)
        let sizeTargets = candidates.compactMap { assets[$0] } + videos
        sizes = await Task.detached(priority: .userInitiated) {
            Dictionary(
                sizeTargets.map { ($0.localIdentifier, PhotoLibrary.fileSize(of: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
        }.value
        largeVideoIDs = videos
            .map(\.localIdentifier)
            .filter { (sizes[$0] ?? 0) >= largeVideoBytes }
            .sorted { (sizes[$0] ?? 0) > (sizes[$1] ?? 0) }
        phase = .finished
    }

    private func remove(_ removed: Set<String>) {
        selectedForDeletion.subtract(removed)
        groups = groups.compactMap { group in
            let remaining = group.memberIDs.filter { !removed.contains($0) }
            guard remaining.count > 1 else { return nil }
            return SimilarityGroup(kind: group.kind, memberIDs: remaining)
        }
        screenshotIDs.removeAll(where: removed.contains)
        blurryIDs.removeAll(where: removed.contains)
        largeVideoIDs.removeAll(where: removed.contains)
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

    private nonisolated static func analyze(_ asset: PHAsset) async -> CachedAnalysis? {
        guard let image = await PhotoLibrary.analysisImage(for: asset) else { return nil }
        let result = await ImageAnalyzer.analyze(image)
        return CachedAnalysis(modified: asset.modificationDate, result: result)
    }

    private nonisolated static func record(for asset: PHAsset, analysis: CachedAnalysis) -> PhotoRecord {
        PhotoRecord(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            differenceHash: analysis.differenceHash,
            features: analysis.featureVector,
            quality: QualitySignals(
                sharpness: analysis.sharpness,
                faceQuality: analysis.faceQuality,
                aesthetics: analysis.aesthetics,
                isFavorite: asset.isFavorite
            )
        )
    }
}
