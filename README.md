# Photo Sweep

iPhone'daki fotoğraf arşivini tarayıp kopya ve benzer fotoğrafları gruplayan, her grupta hangisinin saklanacağını öneren ve seçtiklerinizi silmenize yardım eden uygulama. Ekran görüntülerini, bulanık fotoğrafları ve büyük videoları da listeler; her kategoride açılacak alanı gösterir.

Arkadaşlara dağıtım: [DAGITIM.md](DAGITIM.md).

- **Gizli:** Tüm analiz telefonda yapılır. Sunucu yok, hiçbir fotoğraf dışarı gönderilmez.
- **Güvenli:** Otomatik silme yok. Silme iOS'un kendi onayından geçer, silinenler 30 gün "Son Silinenler"de durur. Favoriler hiçbir zaman otomatik seçilmez.

## Nasıl çalışır

| Katman | Neyi bulur | Yöntem | Nerede aranır |
|---|---|---|---|
| Kopya | Aynı fotoğrafın kopyası, küçültülmüş ya da sıkıştırılmış hali | 64 bit görsel parmak izi (dHash), en fazla 4 bit fark, aynı en-boy oranı | Tüm arşiv |
| Benzer | Aynı sahneden art arda çekilmiş kareler | Vision feature print uzaklığı ya da yakın dHash; uzun zincirler kümenin en az yarısına benzerlik şartıyla bölünür | Aralarında en fazla 2 dakika olan fotoğraflar |
| Bulanık | Ciddi biçimde bulanık kareler | 256 piksellik önizlemede Laplace varyansı eşiği; favoriler hariç, otomatik seçilmez | Tüm arşiv |

Her grupta öneri şu sinyallerle yapılır: favori olmak, netlik (Laplace varyansı), yüz çekim kalitesi, estetik puanı (iOS 18+) ve çözünürlük. Ayrıntılar: [Packages/SweepCore/Sources/SweepCore/BestPicker.swift](Packages/SweepCore/Sources/SweepCore/BestPicker.swift).

Eşikler şimdilik ilk tahmin. Etiketli bir test setiyle ayarlanacaklar (bkz. [PLAN.md](PLAN.md)).

## Klasörler

- `Packages/SweepCore/` — benzerlik, gruplama ve öneri mantığı. Saf Swift; Apple kütüphanelerine bağımlı değil, Linux'ta da test edilir.
- `App/` — SwiftUI uygulaması: fotoğraf izni (PhotoKit), Vision analizi, ekranlar.
- `project.yml` — Xcode projesinin tanımı ([XcodeGen](https://github.com/yonaskolb/XcodeGen)). `.xcodeproj` depoda tutulmaz.

## Geliştirme

Gereken: Xcode 16+, iOS 17+ cihaz.

```bash
brew install xcodegen
xcodegen generate
open PhotoSweep.xcodeproj
```

Gerçek iPhone'da çalıştırmak için Xcode'da Signing & Capabilities altından kendi geliştirici ekibinizi seçin.

Çekirdek testleri:

```bash
swift test --package-path Packages/SweepCore
```

Analiz sonuçları önbelleğe yazılır (Application Support); ikinci tarama yalnızca yeni ya da düzenlenmiş fotoğrafları analiz eder. Tarama durdurulursa sonraki tarama kaldığı yerden devam eder.

CI her gönderimde çekirdek testlerini (Linux) çalıştırır ve uygulamayı iOS simülatörü için derler (macOS).
