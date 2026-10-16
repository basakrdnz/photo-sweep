# Plan

## Sürüm 0.1 — iskelet (bu sürüm)

- [x] SweepCore: dHash, netlik, feature vektör uzaklığı, gruplama (kopya + zaman pencereli benzer), en iyi fotoğraf önerisi, birim testleri
- [x] Uygulama: izin, tüm fotoğrafları önizlemeyle tarama (4 paralel), Vision feature print + yüz kalitesi + estetik puanı (iOS 18), grup listesi, grup ayrıntısı, seçip silme
- [x] CI: Linux'ta çekirdek testleri, macOS'ta iOS derlemesi
- [ ] Gerçek iPhone'da ilk deneme (sen): süre ve bulunan grupların doğruluğu not edilir

## Dağıtım

- [x] Uygulama ikonu, gizlilik manifesti, şifreleme beyanı
- [x] TestFlight iş akışı (Actions > TestFlight)
- [ ] Developer Program üyeliği ve gizli değerler (sen, bkz. DAGITIM.md)

## Sürüm 0.2 — doğruluk

- [ ] Etiketli test seti: kendi arşivinden ~200 çift, "kopya / benzer / farklı" olarak işaretlenmiş. Feature print ve dHash değerleri dışa aktarılıp eşikler bu sete göre ayarlanır
- [ ] Kesin kopya doğrulaması: dHash farkı 0 olan adaylar için dosya içeriğinin SHA-256'sı (yalnızca telefonda duran dosyalar)
- [x] Uzun benzer zincirlerini bölmek (gün batımı yürüyüşü gibi 40 karelik gruplar): kümenin en az yarısına benzerlik şartı

## Sürüm 0.3 — hız ve süreklilik

- [x] Analiz önbelleği (ikili plist): kimlik + değişiklik tarihi; ikinci tarama yalnızca yeni ya da değişen fotoğrafları işler
- [ ] Kütüphane değişikliklerini dinleme (PHPhotoLibraryChangeObserver)
- [x] Durdur düğmesi: o ana kadarki sonuçları gösterir, sonraki tarama kaldığı yerden sürer
- [ ] Şarjdayken arka planda tarama (BGProcessingTask)
- [ ] Ölçüm: 20 bin fotoğrafta ilk ve ikinci tarama süresi

## Sürüm 0.4 — ek temizlik

- [x] Ekran görüntüleri, bulanık fotoğraflar (eşik ayarlanacak), büyük videolar (100 MB üstü)
- [ ] Belge fotoğrafları
- [x] Toplam kazanılacak alanı gösterme
- [ ] Albümdeki fotoğrafları koruma seçeneği
