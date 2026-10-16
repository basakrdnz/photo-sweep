# Plan

## Sürüm 0.1 — iskelet (bu sürüm)

- [x] SweepCore: dHash, netlik, feature vektör uzaklığı, gruplama (kopya + zaman pencereli benzer), en iyi fotoğraf önerisi, birim testleri
- [x] Uygulama: izin, tüm fotoğrafları önizlemeyle tarama (4 paralel), Vision feature print + yüz kalitesi + estetik puanı (iOS 18), grup listesi, grup ayrıntısı, seçip silme
- [x] CI: Linux'ta çekirdek testleri, macOS'ta iOS derlemesi
- [ ] Gerçek iPhone'da ilk deneme (sen): süre ve bulunan grupların doğruluğu not edilir

## Sürüm 0.2 — doğruluk

- [ ] Etiketli test seti: kendi arşivinden ~200 çift, "kopya / benzer / farklı" olarak işaretlenmiş. Feature print ve dHash değerleri dışa aktarılıp eşikler bu sete göre ayarlanır
- [ ] Kesin kopya doğrulaması: dHash farkı 0 olan adaylar için dosya içeriğinin SHA-256'sı (yalnızca telefonda duran dosyalar)
- [ ] Uzun benzer zincirlerini bölmek (gün batımı yürüyüşü gibi 40 karelik gruplar): grup içi ortalama uzaklık sınırı

## Sürüm 0.3 — hız ve süreklilik

- [ ] Analiz önbelleği (SwiftData): kimlik + değişiklik tarihi; ikinci tarama yalnızca yeni ya da değişen fotoğrafları işler
- [ ] Kütüphane değişikliklerini dinleme (PHPhotoLibraryChangeObserver)
- [ ] Tarama sırasında kısmi sonuçları gösterme, iptal düğmesi
- [ ] Şarjdayken arka planda tarama (BGProcessingTask)
- [ ] Ölçüm: 20 bin fotoğrafta ilk ve ikinci tarama süresi

## Sürüm 0.4 — ek temizlik

- [ ] Ekran görüntüleri, bulanık fotoğraflar, büyük videolar, belge fotoğrafları
- [ ] Toplam kazanılacak alanı gösterme
- [ ] Albümdeki fotoğrafları koruma seçeneği
