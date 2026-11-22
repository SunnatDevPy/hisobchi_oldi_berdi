# 📱 Hisobchi Mobil Ilovasi (Flutter APK) — To'liq Qo'llanma

Ushbu qo'llanma **Hisobchi** mobil ilovasining ichki tuzilishi, qaysi fayl nimaga javob berishi, kompyuterda **APK yig'ish (build qilish)** va uni serverga (`hisobchi.okaposai.uz`) joylash bo'yicha qadam-baqadam yo'riqnomadir.

---

## 1. Umumiy Arxitektura (Ilova va Bot qanday ishlaydi?)

Ilova va Telegram bot (`@hisobchi_my_bot`) **bitta PostgreSQL ma'lumotlar bazasida (`hisobchi_db`)** va **bitta konteyner (`hisobchi-bot`)** ichida ishlaydi:

```text
[Android Telefon: Hisobchi.apk]
       │
       │ HTTPS (https://hisobchi.okaposai.uz)
       ▼
[Server Nginx (443 SSL)] ──► [hisobchi-bot konteyneri: FastAPI :8088]
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
             [PostgreSQL]   [Gemini Vision]  [Telegram Guruh]
             (hisobchi_db)   (AI Skaner)     (Nakladnoy #89/1)
```

- **Xavfsizlik:** `BOT_TOKEN` va `GEMINI_API_KEY` hech qachon APK ichida saqlanmaydi — barcha AI va Telegram guruhga yuborish amallari serverning o'zida bajariladi.

---

## 2. Qaysi fayl nimaga javob beradi?

### A) Mobil ilova fayllari (`mobile/` papkasi)

| Fayl manzili | Vazifasi (Nimaga javob beradi?) |
| :--- | :--- |
| **`mobile/lib/main.dart`** | **Asosiy ekranlar va mantiq:**<br>• `LoginScreen` — 8 xonali `/apk` kodi bilan kirish ekrani<br>• `MainWorkspaceScreen` — 4 ta pastki menyu (`Dashboard`, `Qarzlar`, `Hisobot`, `Smena`)<br>• `AddNakladnoySheet` — Yangi nakladnoy qo'shish oynasi (rasm tanlanishi bilan avtomatik AI tahlil qiladi)<br>• `NakladnoyDetailSheet` — Nakladnoyni tahrirlash (`±10 000`, `±1 000`, `Yaxlitlash`, postavshik almashtirish, to'lov turini o'zgartirish)<br>• `sheetBottomPadding()` — Tugmalar telefonning pastki 3 ta navigatsiya tugmasi orqasiga o'tib ketmasligini ta'minlaydi |
| **`mobile/lib/widgets.dart`** | **Dizayn komponentlari (Reusable UI):**<br>• `HeroBalanceCard` — Yuqoridagi katta Indigo-Violet balans kartasi (`Qo'lda qolishi kerak`, kirim/chiqim progress chizig'i, 3 ta Bento KPI kartochkasi va `Tezkor AI Skaner` paneli)<br>• `PaymentModeSelector` — 4 xil to'lov usuli tugmalari (`Naqd`, `Karta`, `O'tkazma`, `Qarzga`)<br>• `NakladnoyListCard` — Ro'yxatdagi har bir nakladnoy kartochkasi (`#89 / 1`, vaqti, guruh holati, summasi) |
| **`mobile/lib/theme.dart`** | **Ranglar, shriftlar va UZS formatlash:**<br>• `AppTokens` — Asosiy brend ranglar (`brand`, `cashGreen`, `cardBlue`, `transferPurple`, `debtAmber`, `dangerRed`) va gradientlar<br>• `formatUzs()` — `1554000` sonini `1 554 000 so'm` ko'rinishiga keltiradi<br>• `parseUzsInput()` — Qo'lda yozilgan summani songa aylantiradi<br>• `buildAppTheme()` — Yorug' (`Light`) va Tungi (`Dark`) Material 3 mavzulari |
| **`mobile/lib/api_client.dart`** | **Server bilan aloqa (HTTP Mijoz):**<br>• `HisobchiApiClient` — `https://hisobchi.okaposai.uz` ga barcha so'rovlarni yuboradi (`/auth/login`, `/status`, `/cash`, `/ai/extract`, `/nakladnoy`, `/debts`, `/day/close`, `/export/...`)<br>• `defaultBaseUrl` — Standart server domeni shu yerda yozilgan<br>• Tokenni telefon xotirasida (`SharedPreferences`) saqlaydi |
| **`mobile/pubspec.yaml`** | **Kutubxonalar va ilova versiyasi:**<br>• `version: 1.0.0+1` — Ilova versiyasi<br>• Ishlatilgan paketlar: `http`, `shared_preferences`, `image_picker`, `share_plus`, `path_provider`, `intl` |
| **`mobile/android/app/src/main/AndroidManifest.xml`** | **Android ruxsatnomalar va Ilova nomi:**<br>• `android:label="Hisobchi"` — Telefonda ko'rinadigan ilova nomi<br>• `INTERNET` va `CAMERA` ruxsatnomalari |
| **`mobile/android/app/build.gradle.kts`** | **Android Gradle sozlamalari:**<br>• `applicationId = "uz.hisobchi.hisobchi_app"` — Ilovaning noyob paket nomi<br>• `minSdk`, `targetSdk`, Java 17 sozlamalari |

---

### B) Server (Backend & Telegram Bot) fayllari

| Fayl manzili | Vazifasi (Nimaga javob beradi?) |
| :--- | :--- |
| **`api/app.py`** | Mobil APK murojaat qiladigan barcha FastAPI endpointlari (`/health`, `/download/hisobchi.apk`, `/auth/login`, `/status`, `/ai/extract`, `/nakladnoy`, `/debts`, `/export/...`) |
| **`api/auth.py`** | `/apk` orqali beriladigan 8 xonali bir martalik kod (5 daqiqa amal qiladi) va SHA-256 bilan shifrlangan qurilma tokenlari (`api_tokens` jadvali) |
| **`api/deps.py`** | APK dan qo'shilgan yoki tahrirlangan nakladnoyni Telegramdagi Nakladnoy guruhiga yuborish va sinxron yangilash |
| **`bot/handlers/apk_link.py`** | Telegram botdagi `/apk` buyrug'i: kirish kodi olish, APK faylni Telegramning o'zidan yuklab olish, ulangan telefonlarni ko'rish va uzish (`❌ Uzish`) |
| **`main.py`** | Bot polling bilan bir vaqtda FastAPI serverini (`0.0.0.0:8088`) bitta jarayonda ishga tushiradi |

---

## 3. Kompyuterda o'rnatilgan dasturlar manzillari

Sizning kompyuteringizda quyidagi SDK'lar sozlangan:
- **Flutter SDK:** `C:\dev\flutter` *(Flutter 3.50.1 / Dart 3.14.0)*
- **Android SDK:** `C:\dev\android-sdk` *(Platform 34, 35, 36 + Build-Tools)*
- **Java (JDK 17):** `C:\Program Files\Microsoft\jdk-17.0.21.102-hotspot`

---

## 4. APK yig'ish (Build qilish) — Buyruqlar

### Variant 1: Eng oson yo'li (1 ta tayyor skript bilan)

Loyiha asosiy papkasida (`c:\Projects\Hisobot_bot_and_integratsiya_yespos`) PowerShell ochib:

```powershell
# Faqat APK yig'ish (dist\hisobchi.apk ga tushadi):
.\build_apk.ps1

# APK yig'ish VA darhol serverga (hisobchi.okaposai.uz) yuklash:
.\build_apk.ps1 -Deploy
```

---

### Variant 2: Qo'lda qadam-baqadam buyruqlar (O'rganish uchun)

PowerShell terminalini ochib, quyidagi buyruqlarni ketma-ket terasiz:

#### 1-qadam: Muhit o'zgaruvchilarini (`PATH` va `JAVA_HOME`) ulash
```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.21.102-hotspot"
$env:ANDROID_HOME = "C:\dev\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\dev\android-sdk"
$env:Path = "C:\dev\flutter\bin;$env:JAVA_HOME\bin;C:\dev\android-sdk\platform-tools;$env:Path"
```

#### 2-qadam: `mobile` papkasiga kirish va paketlarni tekshirish
```powershell
cd c:\Projects\Hisobot_bot_and_integratsiya_yespos\mobile
flutter pub get
```

#### 3-qadam: Kodda xato yo'qligini va testlarni tekshirish
```powershell
flutter analyze
flutter test
```
*(Agar `No issues found!` va `All tests passed!` chiqsa, kod 100% toza)*

#### 4-qadam: Release APK yig'ish
```powershell
flutter build apk --release --target-platform android-arm,android-arm64
```
> **Nega `--target-platform android-arm,android-arm64` yoziladi?**
> Oddiy `flutter build apk` kompyuter emulyatori (`x86_64`) kodini ham qo'shib yuboradi va APK ~51 MB bo'lib ketadi. `android-arm,android-arm64` esa barcha haqiqiy Android telefonlar uchun yig'adi va hajmini **~32.7 MB** qiladi (bu Telegram botning 50 MB fayl yuborish limitidan bemalol o'tadi).

Tayyor APK quyidagi manzilda paydo bo'ladi:
`mobile\build\app\outputs\flutter-apk\app-release.apk`

#### 5-qadam: `dist\hisobchi.apk` ga nusxalash va Serverga yuklash
```powershell
cd c:\Projects\Hisobot_bot_and_integratsiya_yespos
Copy-Item -Force mobile\build\app\outputs\flutter-apk\app-release.apk dist\hisobchi.apk

# Serverga yuklash (Telegram bot va hisobchi.okaposai.uz/download/hisobchi.apk darhol yangilanadi):
scp dist\hisobchi.apk ubuntu@46.8.194.206:/home/ubuntu/hisobchi_oldi_berdi/data/hisobchi.apk
```

---

## 5. Tez-tez kerak bo'ladigan o'zgartirishlar (Cheat Sheet)

1. **Ilova ranglarini o'zgartirish:**
   - `mobile/lib/theme.dart` faylidagi `AppTokens` klassidan (`brand`, `heroGradient`, `cashGreen`, va h.k.) o'zgartiriladi.
2. **Standart domen manzilini o'zgartirish:**
   - `mobile/lib/api_client.dart` ichidagi `static const String defaultBaseUrl = 'https://hisobchi.okaposai.uz';` qatori.
3. **Ilova versiyasini oshirish:**
   - `mobile/pubspec.yaml` faylidagi `version: 1.0.0+1` ni masalan `version: 1.1.0+2` qilasiz.
4. **Telefondagi ilova nomini o'zgartirish:**
   - `mobile/android/app/src/main/AndroidManifest.xml` ichidagi `android:label="Hisobchi"` qatori.
5. **USB orqali ulangan telefonda jonli sinab ko'rish (Hot Reload):**
   - Telefonni USB orqali ulab (`Отладка по USB` yoqilgan holatda), `cd mobile` ichida `flutter run` deb yozsangiz, kodni saqlashingiz (`r` tugmasi) bilan 1 soniyada telefonda o'zgaradi!
