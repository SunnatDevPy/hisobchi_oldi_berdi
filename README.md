# 🤖 Hisobchi AI — Do'kon Oldi-Berdi, Nakladnoy & Prixod (`ITOG 👑`) Telegram Boti

[![Python](https://img.shields.io/badge/Python-3.12%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Aiogram](https://img.shields.io/badge/Aiogram-3.x-2CA5E0?logo=telegram&logoColor=white)](https://docs.aiogram.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Gemini AI](https://img.shields.io/badge/Gemini-Multimodal%20AI-8E75B2?logo=googlegemini&logoColor=white)](https://ai.google.dev/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/)

Do'kon va savdo nuqtalarida **kunlik naqd pul oldi-berdisi**, **AI yordamida nakladnoylarni o'qish (rasm + ovoz)**, **YesPOS'dan olinadigan kunlik prixod (`ITOG 👑`) hisobotlari**, hamda **kun yakunidagi kassa sverkasini** avtomatlashtiruvchi Telegram bot tizimi (`@hisobchi_my_bot`).

---

## ✨ Asosiy Imkoniyatlar

### 1. 💵 Kunlik Oldi-Berdi va AI Nakladnoy Hamyoni (`Gemini AI`)
- **Oson pul kiritish (`➕ Pul oldim`):** Matn, tugma yoki **🎤 ovozli xabar** orqali (`"Pul oldim 21 000 000"`, `"30 mln oldim"`).
- **Kassadan qarz nazorati (`🏦 Kassa qarzi`):** `"Kassadan 3 million oldim"` — ham qo'ldagi naqd pulga qo'shiladi, ham alohida **Kassaga qarz** sifatida yuritiladi; `"Kassaga 3 million qaytardim"` bilan yopiladi.
- **📸 AI Nakladnoy OCR (Rasm / Ovoz / Matn):**
  - Nakladnoy rasmini yuborsangiz, **Gemini Vision** ta'minotchi nomi va summani avtomatik ajratadi (tiniq bo'lsa qayta so'ramaydi; noaniq bo'lsa ovoz/matn orqali to'ldiradi).
  - **Dublikat tekshiruvi:** Bir kunda bir xil ta'minotchiga ayni summa kiritilganda ogohlantiradi.
  - **`✅ Tasdiqlash` bosilganda:** ro'yxatga qo'shadi, asosiy puldan ayiradi va **nakladnoy rasmini belgilangan Telegram guruhga avtomatik yuboradi**.
- **✏️ Tasdiqlangan yozuvlarni tahrirlash + Guruh sinxronizatsiyasi:**
  - Tasdiqlangan nakladnoy summasi/nomini o'zgartirish yoki o'chirish mumkin — balans avtomatik qayta hisoblanadi **va Nakladnoy guruhiga yuborilgan rasm izohi ham avtomatik `✏️ [TAHRIRLANDI]` / `❌ [O'CHIRILDI]` qilib yangilanadi**.
- **📊 Jonli Status va 🏁 Kun Yakuni (Sverka & History):**
  - Istalgan vaqtda kimga qancha berilgani, jami kirim, rasxod va qo'lda qolishi kerak bo'lgan aniq summani ko'rish.
  - Kun oxirida qo'ldagi pulni sanab kiritish $\rightarrow$ **Farqni** ko'rish $\rightarrow$ xato topilsa tuzatib qayta kiritish $\rightarrow$ **History (Arxiv)** ga saqlash.
  - **Ertangi kunga avtomatik o'tish:** Sanab qolgan pul ertangi kun boshlang'ich balansi bo'ladi, nakladnoylar ro'yxati esa `0` dan boshlanadi.

---

### 2. 👑 Kunlik Prixod (`ITOG`) Generatori
YesPOS'dan yuklangan **"Документы о приемке товара"** (`.csv` / `.xlsx`) faylini yoki qo'lda yozilgan matnni botga tashlaganda 1 soniyada tayyor **`ITOG 👑`** hisobotini yaratadi:

```text
ITOG 👑18.11.26
===============================
Qarz
1) OMBOR 12 895 000 + 2 109 750
2) QASSOB  18 985 900
3) FOZIL MARINAD (шашлик) 
4) ASADBEK (норин) 1 307 350
5) Alisa Pereches: 11 560 732
===============================
Nakladnoy 23 262 120
karta: 525 000
16.11: 409 400
===============================
Umumiy 71 055 252
```

- `Примечание` ustunidagi eski sanalarni (`16.11.2026`) va `karta` to'lovlarini avtomatik ajratadi.
- YesPOS'dagi uzun ta'minotchi nomlarini qisqa nomlarga bog'lash (masalan: `SAID AND PARTNERS GRUP ( масло)` $\rightarrow$ `Alisa Pereches`).
- Interaktiv tugmalar orqali istalgan qatorni `💳 Karta`, `📅 Eski sana` yoki `📌 Qarz` ga o'tkazish va **Prixod guruhiga** yuborish (hamda keyinroq tahrirlab xabarni yangilash).

---

### 3. 🔗 Guruhlar, Ta'minotchilar va Excel Eksport
- **3 ta alohida guruh roli:**
  - `/set_nakladnoy_group` — Nakladnoy rasmlari boradigan guruh
  - `/set_prixod_group` — Kunlik `ITOG 👑` prixod hisoboti boradigan guruh
  - `/set_kassa_group` — Kun yakunidagi sverka hisoboti boradigan guruh
- **📥 Excel (`.xlsx`) Eksport:** Kunlik hisobotlar, tarix va prixod qatorlarini tayyor jadval shaklida yuklab olish.

---

## 🏗 Loyiha Tuzilmasi

```text
hisobchi_oldi_berdi/
├── main.py                      # Bot kirish nuqtasi (Aiogram 3 Dispatcher & polling)
├── config.py                    # Pydantic Settings (.env konfiguratsiyasi)
├── requirements.txt             # Python kutubxonalari
├── Dockerfile                   # Production konteyner obrazi
├── docker-compose.yml           # Bot + PostgreSQL 16 izolyatsiyalangan stack
├── REJA.md                      # 1- va 2-bosqich texnik rejasi (YesPOS API yo'l xaritasi)
├── database/
│   ├── models.py                # SQLAlchemy 2.0 ORM modellari
│   ├── session.py               # Async engine, init_db va standart ta'minotchilar
│   └── crud.py                  # Hamyon, nakladnoy, tahrirlash, prixod va guruh CRUD
├── services/
│   ├── gemini_ai.py             # Gemini Vision/Audio AI & o'zbekcha summa parseri
│   ├── prixod_parser.py         # YesPOS CSV/XLSX va matn -> ITOG 👑 formatlagich
│   ├── excel_export.py          # OpenPyXL .xlsx hisobot generatori
│   └── yespos_client.py         # 2-bosqich: YesPOS Marketplace & 1C API mijozi
├── bot/
│   ├── states.py                # Aiogram FSM holatlari
│   ├── keyboards.py             # Reply va Inline tugmalar
│   └── handlers/
│       ├── settings_groups.py   # /start, guruhlarni ulash, ta'minotchilar, arxiv, eksport
│       ├── wallet_nakladnoy.py  # Pul oldim, kassa qarzi, AI nakladnoy, status, sverka
│       └── prixod_itog.py       # YesPOS fayl/matn -> ITOG 👑 & guruhga yuborish
└── tests/
    └── test_all.py              # Avtomatik Pytest testlari
```

---

## 🚀 Ishga Tushirish

### 1-usul: Docker Compose + PostgreSQL 16 (Tavsiya etiladi)

1. Loyihani yuklab oling va `.env` faylini tayyorlang:
   ```bash
   git clone https://github.com/SunnatDevPy/hisobchi_oldi_berdi.git
   cd hisobchi_oldi_berdi
   cp .env.example .env
   ```
2. `.env` faylida `BOT_TOKEN`, `GEMINI_API_KEY`, `POSTGRES_PASSWORD` va `DATABASE_URL` qiymatlarini to'ldiring:
   ```env
   BOT_TOKEN=123456:ABC-DEF...
   POSTGRES_USER=hisobchi
   POSTGRES_PASSWORD=kuchli_parol
   POSTGRES_DB=hisobchi_db
   DATABASE_URL=postgresql+asyncpg://hisobchi:kuchli_parol@hisobchi-postgres:5432/hisobchi_db
   GEMINI_API_KEY=...
   GEMINI_MODEL=gemini-flash-latest
   TIMEZONE=Asia/Tashkent
   ```
3. Konteynerlarni ishga tushiring:
   ```bash
   docker compose up -d --build
   docker compose logs -f hisobchi-bot
   ```

### 2-usul: Lokal Python muhiti (Test / Ishlab chiqish uchun)

```bash
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
python main.py
```

---

## ⚙️ Muhit O'zgaruvchilari (`.env`)

| O'zgaruvchi | Tavsif | Standart / Namuna |
|---|---|---|
| `BOT_TOKEN` | `@BotFather` dan olingan Telegram bot tokeni | Majburiy |
| `ADMIN_IDS` | Ruxsat berilgan Telegram ID lar (vergul bilan); bo'sh bo'lsa barcha shaxsiy chatlar ochiq | `""` |
| `DATABASE_URL` | PostgreSQL (`asyncpg`) yoki SQLite (`aiosqlite`) ulanish manzili | `sqlite+aiosqlite:///./data/hisobot_bot.db` |
| `GEMINI_API_KEY` | Google AI Studio / Gemini API kaliti (rasm va ovoz o'qish uchun) | Majburiy |
| `GEMINI_MODEL` | Asosiy Gemini modeli (`gemini-3.8-flash` / `gemini-flash-lite-latest` zaxira bilan) | `gemini-flash-latest` |
| `YESPOS_BASE_URL` | 2-bosqich YesPOS Marketplace API manzili | `https://marketplace.yestask.uz` |
| `YESPOS_API_KEY` | YesPOS API kaliti | Ixtiyoriy (2-bosqich) |
| `TIMEZONE` | Mahalliy vaqt mintaqasi | `Asia/Tashkent` |

---

## 🧪 Avtomatik Testlar

```bash
python -m pytest tests/test_all.py -v
```

Testlar haqiqiy 29 qatorli YesPOS CSV (`Документы о приемке товара`) parsingini, o'zbekcha summa/ovoz parserini, hamyon oldi-berdi balansini, tasdiqlangan nakladnoylarni tahrirlashni, kun yopish sverkasini va ertangi kunga qoldiq o'tishini tekshiradi.

---

## 🗺 2-Bosqich Yo'l Xaritasi (YesPOS API Integratsiyasi)

YesPOS **1C API (`X-API-Key`)** ruxsati olingandan so'ng `services/yespos_client.py` orqali qo'shiladigan avtomatik hisobotlar (batafsil: [REJA.md](REJA.md)):
- Kassa smenasi yopilganda **Umumiy savdo**, **Sotilgan mol tannarxi**, **Sof foyda va Marja (%)**.
- **Ombordagi bor mol tannarxi** (`stock × cost`) va kunlik prixod sinxronizatsiyasi.
