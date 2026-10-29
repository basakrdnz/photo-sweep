import Foundation
import Observation
import Photos
import SweepCore
import UIKit

/// Sonuçları çekim tarihine göre süzmek için.
enum DateFilter: Hashable, CaseIterable {
    case all
    case lastMonth
    case lastYear
    case olderThanYear
    case custom

    var title: String {
        switch self {
        case .all: "Tüm zamanlar"
        case .lastMonth: "Son 1 ay"
        case .lastYear: "Son 1 yıl"
        case .olderThanYear: "1 yıldan eski"
        case .custom: "Özel aralık"
        }
    }
}

/// Tek tek listelenen (gruplanmayan) temizlik kategorileri.
enum FlatCategory: Hashable, CaseIterable {
    case screenshots
    case blurry
    case documents
    case food
    case landscape
    case pets
    case selfies
    case screenRecordings
    case shortVideos
    case largeVideos

    var title: String {
        switch self {
        case .screenshots: "Ekran görüntüleri"
        case .blurry: "Bulanık olabilir"
        case .documents: "Belge ve sayfalar"
        case .food: "Yemek"
        case .landscape: "Manzara"
        case .pets: "Hayvanlar"
        case .selfies: "Selfie'ler"
        case .screenRecordings: "Ekran kayıtları"
        case .shortVideos: "Kısa videolar"
        case .largeVideos: "Büyük videolar"
        }
    }

    var subtitle: String {
        switch self {
        case .screenshots: "Ekran görüntülerinin çoğu bir kez bakılıp unutulur."
        case .blurry: "Her yeri bulanık çıkmış kareler."
        case .documents: "Kâğıt, kitap sayfası, soru, fiş ve not fotoğrafları."
        case .food: "Yemek ve içecek fotoğrafları."
        case .landscape: "İçinde insan olmayan doğa ve manzara kareleri."
        case .pets: "Kedi, köpek ve diğer hayvan fotoğrafları."
        case .selfies: "Ön kamerayla çekilmiş fotoğraflar."
        case .screenRecordings: "Ekran kayıtları, büyükten küçüğe."
        case .shortVideos: "3 saniyeden kısa, çoğu yanlışlıkla çekilmiş videolar."
        case .largeVideos: "100 MB'tan büyük videolar, büyükten küçüğe."
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .blurry: "aqi.low"
        case .documents: "doc.text.viewfinder"
        case .food: "fork.knife"
        case .landscape: "mountain.2"
        case .pets: "pawprint"
        case .selfies: "person.crop.square"
        case .screenRecordings: "record.circle"
        case .shortVideos: "timer"
        case .largeVideos: "video"
        }
    }

    var contentCategory: ContentCategory? {
        switch self {
        case .documents: .document
        case .food: .food
        case .landscape: .landscape
        case .pets: .pet
        default: nil
        }
    }
}

/// Hızlı gözden geçirmede bir ay.
struct ReviewMonth: Identifiable {
    let start: Date
    /// Eskiden yeniye.
    let ids: [String]

    var id: Date { start }
    var title: String { start.formatted(.dateTime.month(.wide).year()) }
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
    private(set) var flatIDs: [FlatCategory: [String]] = [:]
    /// Hızlı gözden geçirme için aylar, yeniden eskiye.
    private(set) var reviewMonths: [ReviewMonth] = []
    /// Hızlı gözden geçirmede "sakla" denenler; bir daha gösterilmez.
    private(set) var keptInReview: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "keptInReview") ?? [])
    /// Silme sürerken arayüz kilitlenir ve ilerleme gösterilir.
    private(set) var isDeleting = false
    var dateFilter: DateFilter = .all
    var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var customEnd = Date.now
    private(set) var records: [String: PhotoRecord] = [:]
    private(set) var assets: [String: PHAsset] = [:]
    /// Bayt cinsinden boyut; yalnızca temizlik adayları ve videolar için.
    private(set) var sizes: [String: Int64] = [:]
    /// Telefonda önizlemesi olmadığı (yalnızca iCloud'da durduğu) için analiz edilemeyenler.
    private(set) var skippedCount = 0
    private(set) var wasCancelled = false
    /// Kullanıcı yalnızca seçtiği fotoğraflara erişim verdiyse.
    private(set) var isLimitedAccess = false
    /// Kalan süre tahmini (saniye); yeterli örnek yokken nil.
    private(set) var estimatedRemaining: TimeInterval?
    /// Önceki taramanın sonuçları diskten okunurken true.
    private(set) var isLoadingCache = false
    var selectedForDeletion: Set<String> = []
    var errorMessage: String?
    /// Silmeden sonra gösterilen bilgi.
    var notice: String?

    private var scanTask: Task<Void, Never>?
    /// Aynı anda analiz edilen fotoğraf sayısı.
    /// Vision ve Neural Engine paylaşıldığı için 4'ün üstü hızlandırmıyor,
    /// yalnızca bellek ve ısı artıyor.
    private let concurrency = 4
    /// Bu boyutun üstündeki videolar "büyük" sayılır.
    private let largeVideoBytes: Int64 = 100_000_000

    /// - Parameter fromScratch: true ise önbellek yok sayılır, her şey yeniden analiz edilir.
    func startScan(fromScratch: Bool = false) {
        scanTask?.cancel()
        scanTask = Task { await scan(fromScratch: fromScratch) }
    }

    /// Taramayı durdurur; o ana kadar analiz edilenlerle sonuç gösterilir
    /// ve bir sonraki tarama kaldığı yerden devam eder.
    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: - Süzme

    /// Seçili tarih aralığı; nil ise süzme yok.
    private var dateRange: ClosedRange<Date>? {
        let calendar = Calendar.current
        let now = Date.now
        switch dateFilter {
        case .all:
            return nil
        case .lastMonth:
            return (calendar.date(byAdding: .month, value: -1, to: now) ?? now)...now
        case .lastYear:
            return (calendar.date(byAdding: .year, value: -1, to: now) ?? now)...now
        case .olderThanYear:
            return .distantPast...(calendar.date(byAdding: .year, value: -1, to: now) ?? now)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd))) ?? now
            return start...end
        }
    }

    private func isVisible(_ id: String, in range: ClosedRange<Date>?) -> Bool {
        guard let range else { return true }
        guard let date = assets[id]?.creationDate else { return false }
        return range.contains(date)
    }

    /// Tarih süzgecinden geçen gruplar; aralık dışındaki üyeler gruptan çıkar.
    func groups(of kind: GroupKind) -> [SimilarityGroup] {
        let range = dateRange
        return groups.compactMap { group in
            guard group.kind == kind else { return nil }
            guard range != nil else { return group }
            let members = group.memberIDs.filter { isVisible($0, in: range) }
            return members.count > 1 ? SimilarityGroup(kind: kind, memberIDs: members) : nil
        }
    }

    func ids(for category: FlatCategory) -> [String] {
        let all = flatIDs[category] ?? []
        let range = dateRange
        return range == nil ? all : all.filter { isVisible($0, in: range) }
    }

    /// Seçili olup tarih süzgecinden geçenler.
    var visibleSelection: [String] {
        let range = dateRange
        return selectedForDeletion.filter { isVisible($0, in: range) }
    }

    func totalSize(of ids: some Sequence<String>) -> Int64 {
        ids.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    // MARK: - Seçim

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

    /// Gruplarda önerilen dışındakileri seçer; favorilere dokunmaz.
    func selectAllButBest(in groups: [SimilarityGroup]) {
        for group in groups {
            selectedForDeletion.remove(group.suggestedKeepID)
            for id in group.memberIDs.dropFirst() where records[id]?.quality.isFavorite != true {
                selectedForDeletion.insert(id)
            }
        }
    }

    /// Verilen öğelerden seçili olanları siler.
    func deleteSelected(among ids: [String]) async {
        let targets = selectedForDeletion.intersection(ids)
        guard !targets.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let deleted = try await PhotoLibrary.delete(ids: Array(targets))
            let bytes = totalSize(of: deleted)
            remove(deleted)
            var message = "\(deleted.count) öğe silindi ve \"Son Silinenler\" albümüne taşındı. Albüm boşaltılınca \(bytes.formatted(.byteCount(style: .file))) yer açılacak."
            if ids.contains(where: { id in groups.contains { $0.memberIDs.contains(id) } }) {
                message += " Kopya ve benzer gruplarında her grubun en iyi fotoğrafı galeride kalır."
            }
            let failed = targets.count - deleted.count
            if failed > 0 {
                message += " \(failed) öğe silinemedi; hâlâ seçili duruyor."
            }
            notice = message
        } catch {
            // Kullanıcı iOS onayında "Vazgeç" derse de buraya düşer; bu bir hata değil.
            let code = (error as NSError).code
            if code != PHPhotosError.Code.userCancelled.rawValue && code != NSUserCancelledError {
                errorMessage = "Silme tamamlanmadı: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Hızlı gözden geçirme

    func markKept(_ id: String, _ kept: Bool) {
        if kept {
            keptInReview.insert(id)
        } else {
            keptInReview.remove(id)
        }
    }

    func saveKept() {
        UserDefaults.standard.set(Array(keptInReview), forKey: "keptInReview")
    }

    func forgetKept() {
        keptInReview.removeAll()
        saveKept()
    }

    private nonisolated static func months(of assets: [PHAsset]) -> [ReviewMonth] {
        let calendar = Calendar.current
        var byMonth: [Date: [(String, Date)]] = [:]
        for asset in assets {
            guard let date = asset.creationDate,
                  let month = calendar.dateInterval(of: .month, for: date)?.start else { continue }
            byMonth[month, default: []].append((asset.localIdentifier, date))
        }
        return byMonth
            .map { month, items in
                ReviewMonth(start: month, ids: items.sorted { $0.1 < $1.1 }.map(\.0))
            }
            .sorted { $0.start > $1.start }
    }

    // MARK: - Tarama

    private func scan(fromScratch: Bool) async {
        guard await PhotoLibrary.requestAccess() else {
            phase = .denied
            return
        }
        wasCancelled = false
        estimatedRemaining = nil
        isLimitedAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited

        let library = PhotoLibrary.fetchImageAssets()
        let videos = PhotoLibrary.fetchVideoAssets()
        assets = Dictionary(
            (library + videos).map { ($0.localIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        phase = .scanning(done: 0, total: library.count)

        // Değişmemiş fotoğraflar önbellekten gelir; yalnızca yeniler analiz edilir.
        isLoadingCache = !fromScratch
        let cache = fromScratch
            ? [:]
            : await Task.detached(priority: .userInitiated) { AnalysisCache.load() }.value
        isLoadingCache = false
        var analyses: [String: CachedAnalysis] = [:]
        var pending: [PHAsset] = []
        for asset in library {
            // Düzenlenmemiş fotoğrafın içeriği değişmez; iCloud eşitlemesi gibi
            // nedenlerle değişen tarih yeniden analiz gerektirmez.
            if let entry = cache[asset.localIdentifier],
               !asset.hasAdjustments || entry.modified == asset.modificationDate {
                analyses[asset.localIdentifier] = entry
            } else {
                pending.append(asset)
            }
        }
        phase = .scanning(done: analyses.count, total: library.count)

        // Tarama sürerken ekran kilitlenmesin; kilitlenirse iOS uygulamayı durdurur.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        let started = Date.now
        var lastSave = Date.now
        var processed = 0
        var skipped = 0
        await withTaskGroup(of: (String, CachedAnalysis?).self) { group in
            var next = 0
            func enqueue() {
                guard next < pending.count, !Task.isCancelled else { return }
                let asset = pending[next]
                next += 1
                // Takılan bir fotoğraf (galeri ya da Vision yanıt vermezse) taramayı
                // bekletmesin: 30 saniyede bitmezse atlanır, sonraki taramada yeniden denenir.
                group.addTask {
                    (asset.localIdentifier, await withTimeout(seconds: 30) { await Self.analyze(asset) })
                }
            }
            for _ in 0..<concurrency { enqueue() }
            for await (id, entry) in group {
                if let entry {
                    analyses[id] = entry
                } else {
                    skipped += 1
                }
                processed += 1
                // Ara kayıt: uygulama kapanırsa sonraki tarama buradan devam eder.
                // Önbellek dosyası büyük; sık yazmak taramayı yavaşlatır.
                if Date.now.timeIntervalSince(lastSave) > 120 {
                    lastSave = .now
                    saveCache(analyses)
                }
                if processed >= 20 {
                    let perItem = Date.now.timeIntervalSince(started) / Double(processed)
                    estimatedRemaining = perItem * Double(pending.count - processed)
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
        saveCache(analyses)

        let analyzed = library.compactMap { asset in
            analyses[asset.localIdentifier].map { Self.record(for: asset, analysis: $0) }
        }
        records = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })

        let screenshots = library
            .filter { $0.mediaSubtypes.contains(.photoScreenshot) }
            .map(\.localIdentifier)
        let screenshotSet = Set(screenshots)
        let photos = analyzed.reversed().filter { !screenshotSet.contains($0.id) }
        // Gruplama büyük arşivde bir saniyeyi bulabilir; arayüzü kilitlemesin.
        groups = await Task.detached(priority: .userInitiated) { Grouper.group(analyzed) }.value

        var flat: [FlatCategory: [String]] = [:]
        flat[.screenshots] = screenshots.reversed()
        flat[.blurry] = photos
            .filter { BlurCheck.isLikelyBlurry($0) }
            .sorted { ($0.quality.focus ?? $0.quality.sharpness ?? 0) < ($1.quality.focus ?? $1.quality.sharpness ?? 0) }
            .map(\.id)
        for category in FlatCategory.allCases {
            if let content = category.contentCategory {
                flat[category] = photos.filter { content.matches($0) }.map(\.id)
            }
        }
        selectedForDeletion = defaultSelection(for: groups)

        let selfieSet = PhotoLibrary.selfieIDs()
        let candidates = flat.values
            .reduce(into: Set(groups.flatMap(\.memberIDs))) { $0.formUnion($1) }
            .union(selfieSet)
        let sizeTargets = candidates.compactMap { assets[$0] } + videos
        sizes = await PhotoLibrary.fileSizes(of: sizeTargets)
        flat[.selfies] = library.reversed().map(\.localIdentifier).filter(selfieSet.contains)
        let recordings = videos.filter { $0.mediaSubtypes.contains(.videoScreenRecording) }
        flat[.screenRecordings] = recordings
            .map(\.localIdentifier)
            .sorted { (sizes[$0] ?? 0) > (sizes[$1] ?? 0) }
        flat[.shortVideos] = videos
            .filter { $0.duration < 3 && !$0.mediaSubtypes.contains(.videoScreenRecording) }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            .map(\.localIdentifier)
        reviewMonths = Self.months(of: library + videos)
        flat[.largeVideos] = videos
            .map(\.localIdentifier)
            .filter { (sizes[$0] ?? 0) >= largeVideoBytes }
            .sorted { (sizes[$0] ?? 0) > (sizes[$1] ?? 0) }
        flatIDs = flat
        phase = .finished
    }

    /// Kayıtlar sırayla yazılır. Büyük dosyayı kodlamak saniyeler sürer ve
    /// iş parçacığını bloklar; bu yüzden Swift'in ortak havuzu yerine ayrı kuyrukta.
    private static let saveQueue = DispatchQueue(label: "photosweep.cache-save", qos: .utility)

    private func saveCache(_ entries: [String: CachedAnalysis]) {
        Self.saveQueue.async { AnalysisCache.save(entries) }
    }

    private func remove(_ removed: Set<String>) {
        selectedForDeletion.subtract(removed)
        groups = groups.compactMap { group in
            let remaining = group.memberIDs.filter { !removed.contains($0) }
            guard remaining.count > 1 else { return nil }
            return SimilarityGroup(kind: group.kind, memberIDs: remaining)
        }
        for category in flatIDs.keys {
            flatIDs[category]?.removeAll(where: removed.contains)
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
                focus: analysis.focus,
                contrast: analysis.contrast,
                faceQuality: analysis.faceQuality,
                aesthetics: analysis.aesthetics,
                isFavorite: asset.isFavorite
            ),
            labels: analysis.labels
        )
    }
}

/// İşlem süre içinde biterse sonucunu, bitmezse ya da görev iptal edilirse nil döner.
/// İşlemin kendisi arka planda sürebilir; bekleyen taraf onu beklemez.
func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async -> T?
) async -> T? {
    let once = ResumeOnce<T>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            once.store(continuation)
            Task {
                let value = await operation()
                once.resume(with: value)
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(with: nil)
            }
        }
    } onCancel: {
        once.resume(with: nil)
    }
}

/// Bir devamı yalnızca bir kez sürdürür; kim önce gelirse onun değeri geçer.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var finished = false

    func store(_ continuation: CheckedContinuation<T?, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(returning: nil)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resume(with value: T?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
