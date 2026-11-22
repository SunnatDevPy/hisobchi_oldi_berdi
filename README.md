# 🏦 Hisobchi AI — Do'kon Kassa Oldi-Berdi, AI Nakladnoy, Prixod (`ITOG 👑`) Telegram Boti va Mobil Ilovasi (APK)

[![Python](https://img.shields.io/badge/Python-3.12%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Aiogram](https://img.shields.io/badge/Aiogram-3.x-2CA5E0?logo=telegram&logoColor=white)](https://docs.aiogram.dev/)
[![FastAPI](https://img.shields.io/badge/FastAPI-REST%20API-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Flutter](https://img.shields.io/badge/Flutter-Android%20APK-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Gemini AI](https://img.shields.io/badge/Gemini-Vision%20AI-8E75B2?logo=googlegemini&logoColor=white)](https://ai.google.dev/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/)

Do'kon va savdo nuqtalarida **kunlik naqd pul oldi-berdisi**, **4 xil to'lov turi (`Naqd`, `Karta`, `Perechesleniya`, `Qarzga`)**, **Gemini AI yordamida nakladnoylarni rasmdan avtomatik o'qish**, **YesPOS kunlik prixod (`ITOG 👑`) hisobotlari**, **kun yakunidagi kassa sverkasi** hamda **Telegram guruh bilan real-vaqtda sinxron ishlovchi Android mobil ilovasi (`Hisobchi.apk`)** dan iborat yagona ekotizim.

- 🤖 **Telegram Bot:** `@hisobchi_my_bot`
- 🌐 **Mobil API & APK Yuklash Markazi:** `https://hisobchi.okaposai.uz`
- 📥 **To'g'ridan-to'g'ri APK ko'chirish:** `https://hisobchi.okaposai.uz/download/hisobchi.apk` *(yoki bot ichida `/apk` buyrug'i orqali)*

---

## 🏛 Tizim Arxitekturasi (Bot + Mobil APK + Yagona Baza)

Telegram bot va Android mobil ilova **bitta PostgreSQL 16 bazasida (`hisobchi_db`)** ishlaydi. Botdan kiritilgan ma'lumot shu zahoti mobil ilovada ko'rinadi, mobil ilovadan kiritilgan nakladnoy esa shu zahoti **Telegramdagi Nakladnoy guruhiga** (`📸 Nakladnoy #89 / 1`) yuboriladi.

```mermaid
flowchart LR
    subgraph Clients["📲 Foydalanuvchi Qurilmalari"]
        TG["🤖 Telegram Bot\n(@hisobchi_my_bot)"]
        APK["📱 Hisobchi Android APK\n(Flutter Material 3)"]
    end

    subgraph Server["🖥 Production Server (Docker Compose)"]
        NGX["🔒 Nginx SSL Proxy\n(hisobchi.okaposai.uz)"]
        BOT["⚙️ hisobchi-bot konteyneri\nAiogram 3 + FastAPI (:8088)"]
        PG[("🐘 PostgreSQL 16\n(hisobchi_db)")]
    end

    subgraph External["☁️ Tashqi Xizmatlar"]
        AI["✨ Google Gemini Vision AI\n(Nakladnoy OCR)"]
        GRP["👥 Telegram Guruhlar\n(Nakladnoy / Prixod / Kassa)"]
    end

    TG <-->|"Long Polling (IPv4)"| BOT
    APK <-->|"HTTPS REST API"| NGX
    NGX <-->|"http://hisobchi-bot:8088"| BOT
    BOT <--> PG
    BOT <-->|"Rasm tahlili"| AI
    BOT <-->|"Avto-post va sinxron tahrir"| GRP
```

---

## ✨ Asosiy Imkoniyatlar

### 1. 📱 Hisobchi Mobil Ilovasi (Flutter Android APK)
Telegram bot bilan 100% sinxron ishlovchi zamonaviy Fintech dizaynli (`Light` va `Dark` rejimli) Android ilova:
- **🔑 Xavfsiz 1-martalik kod bilan ulanish (`/apk`):**
  - Ilova ichida hech qanday maxfiy token (`BOT_TOKEN`, `GEMINI_API_KEY`) saqlanmaydi.
  - Botga `/apk` yuborilganda **5 daqiqalik 8 xonali kod** beriladi va SHA-256 bilan himoyalangan qurilma tokeni yaratiladi. Botning o'zidan ulangan telefonlarni ko'rish va bir tugma bilan uzish (`❌ Uzish`) mumkin.
- **📊 Haqiqiy Analitik Dashboard (1-bo'lim):**
  - **Hero Balance Card:** `Qo'lda qolishi kerak (Naqd)`, `Qo'ldagi jami kirim`, `Naqd nakladnoy rasxod`, `Kechadan qoldiq`, `Bugun olingan pul`, `Kassa qarz qoldig'i` hamda 1-bosishda kassa amallari (`Pul oldim`, `Kassa qarz`, `Qaytarish`).
  - **To'lov turlari kesimi (2×2 Bento KPI):** `💵 Naqd`, `💳 Karta`, `🏦 Perechesleniya`, `📌 Qarzga` bo'yicha soni, summasi va ulush (`%`) chizig'i.
  - **Pul oldi-berdi va Kassa amallari tarixi:** Qachon (`soat:daqiqa`), qanday amal (`Asosiy pul olindi`, `Kassadan qarz`, `Kassaga qaytarildi`), izohi va summasi bilan to'liq ro'yxat + tahrirlash/o'chirish.
  - **Bugungi Top Postavshiklar:** Eng ko'p to'lov qilingan ta'minotchilar reytingi va grafik chizig'i.
- **📸 Rasm yuklanishi bilan 1-bosishda AI Avto-To'ldirish (`/ai/extract`):**
  - `+` tugmasini bosib `Kamera (AI)` yoki `Galereya (AI)` dan nakladnoy rasmi tanlanishi bilan, qo'shimcha tugma bosmasdan **Gemini Vision AI** 1.5–2 soniyada postavshik nomini (bazadagi aliaslar bilan solishtirib) va summani (yaxlitlangan holda `1 554 000`) avtomatik to'ldiradi.
- **🧾 Nakladnoylar Ro'yxati (2-bo'lim) & Qarzlar (3-bo'lim):**
  - To'lov turi bo'yicha **Dropdown filter**, **Saralash dropdown** (`Yangilari tepada`, `Summasi katta`, `Postavshik A-Z`) va qidiruv.
  - Barcha summa maydonlarida yozayotgan paytda avtomatik probel bilan ajratish (`1 554 000`).
  - To'lanmagan qarzlarni postavshik bo'yicha saralash va 1-bosishda `💵 Naqd`, `💳 Karta` yoki `🏦 Perechesleniya` orqali yopish.
- **🏁 Smena & Excel Hisobotlar (4-bo'lim):**
  - Qo'lda sanalgan haqiqiy pulni kiritish bilan jonli farqni (`✅ Farq: 0 so'm`, `➕ Ortiqcha`, `⚠️ Kamomad`) ko'rish va kunni yakunlash.
  - **Hisobot turi Dropdown** orqali `Bugungi kunlik hisobot`, `Oxirgi 7 kun`, `Joriy oy`, `Ixtiyoriy sana oralig'i` yoki `Postavshiklar Sverkasi`ni `.xlsx` formatida yuklab olish va ulashish.

---

### 2. 💵 4 Xil To'lov Turi va Kunlik Tartib Raqami (`#89 / 1`)
Har bir nakladnoy 4 xil holatdan birida tasdiqlanadi va istalgan vaqtda biridan ikkinchisiga o'zgartirilishi mumkin:
1. **💵 Naqd (standart):** Qo'ldagi naqd puldan (`Qo'lda qolishi kerak`) ayriladi.
2. **💳 Karta (naqdsiz):** Qo'ldagi naqd puldan **ayrilmaydi**, lekin kunlik Status, `/stats`, `/sverka` va Excel hisobotning alohida varag'ida (`Karta va Perechesleniya`) yuritiladi.
3. **🏦 Perechesleniya (O'tkazma):** Qo'ldagi naqd puldan **ayrilmaydi**, statistikada va Excel hisobotda alohida hisoblanadi.
4. **📌 Qarzga (Pul berilmadi):** To'lanmagan qarzlar ro'yxatiga tushadi; keyinchalik to'langanda (`Naqd` / `Karta` / `O'tkazma`) avtomatik bugungi ochiq smenaga o'tadi va guruhdagi xabar `✅ [QARZ TO'LANDI]` qilib yangilanadi.

**Kunlik tartib raqami (`#UmumiyID / KunlikTartib`):**
- Guruhga yuborilgan har bir nakladnoy `📸 Nakladnoy #89 / 1`, `📸 Nakladnoy #90 / 2` ko'rinishida chiqadi. Kun yopilib yangi smena ochilganda kasr keyingi kunlik tartib raqami yana `/ 1` dan boshlanadi.

---

### 3. 🤖 Telegram Botdagi Qulayliklar (`@hisobchi_my_bot`)
- **🏢 Barcha postavshiklar inline ro'yxati:** Nakladnoy qo'shishda yoki postavshikni o'zgartirishda bazadagi barcha ma'lum postavshiklar 2 ustunli sahifalangan (`⬅️ Oldingi` / `Keyingi ➡️`) inline tugmalar bo'lib chiqadi.
- **💰 Summani 1 qadamda tahrirlash:** `💰 Summa` tugmasini bosganda ham `-10 000`, `-1 000`, `+1 000`, `+10 000`, `🔄 Yaxlitlash` tugmalari chiqadi, ham **qo'shimcha tugma bosmasdan pastdan to'g'ridan-to'g'ri yangi summani yozib yoki ovozda aytib** o'zgartirish mumkin.
- **⚡ Yuqori tezlik optimizatsiyasi:**
  - `DatabaseFSMStorage` write-through RAM keshi (har bir tugma bosilganda DB ga ortiqcha so'rov yubormaydi).
  - Guruh xabarlarini fonda birlashtirib yangilash (`_schedule_group_sync`) — ketma-ket `+10 000` bosilganda tugmalar kutmasdan lahzada ishlaydi.
  - Rasm (`Pillow`) va Excel (`OpenPyXL`) amallari `asyncio.to_thread()` orqali alohida oqimda bajariladi.

---

### 4. 👑 Kunlik Prixod (`ITOG`) Generatori va 📒 Nasiya Daftari
- YesPOS'dan yuklangan **"Документы о приемке товара"** (`.csv` / `.xlsx`) faylini yoki matnni 1 soniyada tayyor **`ITOG 👑`** hisobotiga aylantiradi va Prixod guruhiga yuboradi.
- `/nasiya`, `/sverka`, `/stats`, `/audit`, `/roles`, `/backup` va `/apk` buyruqlari orqali to'liq boshqaruv.

---

## 🏗 Loyiha Tuzilmasi

```text
hisobchi_oldi_berdi/
├── main.py                         # Kirish nuqtasi: Aiogram 3 Bot + FastAPI (Uvicorn :8088)
├── config.py                       # Pydantic Settings (.env konfiguratsiyasi)
├── requirements.txt                # Python kutubxonalari (aiogram, fastapi, uvicorn, sqlalchemy...)
├── Dockerfile                      # Production konteyner obrazi
├── docker-compose.yml              # hisobchi-bot + hisobchi-postgres (PostgreSQL 16)
├── build_apk.ps1                   # 1 ta buyruq bilan APK yig'ish va serverga deploy qilish skripti
├── api/                            # Mobil APK uchun FastAPI REST API
│   ├── app.py                      # /health, /auth/login, /status, /ai/extract, /nakladnoy, /export...
│   ├── auth.py                     # 8 xonali /apk bir martalik kod va SHA-256 Bearer tokenlar
│   ├── deps.py                     # Rasm EXIF normallashtirish va Telegram guruhga avto-post/sinxron
│   └── schemas.py                  # Pydantic so'rov va javob modellari
├── bot/
│   ├── auth.py                     # RBAC huquqlar tizimi (admin, kassir, viewer)
│   ├── storage.py                  # Write-through RAM keshli DatabaseFSMStorage
│   ├── states.py                   # Aiogram FSM holatlari
│   ├── keyboards.py                # Reply va Inline klaviaturalar
│   └── handlers/
│       ├── navigation.py           # Ustuvor navigatsiya va /cancel
│       ├── apk_link.py             # /apk buyrug'i: kod olish, APK faylni yuklash, qurilmalarni uzish
│       ├── wallet_nakladnoy.py     # Pul oldim, kassa qarzi, AI nakladnoy, 4 to'lov turi, sverka
│       ├── settings_groups.py      # Guruhlarni ulash, postavshiklar, history, Excel eksport
│       ├── prixod_itog.py          # YesPOS CSV/XLSX -> ITOG 👑 generatori
│       ├── nasiya.py               # Postavshiklar nasiya daftari
│       └── admin_tools.py          # /stats, /sverka, /audit, /roles, /backup
├── database/
│   ├── models.py                   # SQLAlchemy 2.0 ORM modellari (DailyCashSession, NakladnoyPayment, ApiToken...)
│   ├── session.py                  # Async engine (pool_pre_ping) va idempotent sxema migratsiyasi
│   └── crud.py                     # Barcha biznes mantiq va balans hisob-kitoblari
├── services/
│   ├── gemini_ai.py                # Gemini Vision/Audio OCR va o'zbekcha summa parseri
│   ├── excel_export.py             # Ko'p varaqli OpenPyXL (.xlsx) hisobotlar va diagrammalar
│   ├── prixod_parser.py            # YesPOS jadval parseri
│   ├── backup.py                   # Kunlik shifrlangan zaxira nusxa (Backup)
│   └── scheduler.py                # Avto-hisobot va AI limit ogohlantirgichi
├── mobile/                         # Flutter Android Mobil Ilovasi
│   ├── README.md                   # APK arxitekturasi va build qilish bo'yicha batafsil qo'llanma
│   ├── pubspec.yaml                # Flutter paketlari va ilova versiyasi
│   └── lib/
│       ├── main.dart               # Login, 4 ta bo'lim (Dashboard, Nakladnoylar, Qarzlar, Smena & Excel)
│       ├── widgets.dart            # HeroBalanceCard, DashboardAnalyticsSection, NakladnoyListCard
│       ├── theme.dart              # AppTokens, Light/Dark kontrast tizimi, UzsAmountInputFormatter
│       └── api_client.dart         # HisobchiApiClient (https://hisobchi.okaposai.uz)
└── tests/
    └── test_all.py                 # 27 ta keng qamrovli avtomatik Pytest testlari
```

---

## 📱 Mobil APK Yig'ish (Build) va Yangilash

Batafsil qo'llanma: [mobile/README.md](mobile/README.md)

Windows PowerShell orqali **1 ta buyruq bilan** APK yig'ish (`dist\hisobchi.apk`) va serverga (`https://hisobchi.okaposai.uz/download/hisobchi.apk` hamda Telegram bot `/apk` bo'limiga) yuklash:

```powershell
# Faqat APK yig'ish (dist\hisobchi.apk):
.\build_apk.ps1

# APK yig'ish va darhol serverga yuklash:
.\build_apk.ps1 -Deploy
```

Qo'lda yig'ish buyruqlari:
```powershell
cd mobile
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

---

## 🚀 Serverda Ishga Tushirish (Docker Compose)

1. `.env` faylini tayyorlang (`cp .env.example .env`):
   ```env
   BOT_TOKEN=123456:ABC-DEF...
   ADMIN_IDS=123456789
   POSTGRES_USER=hisobchi
   POSTGRES_PASSWORD=kuchli_parol
   POSTGRES_DB=hisobchi_db
   DATABASE_URL=postgresql+asyncpg://hisobchi:kuchli_parol@hisobchi-postgres:5432/hisobchi_db
   GEMINI_API_KEY=AIzaSy...
   GEMINI_MODEL=gemini-flash-lite-latest
   TIMEZONE=Asia/Tashkent
   API_ENABLED=true
   API_HOST=0.0.0.0
   API_PORT=8088
   API_PUBLIC_URL=https://hisobchi.okaposai.uz
   ```
2. Konteynerlarni ishga tushiring:
   ```bash
   docker compose up -d --build
   docker logs -f hisobchi-bot
   ```

---

## 🧪 Avtomatik Testlar

```bash
python -m pytest tests/test_all.py -v
```
Barcha **27 ta test** (`tests/test_all.py`) — YesPOS CSV/matn parsing, 4 xil to'lov turi (`cash` / `card` / `transfer` / `debt`), kunlik `#ID / seq` raqamlash, tez summa va postavshik tahrirlash, RAM FSM kesh, Excel eksport hamda Mobile REST API (`/auth/login`, `/ai/extract`, `/nakladnoy`, `/status`) ishlashini to'liq tekshiradi.
