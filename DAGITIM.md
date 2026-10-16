# Arkadaşlara dağıtım (TestFlight)

Uygulamayı arkadaşlarına göndermenin tek pratik yolu TestFlight. Onlar App Store'daki **TestFlight** uygulamasını kurar, senin gönderdiğin bağlantıya dokunur, uygulama yüklenir. Her yeni sürümde güncelleme kendiliğinden gelir.

Ücretsiz Apple hesabıyla yalnızca kendi telefonuna (7 günlük) kurabilirsin. Başkasına göndermek için **Apple Developer Program** üyeliği gerekiyor: yılda 99 $.

## Bir kerelik kurulum (~30 dk, Apple onayları hariç)

1. **Üyelik:** https://developer.apple.com/programs/enroll/ adresinden bireysel üye ol. Onay genellikle 1-2 gün sürüyor.
2. **Takım kimliği:** https://developer.apple.com/account adresinde "Membership details" altındaki **Team ID**'yi (10 karakter) not al.
3. **Uygulama kaydı:** https://appstoreconnect.apple.com adresinde Apps, sonra "+", sonra "New App":
   - Platform: iOS, Ad: Photo Sweep (alınmışsa "Photo Sweep TR" gibi), Dil: Türkçe
   - Bundle ID: `com.basakrdnz.photosweep`. Listede yoksa önce https://developer.apple.com/account/resources/identifiers adresinden bu kimlikle bir App ID oluştur.
   - SKU: `photosweep`
4. **API anahtarı:** App Store Connect'te Users and Access, sonra Integrations, sonra App Store Connect API, sonra "+":
   - Ad: GitHub, Erişim: **Admin** (imzalama sertifikasını otomatik oluşturabilmesi için gerekli)
   - `.p8` dosyasını indir (yalnızca bir kez indirilebilir). **Key ID** ve sayfanın üstündeki **Issuer ID**'yi not al.
5. **GitHub gizli değerleri:** depoda Settings, sonra Secrets and variables, sonra Actions, sonra "New repository secret":

   | Ad | Değer |
   |---|---|
   | `APPLE_TEAM_ID` | 2. adımdaki Team ID |
   | `ASC_KEY_ID` | Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8` | `.p8` dosyasının tüm içeriği (BEGIN/END satırları dahil) |

## Her sürümde

1. GitHub'da Actions, sonra **TestFlight**, sonra "Run workflow". Yaklaşık 10 dakikada derlenip yüklenir.
2. App Store Connect'te uygulama, sonra TestFlight sekmesi. Derleme 10-30 dakika içinde "Processing" durumundan çıkar.
3. **Kendin için:** "Internal Testing" grubuna kendini ekle; inceleme beklemeden hemen kurulur.
4. **Arkadaşlar için:** "External Testing", yeni grup, derlemeyi ekle:
   - İlk derleme Apple'ın kısa beta incelemesinden geçer (genellikle 1 gün). Test bilgisi olarak şunu yazabilirsin: "Fotoğraf arşivindeki kopya ve benzer fotoğrafları bulup silmeye yardım eder. Tüm analiz cihazda yapılır."
   - Onaydan sonra **Public Link**'i aç. Bu bağlantıyı arkadaşlarına gönder.
   - Sonraki derlemeler çoğunlukla incelemesiz geçer.

## Arkadaşlarına göndereceğin not

> App Store'dan TestFlight'ı kur, sonra bu bağlantıyı aç: <public link>. Uygulama tüm fotoğraflara erişim ister; analiz telefonda yapılır, hiçbir şey dışarı gitmez. Sildiklerin 30 gün "Son Silinenler"de durur.
