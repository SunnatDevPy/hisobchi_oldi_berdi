# 📱 Hisobchi Mobil Ilovasi (Flutter APK) — Tuzilish va Build Qo'llanmasi

Ushbu qo'llanma **Hisobchi** mobil ilovasining ichki tuzilishi, qaysi fayl nimaga javob berishi va kompyuterda **APK yig'ish (build qilish)** bo'yicha qadam-baqadam yo'riqnomadir.

---

## 1. Umumiy Arxitektura

Mobil ilova va Telegram bot yagona ma'lumotlar bazasida hamda FastAPI REST xizmati orqali real-vaqtda sinxron ishlaydi:

```text
[Android Telefon: Hisobchi.apk]
       │
       │ HTTPS REST API
       ▼
[FastAPI REST Xizmati]
       │
       ├──► [Ma'lumotlar Bazasi]
       ├──► [Gemini Vision AI (Nakladnoy OCR)]
       └──► [Telegram Guruh (Nakladnoy #89 / 1)]
```

- **Xavfsizlik:** `BOT_TOKEN` va `GEMINI_API_KEY` hech qachon APK ichida saqlanmaydi — barcha AI va Telegram guruhga yuborish amallari backend serverda bajariladi.

---

## 2. Qaysi fayl nimaga javob beradi?

### A) Mobil ilova fayllari (`mobile/` papkasi)

| Fayl manzili | Vazifasi (Nimaga javob beradi?) |
| :--- | :--- |
| **`mobile/lib/main.dart`** | **Asosiy ekranlar va mantiq:**<br>• `LoginScreen` — 8 xonali `/apk` kodi bilan kirish ekrani<br>• `MainWorkspaceScreen` — 4 ta pastki bo'lim (`Dashboard`, `Nakladnoylar`, `Qarzlar`, `Smena & Excel`)<br>• `AddNakladnoySheet` — Yangi nakladnoy qo'shish oynasi (rasm tanlanishi bilan avtomatik AI tahlil qiladi)<br>• `NakladnoyDetailSheet` — Nakladnoyni tahrirlash (`Yaxlitlash`, postavshik tanlash, to'lov turini o'zgartirish)<br>• `sheetBottomPadding()` — Tugmalar telefonning pastki navigatsiya tugmalari orqasiga o'tib ketmasligini ta'minlaydi |
| **`mobile/lib/widgets.dart`** | **Dizayn komponentlari (Reusable UI):**<br>• `HeroBalanceCard` — Yuqoridagi katta Indigo-Violet balans kartasi (`Qo'lda qolishi kerak`, kirim/chiqim ko'rsatkichlari va tezkor kassa amallari)<br>• `DashboardAnalyticsSection` — 2×2 to'lov turlari kesimi, Pul oldi-berdi va Kassa amallari tarixi, hamda Bugungi Top Postavshiklar reytingi<br>• `PaymentModeSelector` — 4 xil to'lov usuli tugmalari (`Naqd`, `Karta`, `O'tkazma`, `Qarzga`)<br>• `NakladnoyListCard` — Ro'yxatdagi har bir nakladnoy kartochkasi (`#89 / 1`, vaqti, guruh holati, summasi) |
| **`mobile/lib/theme.dart`** | **Ranglar, Light/Dark kontrast va UZS formatlash:**<br>• `AppTokens` — Asosiy brend ranglar va `semanticSurface()` yorug'/tungi kontrast funksiyasi<br>• `UzsAmountInputFormatter` — Summa kiritayotganda raqamlarni jonli tarzda probel bilan ajratib yozadi (`1 554 000`)<br>• `formatUzs()` va `parseUzsInput()` — Pul qiymatlarini formatlash va o'qish<br>• `buildAppTheme()` — Yorug' (`Light`) va Tungi (`Dark`) Material 3 mavzulari |
| **`mobile/lib/version.dart`** | **Ilova versiyasi:**<br>• `build_apk.ps1` tomonidan har gal avtomatik yangilanadigan versiya va build raqami (`kAppVersion`, `kAppBuildNumber`) |
| **`mobile/lib/api_client.dart`** | **Backend bilan aloqa (HTTP Mijoz):**<br>• `HisobchiApiClient` — Barcha REST so'rovlarni yuboradi (`/auth/login`, `/status`, `/cash`, `/ai/extract`, `/nakladnoy`, `/debts`, `/day/close`, `/export/...`, `/apk/version`)<br>• Tokenni telefon xotirasida (`SharedPreferences`) saqlaydi |
| **`mobile/pubspec.yaml`** | **Kutubxonalar va ilova versiyasi:**<br>• `version: X.Y.Z+B` — Ilova versiyasi (har buildda avtomatik `+1` ga oshadi)<br>• Ishlatilgan paketlar: `http`, `shared_preferences`, `image_picker`, `share_plus`, `path_provider`, `intl` |
| **`mobile/android/app/src/main/AndroidManifest.xml`** | **Android ruxsatnomalar va Ilova nomi:**<br>• `android:label="Hisobchi"` — Telefonda ko'rinadigan ilova nomi<br>• `INTERNET` va `CAMERA` ruxsatnomalari |

---

### B) Backend & Telegram Bot fayllari

| Fayl manzili | Vazifasi (Nimaga javob beradi?) |
| :--- | :--- |
| **`api/app.py`** | Mobil APK murojaat qiladigan barcha FastAPI endpointlari (`/health`, `/apk/version`, `/download/hisobchi.apk`, `/auth/login`, `/status`, `/ai/extract`, `/nakladnoy`, `/debts`, `/export/...`) |
| **`api/auth.py`** | `/apk` orqali beriladigan 8 xonali bir martalik kod (5 daqiqa amal qiladi) va SHA-256 bilan shifrlangan qurilma tokenlari |
| **`api/deps.py`** | Rasm EXIF normallashtirish hamda APK dan qo'shilgan nakladnoyni Telegram guruhga yuborish va sinxron yangilash |
| **`bot/handlers/apk_link.py`** | Telegram botdagi `/apk` buyrug'i: kirish kodi olish, APK faylni yuklab olish, ulangan telefonlarni ko'rish va uzish (`❌ Uzish`) |

---

## 3. APK yig'ish (Build qilish) — Buyruqlar

### Variant 1: 1 ta tayyor skript bilan (Avto-versiya bilan)

Loyiha asosiy papkasida PowerShell ochib:

```powershell
# Versiyani avtomatik +1 ga oshiradi va APK yig'adi (dist\hisobchi.apk):
.\build_apk.ps1
```

---

### Variant 2: Qo'lda qadam-baqadam buyruqlar

#### 1-qadam: `mobile` papkasiga kirish va paketlarni tekshirish
```powershell
cd mobile
flutter pub get
```

#### 2-qadam: Kodda xato yo'qligini va testlarni tekshirish
```powershell
flutter analyze
flutter test
```

#### 3-qadam: Release APK yig'ish
```powershell
flutter build apk --release --target-platform android-arm,android-arm64
```
Tayyor APK quyidagi manzilda paydo bo'ladi:
`mobile\build\app\outputs\flutter-apk\app-release.apk`
