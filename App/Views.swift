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
                    ProgressView(value: Double(done), total: Double(max(total, 1))) {
                        Text("Taranıyor")
                    } currentValueLabel: {
                        Text("\(done) / \(total)")
                    }
                    .padding(32)
                case .finished:
                    GroupsListView()
                }
            }
            .navigationTitle("Photo Sweep")
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
            Text("Kopya ve benzer fotoğrafları bulur, hangisini saklayacağınızı önerir. Tarama tamamen telefonda yapılır; hiçbir fotoğraf dışarı gönderilmez.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Taramayı başlat") {
                Task { await model.scan() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

private struct GroupsListView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        List(model.groups) { group in
            NavigationLink {
                GroupDetailView(group: group)
            } label: {
                GroupRow(group: group)
            }
        }
        .overlay {
            if model.groups.isEmpty {
                ContentUnavailableView("Benzer fotoğraf bulunamadı", systemImage: "checkmark.circle")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.selectedCount > 0 {
                Button(role: .destructive) {
                    Task { await model.deleteSelected() }
                } label: {
                    Text("Seçilen \(model.selectedCount) fotoğrafı sil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
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
        let kind = group.kind == .duplicate ? "Kopya" : "Benzer"
        let selected = group.memberIDs.filter(model.selectedForDeletion.contains).count
        return "\(kind) · \(group.memberIDs.count) fotoğraf · \(selected) silinecek"
    }
}

private struct GroupDetailView: View {
    @Environment(ScanModel.self) private var model
    let group: SimilarityGroup

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(group.memberIDs, id: \.self) { id in
                    let selected = model.selectedForDeletion.contains(id)
                    AssetThumbnail(asset: model.assets[id], side: 110)
                        .overlay(alignment: .topLeading) {
                            if id == group.suggestedKeepID {
                                Text("Önerilen")
                                    .font(.caption2.bold())
                                    .padding(4)
                                    .background(.green, in: .capsule)
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
            .padding(4)
            Text("Dokunarak saklanacak ve silinecek fotoğrafları değiştirebilirsiniz.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
        .navigationTitle(group.kind == .duplicate ? "Kopyalar" : "Benzerler")
        .navigationBarTitleDisplayMode(.inline)
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
            .clipShape(.rect(cornerRadius: 6))
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                image = await PhotoLibrary.thumbnail(for: asset, side: side * displayScale)
            }
    }
}
