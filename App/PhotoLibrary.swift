import Photos
import UIKit

/// Fotoğraflar kütüphanesine tüm erişim buradan geçer.
enum PhotoLibrary {
    /// Okuma ve silme izni ister. Kısıtlı erişimde (seçili fotoğraflar) de çalışır.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Tüm fotoğraflar (videolar hariç), eskiden yeniye.
    static func fetchImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Tüm videolar.
    static func fetchVideoAssets() -> [PHAsset] {
        let result = PHAsset.fetchAssets(with: .video, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Sistemin "Selfie'ler" akıllı albümündeki öğelerin kimlikleri.
    static func selfieIDs() -> Set<String> {
        var ids = Set<String>()
        PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            .enumerateObjects { collection, _, _ in
                PHAsset.fetchAssets(in: collection, options: nil)
                    .enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
            }
        return ids
    }

    /// Telefonda kapladığı alan (düzenlenmiş sürümler dahil tüm kaynaklar).
    /// iCloud'da optimize edilmiş öğelerde tam boyut döner.
    static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(0) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? Int64) ?? 0)
        }
    }

    static func assets(withIDs ids: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Analiz için küçük önizleme. iCloud'dan indirme yapmaz; telefonda
    /// önizlemesi olmayan fotoğraf için nil döner ve atlanır.
    static func analysisImage(for asset: PHAsset, side: CGFloat = 300) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    /// Ekranda gösterilecek önizleme; gerekirse iCloud'dan indirir.
    static func thumbnail(
        for asset: PHAsset,
        side: CGFloat,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: contentMode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Seçilenleri siler. iOS her seferinde kendi onayını sorar; silinenler
    /// 30 gün boyunca "Son Silinenler" albümünde durur.
    /// Silmeden sonra kütüphaneye yeniden bakar; gerçekten silinenlerin
    /// kimliklerini döner. iOS bir öğeyi sessizce bırakırsa sonuçta yer almaz.
    static func delete(ids: [String]) async throws -> Set<String> {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        var remaining = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in remaining.insert(asset.localIdentifier) }
        return Set(ids).subtracting(remaining)
    }
}
