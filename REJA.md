# 📋 Hisobot Bot & YesPOS Integratsiya — Loyiha Rejasi

Ushbu hujjat do'konning kunlik **naqd pul oldi-berdisi**, **AI yordamida nakladnoylarni o'qish va guruhga yuborish**, **kunlik prixod (`ITOG 👑`) hisoboti**, hamda kelajakdagi **YesPOS integratsiyasi** tizimining to'liq texnik va funksional rejasini o'z ichiga oladi.

---

## 🎯 Loyiha Maqsadi

Do'konda ta'minotchilar bilan har kuni bo'ladigan naqd pul oldi-berdisini, nakladnoy rasmlarini, kun yakunidagi kassa sverkasini va YesPOS'dan olinadigan kunlik prixod hisobotlarini **bitta Telegram bot** orqali avtomatlashtirish.
- Alohida veb-sayt ochish shart emas: barcha operatsiyalar (rasm tashlash, ovozli xabar yuborish, matn kiritish, tahrirlash, Excel yuklash va guruhlarga yuborish) bevosita Telegram bot ichida bajariladi.

---

## 🟢 1-BOSQICH: Asosiy Tizim (Hozir Ishga Tushiriladigan Qism)

### 1-Bo'lim: ⚙️ Guruhlar va Ta'minotchilarni Sozlash

Botning turli bo'limlari uchun alohida Telegram guruhlarini ulash va doimiy ta'minotchilar ro'yxatini boshqarish imkoniyati:

1. **Guruhlarni biriktirish:**
   Botni kerakli Telegram guruhiga qo'shib, guruh ichida quyidagi buyruqni yuborish kifoya (yoki bot menyusi orqali Chat ID kiritish):
   - `/set_nakladnoy_group` — **📸 Nakladnoy guruhi** (tasdiqlangan nakladnoy rasmlari va tahrirlangan izohlar avtomatik yuboriladi).
   - `/set_prixod_group` — **👑 Prixod (`ITOG`) guruhi** (kunlik `ITOG 👑` prixod hisoboti yuboriladi).
   - `/set_kassa_group` — **💰 Kassa / Rahbariyat guruhi** (kun yakunidagi oldi-berdi sverkasi va yakuniy hisobotlar yuboriladi).

2. **Doimiy Qarz ta'minotchilari (`Qarz` ro'yxati) va Sinonimlar:**
   - Standart ro'yxat (`OMBOR`, `QASSOB`, `FOZIL MARINAD (шашлик)`, `ASADBEK (норин)`, `Alisa Pereches`, `By Malika`).
   - Bot menyusidan yangi ta'minotchi qo'shish, nomini o'zgartirish, toifasini (`qarz` / `karta` / `nakladnoy`) belgilash va YesPOS'dagi nomini bog'lash (masalan: `SAID AND PARTNERS GRUP ( МАСЛО)` $\rightarrow$ `Alisa Pereches`).

---

### 2-Bo'lim: 💵 Kunlik Oldi-Berdi va AI Nakladnoy Hamyoni (`Gemini Flash`)

1. **Kun boshlanishi va Pul kiritish (`➕ Pul oldim`):**
   - Kechagi kun yopilganda sanab qolgan pul (masalan, `1 500 000`) bugungi kunning **boshlang'ich qoldig'i** sifatida avtomatik o'tadi. Nakladnoylar ro'yxati esa har kuni `0` dan boshlanadi.
   - **Matn, tugma yoki 🎤 Ovoz** orqali kiritish:
     - *"Pul oldim 21 000 000"* $\rightarrow$ Asosiy balansga qo'shiladi.
     - *"Kassadan oldim 3 000 000"* (`🏦 Kassa qarzi`) $\rightarrow$ Ham balansga qo'shiladi, ham **"Kassaga qarz"** sifatida alohida hisobga olinadi.
     - *"Kassaga 3 000 000 qaytardim"* $\rightarrow$ Kassadan qarz kamayadi.

2. **Nakladnoy rasm / ovoz / matn orqali to'lov (`📸 Nakladnoy qo'shish`):**
   - Nakladnoy rasmini botga yuborasiz. **Gemini Flash** rasmdagi ta'minotchi (postavshik) nomini va summani avtomatik o'qiydi.
   - Agar rasm tiniq bo'lib, ikkalasi ham o'qilsa, bot ovoz/matn so'rab o'tirmaydi — birdan tasdiqlash oynasini chiqaradi.
   - Agar rasmdagi yozuv tushunarsiz bo'lsa, bot ovoz yoki matn orqali aniqlashtirishni so'raydi.
   - **Dublikat tekshiruvi:** Bugun ayni shu ta'minotchiga ayni shu summa kiritilgan bo'lsa, bot ogohlantiradi.
   - **`✅ Tasdiqlash`** bosilganda:
     1. Nakladnoy to'lovi ro'yxatga qo'shiladi;
     2. Qo'ldagi umumiy puldan ayiriladi;
     3. Rasm **Nakladnoy guruhiga** chiroyli izoh bilan avtomatik tashlanadi va xabar ID'si bazaga saqlanadi.

3. **✏️ Tasdiqlangan yozuvlarni tahrirlash va o'chirish:**
   - Istalgan vaqtda tasdiqlangan nakladnoy summasini/nomini o'zgartirish yoki o'chirish, shuningdek kiritilgan naqd pullarni tahrirlash mumkin.
   - **Avto-sinxronizatsiya:** Tasdiqlangan nakladnoy o'zgartirilsa yoki o'chirilsa:
     - Balans avtomatik qayta hisoblanadi;
     - **Nakladnoy guruhiga yuborilgan rasm tagidagi matn ham avtomatik yangilanadi** (`✏️ TAHRIRLANDI` yoki `❌ BEKOR QILINDI`).

4. **📊 Jonli Status va 🏁 Kunni Yakunlash (Sverka & History):**
   - **`📊 Status`:** Istalgan payt kechadan qoldiq, bugungi kirimlar, kassadan olingan qarzlar, kimga qancha berilgani ro'yxati, umumiy rasxod va qo'lda qolishi kerak bo'lgan aniq summani ko'rsatadi.
   - **`🏁 Kunni yakunlash`:**
     1. Bot jami kirim, umumiy rasxod va qo'lda qolishi kerak bo'lgan summani ko'rsatadi;
     2. Siz qo'lingizdagi naqd pulni sanab kiritasiz (matn yoki ovozda);
     3. Bot **Farqni** (`✅ To'g'ri (0)`, `⚠️ Kamomad` yoki `➕ Ortiqcha`) hisoblaydi;
     4. Agar xato bo'lsa, **`✏️ Xatoni to'g'irlash`** orqali ro'yxatga qaytib to'g'irlashingiz va qayta kiritishingiz mumkin;
     5. Tasdiqlangach, hisobot **History (Arxiv)** ga saqlanadi, **Kassa guruhiga** yuboriladi va siz sanagan pul **ertangi kun boshlang'ich balansi** bo'lib o'tadi.
   - **📥 Excel Export:** Istalgan kunlik yoki arxiv tarixini `.xlsx` jadval ko'rinishida yuklab olish.

---

### 3-Bo'lim: 👑 Kunlik Prixod (`ITOG`) Generatori

YesPOS'dan yuklab olingan **"Документы о приемке товара"** (`.csv` yoki `.xlsx`) faylini yoki qo'lda yozilgan matnni botga tashlaganda:

1. Jadvaldagi `Выполненный` qatorlarni avtomatik o'qiydi va sanani (`DD.MM.YY`) aniqlaydi.
2. **Aqlli ajratish:**
   - Sozlamadagi **Qarz** ta'minotchilarini (`OMBOR`, `QASSOB`, `ASADBEK`, `Alisa Pereches` va b.) alohida raqamlab chiqaradi (bir kunda bir ta'minotchidan 2 ta nakladnoy bo'lsa, `12 895 000 + 2 109 750` ko'rinishida yozadi).
   - `Примечание` ustunida sana yozilgan bo'lsa (`16.11.2026`), uni alohida **`16.11: 409 400`** satriga ajratadi.
   - `Примечание` da `karta` yozilgan bo'lsa yoki karta toifasidagi ta'minotchi (`By Malika`) bo'lsa, **`karta: 525 000`** satriga ajratadi.
   - Qolgan barcha ta'minotchilar yig'indisini **`Nakladnoy`** satriga yig'adi.
3. **Interaktiv tahrirlash:** Tasdiqlashdan oldin tugmalar yordamida istalgan qatorni `💳 Karta`, `📅 Eski sana` yoki `📋 Nakladnoy` toifasiga o'tkazish mumkin.
4. **`✅ Prixod guruhiga yuborish`** bosilganda tayyor `ITOG 👑` hisoboti Prixod guruhiga yuboriladi va bazaga saqlanadi (keyinchalik tahrirlab guruhdagi xabarni ham yangilash mumkin).

---

## 🟡 2-BOSQICH: Kelajakdagi Reja (YesPOS API Integratsiyasi)

YesPOS jamoasidan **1C / Hisobot API (`X-API-Key`)** ruxsati olingandan so'ng ulanadigan modullar:

1. **Marketplace API (`https://marketplace.yestask.uz/api/v1`):**
   - `POST /marketplace/products` — barcha kategoriya va mahsulotlar katalogini sinxronlash (rate limit: `15 req/min`).
   - `POST /marketplace/products/info` — `Branch` kesimida joriy qoldiq (`stock`) va sotuv narxlarini (`price`) olish (rate limit: `10 req/min`).
2. **1C Integration API (`/api/v1/1c`):**
   - `GET /api/v1/1c/receipts1C` — kassa cheklari, kassirlar kesimida savdo, to'lov turlari (naqd/karta) va har bir sotilgan tovarning **tannarxi (`cost`)** hamda **sotuv narxi (`price`)**.
   - `GET /api/v1/1c/purchOrders1C` — kirim nakladnoylari va ta'minotchilardan kelgan tovarlarning kirim tannarxi.
3. **Kassa Smena Yopilgandagi Yakuniy Avto-Hisobot (Rahbariyat / Kassa guruhiga):**
   - Barcha kassalar smenasi yopilgach avtomatik hisoblanadi:
     - 💰 **Umumiy savdo** (naqd + terminal + o'tkazma);
     - 📉 **Umumiy savdo tannarxi**;
     - 📈 **Umumiy sof foyda va Marja (%)**;
     - 🏬 **Do'konda/omborda bor mol (tannarxida va sotuv narxida)**;
     - 📥 **Kunlik umumiy prixod**.

---

## 🛠 Texnik Arxitektura

- **Til va Framework:** Python 3.11+, Aiogram 3.x (Asinxron Telegram Bot)
- **Ma'lumotlar bazasi:** PostgreSQL (`asyncpg` + `SQLAlchemy 2.0 Async`) — lokal test uchun SQLite (`aiosqlite`) ham qo'llab-quvvatlanadi.
- **Sun'iy Intellekt (AI):** Google **Gemini Flash (`gemini-flash-latest` / `gemini-3.8-flash` / `gemini-flash-lite-latest` avtomatik zaxira bilan)** (`generateContent` multimodal REST API — rasm OCR va o'zbek tilidagi ovozli xabarlarni tushunish).
- **Fayl tahlili va eksport:** `csv`, `openpyxl` (`.xlsx` o'qish va tayyor hisobot eksport qilish).
