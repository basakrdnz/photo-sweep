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
                    ContentUnavailableView(
                        "Fotoğraflara erişim yok",
                        systemImage: "lock",
                        description: Text("Ayarlar > Gizlilik > Fotoğraflar'dan izin verebilirsiniz.")
                    )
                case let .scanning(done, total):
                    VStack(spacing: 24) {
                        ProgressView(value: Double(done), total: Double(max(total, 1))) {
                            Text("Taranıyor")
                        } currentValueLabel: {
                            Text("\(done) / \(total)")
                        }
                        Text("İlk tarama arşivin büyüklüğüne göre birkaç dakika sürebilir. Sonraki taramalar yalnızca yeni fotoğrafları işler.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Durdur ve sonuçları göster") { model.cancelScan() }
                    }
                    .padding(32)
                case .organizing:
                    ProgressView("Sonuçlar hazırlanıyor")
                case .finished:
                    SummaryView()
                }
            }
            .navigationTitle("Photo Sweep")
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
    }
}

private struct StartView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Kopya ve benzer fotoğrafları, ekran görüntülerini, bulanık fotoğrafları ve büyük videoları bulur. Tarama tamamen telefonda yapılır; hiçbir fotoğraf dışarı gönderilmez.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Taramayı başlat") { model.startScan() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

private struct SummaryView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        List {
            Section {
                let selected = model.totalSize(of: model.selectedForDeletion)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatBytes(selected))
                        .font(.largeTitle.bold())
                    Text("seçili \(model.selectedCount) öğe silinirse açılacak alan")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                if model.wasCancelled {
                    Text("Tarama yarıda kesildi; sonuçlar taranan fotoğraflara göre. Yeniden tarayınca kaldığı yerden devam eder.")
                }
            }

            Section {
                let duplicates = model.groups(of: .duplicate)
                CategoryRow(
                    title: "Kopyalar",
                    systemImage: "square.on.square",
                    count: duplicates.count,
                    unit: "grup",
                    bytes: model.totalSize(of: duplicates.flatMap(\.memberIDs))
                ) {
                    GroupsListView(kind: .duplicate)
                }
                let similar = model.groups(of: .similar)
                CategoryRow(
                    title: "Benzerler",
                    systemImage: "rectangle.stack",
                    count: similar.count,
                    unit: "grup",
                    bytes: model.totalSize(of: similar.flatMap(\.memberIDs))
                ) {
                    GroupsListView(kind: .similar)
                }
                ForEach([FlatCategory.screenshots, .blurry, .largeVideos], id: \.self) { category in
                    let ids = model.ids(for: category)
                    CategoryRow(
                        title: category.title,
                        systemImage: category.systemImage,
                        count: ids.count,
                        unit: "öğe",
                        bytes: model.totalSize(of: ids)
                    ) {
                        AssetGridView(category: category)
                    }
                }
            } footer: {
                if model.skippedCount > 0 {
                    Text("\(model.skippedCount) fotoğraf yalnızca iCloud'da durduğu için taranamadı.")
                }
            }
        }
        .toolbar {
            Button("Yeniden tara") { model.startScan() }
        }
    }
}

private extension ScanModel {
    var selectedCount: Int { selectedForDeletion.count }
}

private struct CategoryRow<Destination: View>: View {
    let title: String
    let systemImage: String
    let count: Int
    let unit: String
    let bytes: Int64
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(count) \(unit)")
                    Text(formatBytes(bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(count == 0)
    }
}

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
                Text("\(selected.count) öğeyi sil · \(formatBytes(model.totalSize(of: selected)))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
    }
}

private struct GroupsListView: View {
    @Environment(ScanModel.self) private var model
    let kind: GroupKind

    var body: some View {
        let groups = model.groups(of: kind)
        List(groups) { group in
            NavigationLink {
                GroupDetailView(members: Set(group.memberIDs))
            } label: {
                GroupRow(group: group)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        AssetThumbnail(asset: model.assets[id], side: 64)
                            .opacity(model.selectedForDeletion.contains(id) ? 0.4 : 1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        let selected = group.memberIDs.filter(model.selectedForDeletion.contains).count
        return "\(group.memberIDs.count) fotoğraf · \(selected) silinecek"
    }
}

private struct GroupDetailView: View {
    @Environment(ScanModel.self) private var model
    /// Grup, silmeden sonra da bulunabilsin diye üyeleriyle aranır.
    let members: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        if let group = model.groups.first(where: { !members.isDisjoint(with: $0.memberIDs) }) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(group.memberIDs, id: \.self) { id in
                        SelectableThumbnail(id: id, isSuggested: id == group.suggestedKeepID)
                    }
                }
                .padding(4)
                Text("Dokunarak saklanacak ve silinecek fotoğrafları değiştirebilirsiniz.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                DeleteBar(ids: group.memberIDs)
            }
            .navigationTitle(group.kind == .duplicate ? "Kopyalar" : "Benzerler")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Bu grup temizlendi", systemImage: "checkmark.circle")
        }
    }
}

private struct AssetGridView: View {
    @Environment(ScanModel.self) private var model
    let category: FlatCategory

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        let ids = model.ids(for: category)
        let allSelected = !ids.isEmpty && ids.allSatisfy(model.selectedForDeletion.contains)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    SelectableThumbnail(id: id, isSuggested: false, showsSize: true)
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
                model.setSelected(ids, !allSelected)
            }
            .disabled(ids.isEmpty)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SelectableThumbnail: View {
    @Environment(ScanModel.self) private var model
    let id: String
    let isSuggested: Bool
    var showsSize = false

    var body: some View {
        let selected = model.selectedForDeletion.contains(id)
        AssetThumbnail(asset: model.assets[id], side: 110)
            .overlay(alignment: .topLeading) {
                if isSuggested {
                    Text("Önerilen")
                        .font(.caption2.bold())
                        .padding(4)
                        .background(.green, in: .capsule)
                        .foregroundStyle(.white)
                        .padding(4)
                }
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
                    .foregroundStyle(.white, selected ? Color.red : Color.green)
                    .padding(4)
            }
            .onTapGesture { model.toggle(id) }
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
                }
            }
            .overlay(alignment: .topTrailing) {
                if let asset, asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                image = await PhotoLibrary.thumbnail(for: asset, side: side * displayScale)
            }
    }
}
