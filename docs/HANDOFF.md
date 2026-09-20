# MacB — devir notu

Son güncelleme: 2026-09-20. Bu dosya Codex'e (ya da başka bir ajana) devretmek için
yazıldı: bugün ne yapıldı, şu an ne bozuk, sırada ne var.

Branch: `main`, çalışma ağacı temiz. **53 commit push edilmemiş** (iCloud tahliyesi
yüzünden ertelendi — repo `~/Developer/MacB`'ye taşınabilir).

---

## 0. Önce bunları oku — değişmez kurallar

Bunlar tercih değil, kural. Koddaki yorumlar da bunları açıklıyor.

- **Mac parolası asla alınmaz, saklanmaz.** Kilit ekranına `CGEvent` ile tuş
  basılmaz. MacB macOS'u açmaz.
- **Hiçbir şey silinmez.** `FileManager.removeItem` yok; `NSWorkspace.recycle` var.
- **Kamera görüntüsü diske yazılmaz.** Yüz verisi AES-GCM, anahtar Keychain'de
  `userPresence` ile. Biyometrik veri ve kamera görüntüsü dışarı çıkmaz.
- **API anahtarı dosyaya, log'a, repoya yazılmaz.** Yalnız Keychain'de, sağlayıcı
  başına ayrı item. Anahtarı okuyan tek yer `AIKeyStore`.
- Parola yöneticilerinin geçici/gizli pano içeriği kaydedilmez.
- Üçüncü parti kod ve lisanslar `THIRD_PARTY_NOTICES.md`'de.
- **Tam ekran görüntüsü alınmaz.** Görsel doğrulama için kontrollü test penceresi,
  dar kırpma veya sayısal ölçüm (`--measure-*` probe'ları) kullanılır.
- GitHub'a push ve Keychain'e yazma **açık onay** ister.
- Otomatik test + gerçek Mac'te doğrulama olmadan iş bitmiş sayılmaz. Placeholder
  ekran yok.

### Prompt-injection kapısı

Dışarıdan gelen metin (web sayfası, ekran yazısı, seçim, takvim daveti, **mail konu
satırı**) veri'dir, talimat değil. `JarvisTool.readsOutsideContent` bunu işaretler;
işaretlendikten sonra dışarı etki eden her araç kullanıcı onayı ister
(`needsConfirmation(afterReadingOutsideContent:privateContent:)`).

---

## 1. Bugün yapılanlar

### `03124d5` — sağlayıcı seçimi, maliyet tavanı, brifing kartı
- `AIProvider.textOrder` sırası değişti: Gemini önce, Groq sonra. Sebebi: `automatic`
  anahtarı olan ilk sağlayıcıyı seçiyordu ve Groq'un ücretsiz modeli 8B idi — hızlı
  ama kötü. Kullanıcının "yapay zeka aşırı kötü" şikâyetinin sebebi buydu.
- Canlı ses varsayılanı `gpt-realtime-mini` (yaklaşık 1/3 fiyat). `AIPricing` mini'yi
  ayrı fiyatlıyor; önceden tam model fiyatından sayıp 3 katını yazıyordu.
- `JarvisSession`: sessizlik 90s → **30s**, sert limit 20dk → **6dk**,
  `max_output_tokens` eklendi. Realtime sessizliği de faturalandırır ve her turda
  tüm konuşmayı yeniden gönderir (maliyet karesel).
- `AIBudget` + `AICostMeter.dailyLimit` (varsayılan **$0.50**). Harcamadan **önce**
  kontrol edilir. Ücretsiz sağlayıcılar tavandan etkilenmez.
- `showInDock` varsayılanı `true` → MacB ⌘Tab'de çıkıyor (macOS Dock'suz ⌘Tab vermez).
- Brifing kartı yeniden yazıldı: cümle yığını yerine **chip satırı**
  (`Briefing.chips(for:)`). 154×460 → 100×380.
- Ayarlar'daki uzun paragraflar 2 satıra kırpıldı (`SettingsIntro`).

### `03daec6` — ücretsiz sesli motor
- İki motor: canlı (OpenAI realtime) ve **ücretsiz** (cihaz üstü STT →
  ücretsiz sağlayıcı → macOS TTS).
- `JarvisEngineChoice.resolve(...)` saf fonksiyon: anahtar + bütçe varsa canlı,
  yoksa ücretsiz. **Para yüzünden konuşma hiç başlamamazlık etmez.**
- İki motor aynı talimatı paylaşıyor (`JarvisProtocol.instructions`, `sessionUpdate`
  içinden çıkarıldı). Aynı onay kapısından geçiyorlar.
- `JarvisProtocol.plainSpoken` — sentezleyiciye Markdown okutulmuyor.
- Yeni dosyalar: `FreeVoiceEngine.swift`, `TurkishSpeaker.swift`,
  `JarvisEngineChoice.swift`.

### `88b7f86` — brifing sesi + mail
- Brifing artık **satır satır** okunuyor, aralarında 0.28s nefes. Tek string tek
  düz cümle gibi okunuyordu; "robot/Arapça gibi" şikâyetinin sebebi buydu.
- Türkçe ses seçici + "Daha iyi ses indir" (Sistem Ayarları › Erişilebilirlik ›
  Sözlü İçerik). Bu Mac'te: Yelda (basit), Cem (gelişmiş).
- `MailService` — Apple Mail'den AppleScript ile **yalnız** gönderen, konu, tarih,
  bayrak. Gövde asla. `MailParsing` saf ve test edilmiş.
- `MailImportance` — "önemli" = bayrakladığın + senin listelediğin gönderenler.
  Model karar vermiyor (bilerek).
- `read_mail` aracı; dış içerik **ve** özel içerik sayılır.

### `904b2bf` — arka plan ajanı
- `AgentJob` / `AgentPolicy` / `AgentJobStore` / `AgentJobRunner` / `IslandAgentView`.
- **Tek kural: iş okur ve önerir, asla yapmaz.** Etki eden araç çağrıldığında
  çalıştırılmaz; `AgentProposal` olarak kaydedilir, modele "queued" denir, kullanıcı
  dönünce karttan onaylanır.
- `AgentPolicy` her aracı **tam olarak bir** sınıfa koyar (runs / proposes /
  forbidden); test tüm enum'u dolaşıp bunu kanıtlıyor.
- Yasak: ekrana bakma, ekran yazısı, seçim, **uyutma**, başka iş başlatma.
- 8 tur, 5 dakika, tek seferde tek iş, ücretsiz motorda.
- Teslim: `NSWorkspace.sessionDidBecomeActiveNotification` / `didWake` →
  `deliverAgentReports()`.
- Gerçek sağlayıcı hataları bulundu ve düzeltildi:
  - `gemini-2.5-flash` yeni anahtarlara kapatılmış → varsayılan `gemini-3.6-flash`.
  - Groq'ta llama modeli kalmamış → varsayılan `openai/gpt-oss-120b`.
  - Gemini hata gövdesini **dizi** içinde yolluyor → `AIChatStream.errorMessage`.
  - Gemini 3 her function call'u imzalıyor, imzasız sonraki turu reddediyor →
    `AIChatStream.assistantMessage` ile modelin mesajı **aynen** geri yollanıyor.

Test: **163/163**. Build: temiz.

---

## 2. Şu an bozuk olanlar (öncelik sırasıyla)

### P1 — Hava durumu konumu görmüyor, OpenWeatherMap anahtarı boşta

**Teşhis.** `WeatherService.refresh()` ilk satırda şunu yapıyor
(`Sources/MacB/Services/WeatherService.swift:65`):

```swift
let place = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
guard !place.isEmpty else { errorMessage = nil; return }
```

`placeQuery` kullanıcının **elle yazdığı** şehir (`UserDefaults` → `weatherPlace`).
Boşsa hava durumu sessizce hiç denemiyor. CoreLocation hiç yok. OpenWeatherMap
anahtarı da yalnız Open-Meteo başarısız olunca devreye giren bir yedek
(`WeatherService.swift:89`) ve o da **aynı yazılı şehir adına** ihtiyaç duyuyor.
Yani anahtar pratikte hiç kullanılmıyor.

**Yapılacak.**
1. `Resources/MacB.entitlements`'a ekle:
   `com.apple.security.personal-information.location` → `true`.
2. `Resources/Info.plist`'e ekle: `NSLocationUsageDescription` (Türkçe, ne için
   kullanıldığını söyleyen bir cümle). macOS 14+ için
   `NSLocationWhenInUseUsageDescription` de ekle.
3. Yeni `Sources/MacB/Services/LocationService.swift`:
   - `CLLocationManager`, `desiredAccuracy = kCLLocationAccuracyKilometer`
     (hava durumu için şehir hassasiyeti yeter, daha fazlası gereksiz veri).
   - `requestWhenInUseAuthorization()` **sadece** kullanıcı Ayarlar'dan
     "Konumumu kullan"ı açınca çağrılsın — brifing kendi başına izin penceresi
     açmaz kuralı burada da geçerli.
   - `requestLocation()` (sürekli takip değil), sonucu cache'le, `CLGeocoder` ile
     ters çevirip şehir adını al.
   - Konum asla diske yazılmasın, asla modele gönderilmesin (yalnız Open-Meteo'ya
     giden lat/lon).
4. `WeatherService`: `placeQuery` boşsa ve konum izni varsa **lat/lon ile doğrudan**
   Open-Meteo'ya git — geocode turunu atla, bu aynı zamanda "hızlı baksın"ı çözer.
   Şehir adı yalnız görüntülemek için ters geocode'dan gelsin.
5. `Preferences.weatherUsesLocation: Bool` (varsayılan `false`) + Ayarlar'da
   toggle ve "şu an: Yalova" satırı.
6. OpenWeatherMap yedeği de lat/lon alacak şekilde güncellensin
   (`WeatherFallback.current(latitude:longitude:)`).
7. Test: `LocationService` mantığının saf kısmı (izin durumu → ne yapılacağı)
   MacBCore'a taşınsın ve `scripts/test-core.swift`'e senaryo eklensin.
8. Gerçek Mac doğrulaması: yeni bir probe — `--weather-probe` — konumdan hava
   durumunu alıp yazsın.

### P2 — Sürekli izin soruyor, izin kartı çirkin

**Teşhis.** `JarvisTool.readMail.needsConfirmation == true` → **her çağrıda** sorar.
Bir konuşmada üç kez maile bakarsa üç kez sorar. Ekran görüntüsündeki kart da dar:
`IslandAssistantView.confirmationCard` 3 satıra sığmaya çalışan bir metin + iki
düğme, island 300pt geniş.

**Yapılacak.**
1. **Oturum içi hatırlama.** `JarvisSession`'a
   `private var allowedThisSession: Set<JarvisTool>` ekle. `ask(...)` onaydan sonra
   aracı bu kümeye koysun; aynı araç aynı konuşmada bir daha sormasın.
   - Dikkat: bu **yalnız** `tool.needsConfirmation == true` olan okuma araçları için
     geçerli olmalı (`readMail`, `calendarEvents`). Yazan/eden araçlar
     (`addCalendarEvent`, `remember`, `powerAction`, `openWebsite`…) her seferinde
     sormaya devam etmeli — argümanları her seferinde farklı.
   - Konuşma bitince (`stop()`) küme sıfırlanmalı.
2. **Kalıcı izin (isteğe bağlı).** Ayarlar › Mail'e "Her seferinde sorma" toggle'ı.
   Varsayılan kapalı. Açıksa `readMail` onay istemesin — ama dış içerik okuduktan
   sonraki taint kuralı yine işlesin.
3. **Kartı yeniden tasarla.** `IslandAssistantView.confirmationCard`:
   - Genişlik: onay varken island `IslandGeometry.assistantWidth` 300 → 380 olsun
     (`assistantHeight(hasConfirmation:)` zaten 44pt ayırıyor, yetmiyor).
   - Düzen: üstte simge + tek satır başlık ("Maillerine bakayım mı?"), altta küçük
     gri açıklama ("kimden, konu, saat — içerik okunmaz"), en altta sağa yaslı
     `Hayır` / `İzin ver` (`IslandCapsuleButtonStyle`).
   - `--measure-assistant` probe'u onaylı hâli de ölçüyor; sığdığını orada kanıtla.
4. Onay metinleri `MacBJarvisToolbox.confirmationText(for:call:)`'da; başlık/açıklama
   ayrımı için `(title, detail)` döndüren bir şekle geçmek gerekebilir.

### P3 — "adam akıllı bakmıyor"

**Teşhis (doğrulanmadı, ilk bakılacak yer burası).** Muhtemel üç sebep:
1. `MailService.script` **unified inbox** kullanıyor (`messages of inbox whose read
   status is false`). Hesap yapısına göre boş dönebilir; hesap hesap dolaşmak
   (`every account` → `mailbox "INBOX"`) daha güvenilir.
2. Otomasyon izni verilmemişse `-1743` döner ve `isUnavailable` olur; island'da bu
   yalnız kısa bir mesaj olarak görünür.
3. Tarih ayrıştırma: `MailParsing.date` üç-dört formatı deniyor, tutmazsa `Date()`
   döndürüyor → sıralama bozulur, "en yeni" yanlış olur.

**Yapılacak.**
- Önce teşhis: yeni bir probe — `--mail-probe` — ham AppleScript çıktısının satır
  sayısını, ilk satırın alan sayısını ve ayrıştırılan başlık sayısını yazsın.
  **Konu satırlarını yazdırma** (gizlilik) — yalnız sayılar ve tarih ayrıştı mı.
- Sonuca göre script'i hesap bazlı dolaşacak şekilde değiştir.
- `MailParsing.date` başarısız olursa bunu belli et (`dateIsGuessed: Bool`), sessizce
  `Date()` döndürme.

---

## 3. Yapılacaklar listesi

### Hemen (yukarıdaki üç sorun)
- [ ] P1 — konumdan hava durumu + OpenWeatherMap'i lat/lon'a bağla
- [ ] P2 — oturum içi izin hatırlama + onay kartı yeniden tasarım
- [ ] P3 — mail okuma teşhisi ve düzeltme

### Sonraki tur
- [ ] Arka plan işi için "saat tut" seçeneği — şu an "20 dakikaya gelirim" denince
      süre sayılmıyor, kullanıcı dönünce teslim ediliyor. Süre de istenirse
      `AgentJob.deliverAt` alanı zaten duruyor, kullanılmıyor.
- [ ] Ajan raporu için Ayarlar bölümü: geçmiş işler, iptal, "hepsini temizle"
      (`AgentJobStore.clearDelivered` var, UI yok).
- [ ] `IslandAgentView` birden fazla bekleyen işi gösteremiyor (yalnız `waiting.first`).
- [ ] Island'ın diğer bölümleri (dosya, pano, zamanlayıcı) tasarım turundan geçmedi.
- [ ] OpenWeatherMap anahtarı P1 bittikten sonra da işe yaramıyorsa silinsin.
- [ ] Groq için "Modelleri yenile" akışı test edilmedi (model adları sık değişiyor).
- [ ] 53 commit push edilecek (onay gerekir).

### Ertelenmiş
- [ ] Face ID / yüz tanıma işi (InsightFace ağırlıkları **bundle edilmeyecek**,
      deneysel kalacak, Touch ID yedek).
- [ ] Beş repodan alınacak fikirler: Rectangle (kenara sürükleyip yapıştırma,
      üçte bir döngüsü), AltTab (island içinde önizlemeli pencere değiştirici),
      Ice (menü çubuğu öğelerini çentiğin arkasına gizleme), IINA (island'da
      scrubber/jest), Keka (rafta zip/çıkar).

---

## 4. Nasıl çalıştırılır

```bash
bash scripts/build.sh release     # ~/Applications/MacB.app'e kurar ve imzalar
bash scripts/test.sh              # 163/163 saf çekirdek senaryosu
pkill -x MacB; open ~/Applications/MacB.app
```

`swift build` bu makinede güvenilmez (SwiftUIMacros eklentisi / ClangStatCache
hataları). **Her zaman `scripts/build.sh` kullan.**

### Probe'lar (uygulama bağlamında çalışır, TCC izinleri uygulamaya ait)

```bash
open -g -n -W --stdout /tmp/out.txt --stderr /tmp/err.txt \
  ~/Applications/MacB.app --args --measure-briefing
```

Mevcut bayraklar: `--verify-keys`, `--list-models <provider>`,
`--chat-probe <provider> <model>`, `--ask <soru>`, `--ocr-probe`,
`--youtube-probe <q>`, `--measure-assistant`, `--measure-briefing`,
`--measure-agent`, `--job-probe "<görev>"`, `--import-keys <path>`.

`--chat-probe` bir sağlayıcının neden 404 verdiğini gövdesiyle gösterir; bugünkü
Gemini/Groq model sorunları böyle bulundu. **Anahtarı asla yazdırmaz.**

---

## 5. Mimari kısa özet

- `MacBCore` — saf, test edilebilir, AppKit yok. Protokoller, politika, geometri,
  ayrıştırma. Test edilecek her mantık buraya.
- `MacB` — AppKit/SwiftUI, servisler, island, ayarlar.
- Test koşucusu `scripts/test-core.swift` yalnız `MacBCore`'u görür. Bir mantığı
  test etmek istiyorsan MacBCore'a taşı (bugün `MailService.parse` →
  `MailParsing.headers` böyle taşındı).
- Tasarım jetonları `MacBDesign` (`Space`, `TypeScale`, `Motion`, `Radius`,
  `IslandToken`). Yeni sabit sayı yazma, jeton kullan.
- Island yüksekliği `IslandGeometry`'den gelir ve `--measure-*` probe'ları
  görünümün ayrılan yüksekliğe sığdığını sayısal olarak kanıtlar.

## 6. Kullanıcı hakkında

- Türkçe konuşulur; kod, tanımlayıcı, commit mesajı İngilizce.
- Tasarım konusunda mükemmeliyetçi. "Bok gibi" = yeniden tasarla, yamama.
- Bitmedi demeden önce test + gerçek Mac doğrulaması ister.
