import AVFoundation
import Photos
import SwiftUI
import SweepCore

struct ContentView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:
                    StartView()
                case .denied:
                    ContentUnavailableView {
                        Label("Fotoğraflara erişim yok", systemImage: "lock")
                    } description: {
                        Text("Taramak için Ayarlar'dan fotoğraflara erişim verin.")
                    } actions: {
                        OpenSettingsButton()
                            .buttonStyle(.borderedProminent)
                    }
                case let .scanning(done, total):
                    ScanningView(done: done, total: total)
                case .organizing:
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Sonuçlar hazırlanıyor")
                            .foregroundStyle(.secondary)
                    }
                case .finished:
                    SummaryView()
                }
            }
            .animation(.default, value: model.phase)
        }
        .disabled(model.isDeleting)
        .overlay {
            if model.isDeleting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Siliniyor…")
                    }
                    .padding(28)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
        }
        .alert(
            "Hata",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(
            "Silindi",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            )
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

private struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL
    var title = "Ayarları aç"

    var body: some View {
        Button(title) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }
}

// MARK: - Başlangıç ve tarama

private struct StartView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                WavingMascot()
                    .padding(.top, 8)
                VStack(spacing: 8) {
                    Text("Başak'ın Photo Sweep uygulamasına hoş geldiniz")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Kopyaları, benzer kareleri ve gereksiz fotoğrafları bulur, hangisini saklayacağını önerir.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(systemImage: "lock.shield", title: "Tamamen telefonda", text: "Hiçbir fotoğraf dışarı gönderilmez.")
                    FeatureRow(systemImage: "arrow.uturn.backward.circle", title: "Geri alınabilir", text: "Silinenler 30 gün \"Son Silinenler\"de durur.")
                    FeatureRow(systemImage: "star.circle", title: "Favorilere dokunmaz", text: "Favoriler asla otomatik seçilmez.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.startScan()
            } label: {
                Text("Taramayı başlat")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.white)
        }
        // Memoji videosunun beyaz zeminiyle birleşsin diye bu ekran her zaman açık renkte.
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

/// Başak'ın el sallayan Memoji videosu; sessiz ve sonsuz döngüde oynar.
/// "Hareketi Azalt" açıksa yerine durağan Memoji gösterilir.
private struct WavingMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !reduceMotion, let url = Bundle.main.url(forResource: "MascotWave", withExtension: "mp4") {
                // Videonun arka planı da beyaz; çerçevesiz durunca el sayfaya taşıyor gibi görünür.
                LoopingVideo(url: url)
                    .frame(width: 240, height: 240)
            } else {
                Image("Mascot")
                    .resizable()
                    .scaledToFit()
                    .clipShape(.circle)
                    .frame(width: 190, height: 190)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Arka planda çalan müziği kesmesin.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        view.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .white
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    final class PlayerView: UIView {
        var looper: AVPlayerLooper?
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScanningView: View {
    @Environment(ScanModel.self) private var model
    let done: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: fraction)
                VStack(spacing: 4) {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("\(done) / \(total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 220, height: 220)

            VStack(spacing: 6) {
                Text(model.isLoadingCache ? "Önceki tarama yükleniyor…" : "Fotoğraflar inceleniyor")
                    .font(.title3.bold())
                if let remaining = model.estimatedRemaining, remaining > 5 {
                    Text("Yaklaşık \(remainingText(remaining)) kaldı")
                        .foregroundStyle(.secondary)
                }
                Text("Uygulamayı açık tutun. Sonraki taramalar yalnızca yeni fotoğrafları işler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            Spacer()
            Button("Durdur ve sonuçları göster") { model.cancelScan() }
                .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private func remainingText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 1 ? "1 dakika" : "\(minutes) dakika"
    }
}

// MARK: - Özet

private extension FlatCategory {
    var color: Color {
        switch self {
        case .screenshots: .indigo
        case .blurry: .gray
        case .documents: .brown
        case .food: .orange
        case .landscape: .green
        case .pets: .pink
        case .selfies: .cyan
        case .screenRecordings: .mint
        case .shortVideos: .yellow
        case .largeVideos: .red
        }
    }
}

private struct SummaryView: View {
    @Environment(ScanModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SavingsCard()

                NavigationLink {
                    ReviewMonthsView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.draw.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.orange.gradient, in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hızlı gözden geçir")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Ay ay kaydır: sola sil, sağa sakla.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.background, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                DateFilterBar()

                if model.isLimitedAccess {
                    InfoCard(systemImage: "exclamationmark.triangle", text: "Yalnızca seçtiğiniz fotoğraflara erişim var; kopyaların çoğu gözden kaçabilir.") {
                        OpenSettingsButton(title: "Tüm fotoğraflara izin ver")
                    }
                }
                if model.wasCancelled {
                    InfoCard(systemImage: "pause.circle", text: "Tarama yarıda kesildi; sonuçlar taranan fotoğraflara göre. Yeniden tarayınca kaldığı yerden devam eder.") {
                        Button("Taramaya devam et") { model.startScan() }
                    }
                }

                SectionTitle("Benzerlik")
                LazyVGrid(columns: columns, spacing: 12) {
                    let duplicates = model.groups(of: .duplicate)
                    CategoryTile(
                        title: "Kopyalar",
                        systemImage: "square.on.square",
                        color: .blue,
                        countText: "\(duplicates.count) grup",
                        bytes: model.totalSize(of: duplicates.flatMap { $0.memberIDs.dropFirst() }),
                        isEmpty: duplicates.isEmpty
                    ) {
                        GroupsListView(kind: .duplicate)
                    }
                    let similar = model.groups(of: .similar)
                    CategoryTile(
                        title: "Benzerler",
                        systemImage: "rectangle.stack",
                        color: .purple,
                        countText: "\(similar.count) grup",
                        bytes: model.totalSize(of: similar.flatMap { $0.memberIDs.dropFirst() }),
                        isEmpty: similar.isEmpty
                    ) {
                        GroupsListView(kind: .similar)
                    }
                }

                SectionTitle("Kategoriler")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FlatCategory.allCases, id: \.self) { category in
                        let ids = model.ids(for: category)
                        CategoryTile(
                            title: category.title,
                            systemImage: category.systemImage,
                            color: category.color,
                            countText: "\(ids.count) öğe",
                            bytes: model.totalSize(of: ids),
                            isEmpty: ids.isEmpty
                        ) {
                            AssetGridView(category: category)
                        }
                    }
                }

                if model.skippedCount > 0 {
                    Text("\(model.skippedCount) fotoğraf yalnızca iCloud'da durduğu için taranamadı.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Photo Sweep")
        .refreshable { model.startScan() }
        .toolbar {
            Menu {
                Button {
                    model.startScan()
                } label: {
                    Label("Yeni fotoğrafları tara", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    model.startScan(fromScratch: true)
                } label: {
                    Label("Baştan tara (her şeyi yeniden incele)", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Label("Tara", systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .padding(.top, 4)
    }
}

private struct SavingsCard: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        let selection = model.visibleSelection
        VStack(alignment: .leading, spacing: 6) {
            Text("Açılabilecek alan")
                .font(.subheadline.weight(.medium))
                .opacity(0.85)
            Text(formatBytes(model.totalSize(of: selection)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(selection.isEmpty
                 ? "Silmek istediklerinizi kategorilerden seçin."
                 : "Seçili \(selection.count) öğe. Kopya ve benzerlerde en iyisi dışındakiler önceden seçildi.")
                .font(.footnote)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20)
        )
    }
}

private struct DateFilterBar: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DateFilter.allCases, id: \.self) { filter in
                        let isOn = model.dateFilter == filter
                        Button {
                            withAnimation { model.dateFilter = filter }
                        } label: {
                            Text(filter.title)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.background), in: .capsule)
                                .foregroundStyle(isOn ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if model.dateFilter == .custom {
                HStack {
                    DatePicker("Başlangıç", selection: $model.customStart, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                    Text("–")
                    DatePicker("Bitiş", selection: $model.customEnd, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct InfoCard<Action: View>: View {
    let systemImage: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.subheadline)
                action().font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 14))
    }
}

private struct CategoryTile<Destination: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let countText: String
    let bytes: Int64
    let isEmpty: Bool
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(color.gradient, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(isEmpty ? "Temiz" : "\(countText) · \(formatBytes(bytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background, in: .rect(cornerRadius: 16))
            .opacity(isEmpty ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
    }
}

// MARK: - Silme çubuğu

/// Ekranın altındaki silme düğmesi; yalnızca bu ekrandaki seçilileri siler.
private struct DeleteBar: View {
    @Environment(ScanModel.self) private var model
    let ids: [String]

    var body: some View {
        let selected = ids.filter(model.selectedForDeletion.contains)
        if !selected.isEmpty {
            Button(role: .destructive) {
                Task { await model.deleteSelected(among: ids) }
            } label: {
                VStack(spacing: 2) {
                    Text("\(selected.count) öğeyi sil")
                        .font(.headline)
                    Text(formatBytes(model.totalSize(of: selected)))
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

// MARK: - Gruplar

private struct GroupsListView: View {
    @Environment(ScanModel.self) private var model
    let kind: GroupKind

    var body: some View {
        let groups = model.groups(of: kind)
        List {
            if !groups.isEmpty {
                Section {
                    Button {
                        withAnimation { model.selectAllButBest(in: groups) }
                    } label: {
                        Label("Hepsinde yalnızca en iyisini tut", systemImage: "wand.and.stars")
                    }
                    Button {
                        withAnimation { model.setSelected(groups.flatMap(\.memberIDs), false) }
                    } label: {
                        Label("Seçimi temizle", systemImage: "xmark.circle")
                    }
                } footer: {
                    Text(kind == .duplicate
                         ? "Aynı fotoğrafın kopyaları. Her grupta en iyi kalitedeki saklanır."
                         : "Art arda çekilmiş benzer kareler. Silmeden önce gruba girip bakmanızı öneririz.")
                }
            }
            ForEach(groups) { group in
                NavigationLink {
                    GroupDetailView(members: Set(group.memberIDs))
                } label: {
                    GroupRow(group: group)
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Hepsi temizlendi", systemImage: "checkmark.circle")
            }
        }
        .safeAreaInset(edge: .bottom) {
            DeleteBar(ids: groups.flatMap(\.memberIDs))
        }
        .navigationTitle(kind == .duplicate ? "Kopyalar" : "Benzerler")
    }
}

private struct GroupRow: View {
    @Environment(ScanModel.self) private var model
    let group: SimilarityGroup

    var body: some View {
        let selected = group.memberIDs.filter(model.selectedForDeletion.contains)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.memberIDs.count) fotoğraf")
                    .font(.headline)
                Spacer()
                if !selected.isEmpty {
                    Text("\(selected.count) silinecek · \(formatBytes(model.totalSize(of: selected)))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        AssetThumbnail(asset: model.assets[id], side: 64)
                            .overlay(alignment: .topLeading) {
                                if id == group.suggestedKeepID {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                        .padding(3)
                                        .background(.black.opacity(0.5), in: .circle)
                                        .padding(3)
                                }
                            }
                            .opacity(model.selectedForDeletion.contains(id) ? 0.35 : 1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GroupDetailView: View {
    @Environment(ScanModel.self) private var model
    /// Grup, silmeden sonra da bulunabilsin diye üyeleriyle aranır.
    let members: Set<String>
    @State private var viewer: ViewerItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        if let group = model.groups.first(where: { !members.isDisjoint(with: $0.memberIDs) }) {
            ScrollView {
                Text("Dokunarak saklanacak ve silinecekleri değiştirin. Büyütmek için büyüteçe basın.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        SelectableThumbnail(id: id, isSuggested: id == group.suggestedKeepID) {
                            viewer = ViewerItem(ids: group.memberIDs, start: id)
                        }
                    }
                }
                .padding(4)
            }
            .safeAreaInset(edge: .bottom) {
                DeleteBar(ids: group.memberIDs)
            }
            .toolbar {
                Button("En iyisini tut") {
                    withAnimation { model.selectAllButBest(in: [group]) }
                }
            }
            .fullScreenCover(item: $viewer) { item in
                PhotoViewer(item: item, suggestedID: group.suggestedKeepID)
            }
            .navigationTitle(group.kind == .duplicate ? "Kopyalar" : "Benzerler")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Bu grup temizlendi", systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Kategori ızgarası

private struct AssetGridView: View {
    @Environment(ScanModel.self) private var model
    let category: FlatCategory
    @State private var viewer: ViewerItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        let ids = model.ids(for: category)
        let allSelected = !ids.isEmpty && ids.allSatisfy(model.selectedForDeletion.contains)
        ScrollView {
            Text(category.subtitle + " Hiçbiri kendiliğinden seçilmez.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    SelectableThumbnail(id: id, isSuggested: false, showsSize: true) {
                        viewer = ViewerItem(ids: ids, start: id)
                    }
                }
            }
            .padding(4)
        }
        .overlay {
            if ids.isEmpty {
                ContentUnavailableView("Hepsi temizlendi", systemImage: "checkmark.circle")
            }
        }
        .safeAreaInset(edge: .bottom) {
            DeleteBar(ids: ids)
        }
        .toolbar {
            Button(allSelected ? "Seçimi kaldır" : "Tümünü seç") {
                withAnimation { model.setSelected(ids, !allSelected) }
            }
            .disabled(ids.isEmpty)
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(item: item, suggestedID: nil)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Küçük resimler

private struct SelectableThumbnail: View {
    @Environment(ScanModel.self) private var model
    let id: String
    let isSuggested: Bool
    var showsSize = false
    let onExpand: () -> Void

    var body: some View {
        let selected = model.selectedForDeletion.contains(id)
        AssetThumbnail(asset: model.assets[id], side: 110)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.25))
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.red, lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSuggested {
                    Label("En iyi", systemImage: "star.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.green, in: .capsule)
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: .circle)
                }
                .padding(4)
                .accessibilityLabel("Büyüt")
            }
            .overlay(alignment: .bottomLeading) {
                if showsSize, let bytes = model.sizes[id] {
                    Text(formatBytes(bytes))
                        .font(.caption2.bold())
                        .padding(3)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: selected ? "trash.circle.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? Color.red : Color.green)
                    .padding(4)
            }
            .contentShape(.rect)
            .onTapGesture { model.toggle(id) }
            .sensoryFeedback(.selection, trigger: selected)
            .accessibilityLabel(selected ? "Silinecek" : "Saklanacak")
            .accessibilityAddTraits(.isButton)
    }
}

private struct AssetThumbnail: View {
    let asset: PHAsset?
    let side: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.secondary.opacity(0.15)
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let asset, asset.mediaType == .video, side < 100 {
                    VideoBadge(duration: asset.duration)
                }
            }
            .overlay(alignment: .bottom) {
                if let asset, asset.mediaType == .video, side >= 100 {
                    VideoBadge(duration: asset.duration)
                        .padding(.bottom, 28)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                let loaded = await PhotoLibrary.thumbnail(for: asset, side: side * displayScale)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
    }
}

private struct VideoBadge: View {
    let duration: TimeInterval

    var body: some View {
        Label(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)), systemImage: "play.fill")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(4)
    }
}

// MARK: - Tam ekran görüntüleyici

private struct ViewerItem: Identifiable {
    let ids: [String]
    let start: String
    var id: String { start }
}

/// Fotoğrafları büyük görüp kaydırarak karşılaştırmak ve seçimi oradan değiştirmek için.
private struct PhotoViewer: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ViewerItem
    let suggestedID: String?
    @State private var current: String

    init(item: ViewerItem, suggestedID: String?) {
        self.item = item
        self.suggestedID = suggestedID
        _current = State(initialValue: item.start)
    }

    var body: some View {
        let selected = model.selectedForDeletion.contains(current)
        NavigationStack {
            TabView(selection: $current) {
                ForEach(item.ids, id: \.self) { id in
                    LargePhoto(asset: model.assets[id])
                        .tag(id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    HStack {
                        if current == suggestedID {
                            Label("Önerilen", systemImage: "star.fill")
                                .foregroundStyle(.green)
                        }
                        if let date = model.assets[current]?.creationDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                        }
                        Spacer()
                        if let bytes = model.sizes[current] {
                            Text(formatBytes(bytes))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    Button {
                        withAnimation { model.toggle(current) }
                    } label: {
                        Label(selected ? "Silinecek · Sakla" : "Saklanacak · Silinecek yap",
                              systemImage: selected ? "trash.fill" : "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected ? .red : .green)
                    .controlSize(.large)
                    .sensoryFeedback(.selection, trigger: selected)
                }
                .padding()
                .background(.black.opacity(0.6))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if let index = item.ids.firstIndex(of: current) {
                        Text("\(index + 1) / \(item.ids.count)")
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct LargePhoto: View {
    let asset: PHAsset?
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                let side = max(proxy.size.width, proxy.size.height) * displayScale
                image = await PhotoLibrary.thumbnail(for: asset, side: side, contentMode: .aspectFit)
            }
        }
    }
}

// MARK: - Hızlı gözden geçirme

private struct ReviewMonthsView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.reviewMonths) { month in
                    let pending = month.ids.filter { !model.keptInReview.contains($0) && model.assets[$0] != nil }
                    NavigationLink {
                        SwipeReviewView(title: month.title, ids: pending)
                    } label: {
                        HStack {
                            Text(month.title)
                            Spacer()
                            Text(pending.isEmpty ? "Bitti" : "\(pending.count)")
                                .foregroundStyle(pending.isEmpty ? .green : .secondary)
                                .monospacedDigit()
                        }
                    }
                    .disabled(pending.isEmpty)
                }
            } footer: {
                Text("Sola kaydırdıkların silinmek üzere işaretlenir, sağa kaydırdıkların bir daha karşına çıkmaz. Bitirince işaretlediklerini tek seferde silersin.")
            }
            if !model.keptInReview.isEmpty {
                Section {
                    Button("Saklananları yeniden göster", role: .destructive) {
                        model.forgetKept()
                    }
                }
            }
        }
        .navigationTitle("Hızlı gözden geçir")
    }
}

private struct SwipeReviewView: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let ids: [String]

    @State private var index = 0
    @State private var decisions: [(id: String, delete: Bool)] = []
    @State private var drag: CGSize = .zero
    @State private var isAnimating = false

    private var marked: [String] { decisions.filter { $0.delete }.map { $0.id } }

    var body: some View {
        VStack(spacing: 16) {
            if index < ids.count {
                card
                info
                controls
            } else {
                finished
            }
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if index < ids.count && !decisions.isEmpty {
                Button("Bitir") { index = ids.count }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: index)
        .onDisappear { model.saveKept() }
    }

    private var card: some View {
        ZStack {
            if index + 1 < ids.count {
                ReviewCard(asset: model.assets[ids[index + 1]])
                    .id(ids[index + 1])
                    .scaleEffect(0.94)
                    .opacity(0.5)
            }
            ReviewCard(asset: model.assets[ids[index]])
                .id(ids[index])
                .overlay(alignment: .topLeading) {
                    Stamp(text: "SAKLA", color: .green)
                        .opacity(Double(max(0, drag.width)) / 100)
                }
                .overlay(alignment: .topTrailing) {
                    Stamp(text: "SİL", color: .red)
                        .opacity(Double(max(0, -drag.width)) / 100)
                }
                .offset(x: drag.width, y: drag.height * 0.2)
                .rotationEffect(.degrees(Double(drag.width) / 25))
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            if value.translation.width < -100 {
                                decide(delete: true)
                            } else if value.translation.width > 100 {
                                decide(delete: false)
                            } else {
                                withAnimation(.spring) { drag = .zero }
                            }
                        }
                )
        }
        .frame(maxHeight: .infinity)
    }

    private var info: some View {
        let id = ids[index]
        return HStack {
            if let date = model.assets[id]?.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
            if model.assets[id]?.isFavorite == true {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            Spacer()
            Text("\(index + 1) / \(ids.count)")
                .monospacedDigit()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            RoundButton(systemImage: "arrow.uturn.backward", color: .gray, size: 52) { undo() }
                .disabled(decisions.isEmpty)
                .accessibilityLabel("Geri al")
            RoundButton(systemImage: "xmark", color: .red, size: 72) { decide(delete: true) }
                .accessibilityLabel("Sil")
            RoundButton(systemImage: "checkmark", color: .green, size: 72) { decide(delete: false) }
                .accessibilityLabel("Sakla")
        }
    }

    private var finished: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: marked.isEmpty ? "checkmark.circle.fill" : "trash.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(marked.isEmpty ? .green : .red)
            Text(marked.isEmpty ? "Hepsini sakladın" : "\(marked.count) öğe silinmek üzere işaretlendi")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            if !marked.isEmpty {
                Text("Silinenler 30 gün \"Son Silinenler\"de durur.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !marked.isEmpty {
                Button(role: .destructive) {
                    Task {
                        await model.deleteSelected(among: marked)
                        dismiss()
                    }
                } label: {
                    Text("\(marked.count) öğeyi sil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            Button(marked.isEmpty ? "Kapat" : "Silmeden çık (işaretliler seçili kalır)") { dismiss() }
            if !decisions.isEmpty {
                Button("Geri dön, son karara") { undo() }
                    .font(.footnote)
            }
        }
    }

    private func decide(delete: Bool) {
        guard index < ids.count, !isAnimating else { return }
        isAnimating = true
        let id = ids[index]
        decisions.append((id, delete))
        model.setSelected([id], delete)
        model.markKept(id, !delete)
        withAnimation(.easeOut(duration: 0.18)) {
            drag = CGSize(width: delete ? -700 : 700, height: 0)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            index += 1
            drag = .zero
            isAnimating = false
        }
    }

    private func undo() {
        guard let last = decisions.popLast() else { return }
        model.setSelected([last.id], false)
        model.markKept(last.id, false)
        index = max(0, index - 1)
        drag = .zero
    }
}

private struct ReviewCard: View {
    let asset: PHAsset?

    var body: some View {
        LargePhoto(asset: asset)
            .background(Color.black)
            .clipShape(.rect(cornerRadius: 20))
            .overlay(alignment: .bottomLeading) {
                if let asset, asset.mediaType == .video {
                    VideoBadge(duration: asset.duration)
                        .padding(8)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

private struct Stamp: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.title.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(text == "SİL" ? 12 : -12))
            .padding(24)
    }
}

private struct RoundButton: View {
    let systemImage: String
    let color: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(.background, in: .circle)
                .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 2))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
