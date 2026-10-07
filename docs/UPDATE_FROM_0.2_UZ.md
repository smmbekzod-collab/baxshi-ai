# Baxshi AI v0.3 — yangilash, tekshirish va APK olish

## 1. Eski ma’lumotlarni saqlang

Railway PostgreSQL bazasi va media volume zaxirasini oling. Mavjud `DATABASE_URL`, `JWT_SECRET`, `ENCRYPTION_KEY` kabi maxfiy qiymatlarni o‘zgartirmang: ayniqsa shifrlash kalitini almashtirish OTP ma’lumotini o‘qib bo‘lmas holga keltiradi. Eski adminni qayta yaratish shart emas.

## 2. GitHub kodini yangilang

ZIPni oching; README, backend, mobile, docs, design, compose.yaml va `.github` joylashgan katalog ichidagilarni repozitoriy ildiziga nusxalang. Butun katalogni yana `baxshi-v0.3/` ichiga joylashtirmang. GitHub Desktop orqali mavjud repo nusxasiga almashtirib, diffni ko‘rib Commit va Push qilish qulay. `.github/workflows` ham yuklangan bo‘lsin. `.env`, build, local.properties, keystore va shaxsiy maxfiy fayllarni yuklamang.

## 3. Railway backendni yangilang

Mavjud servisning Root Directory qiymati `backend` bo‘lsin. Dockerfile shu katalogda. Start Command: `python -m app.serve` (yoki Dockerfile CMD ishlashi uchun bo‘sh). Bu launcher Railway bergan `PORT`ni o‘qiydi.

Bitta API servisi uchun Variables:

```text
EMBEDDED_WORKER=true
SEED_DEMO_CONTENT=true
MEDIA_ROOT=/data/media
```

PostgreSQL `DATABASE_URL` va avvalgi maxfiy kalitlar saqlanadi. `/data`ga persistent volume ulang; container diskining o‘zi doimiy emas. Media papkasi Docker foydalanuvchisi UID 10001 uchun yoziladigan bo‘lsin. Redeploy qiling. Startup yangi jadvallarni qo‘shadi, mavjud admin bo‘lsa namunaviy darslarni va texnik etalonlarni bir marta joylaydi. Har restart eski progressni o‘chirmaydi.

Agar birinchi admin hali yo‘q bo‘lsa, server terminalida:

```bash
python -m app.cli init-db
python -m app.cli create-admin
python -m app.cli seed-demo
```

Mavjud admin bor bo‘lsa faqat oxirgi buyruq yetadi; parol yoki OTPni chatga yubormang.

Docker Compose konfiguratsiyasida `EMBEDDED_WORKER=false` belgilangan va `api` hamda alohida `worker` xizmatlari umumiy media volume bilan ishlaydi. Railway bitta servisida esa `true` qoladi.

## 4. Tahlil tayyorligini tekshiring

Brauzerda `https://baxshi-ai-production.up.railway.app/healthz`ni oching (boshqa domen bo‘lsa o‘shaniki):

```json
{"status":"ok","version":"0.3.1","analysis":{"worker_online":true,"ffmpeg_available":true}}
```

Javobda qo‘shimcha maydonlar ham bor. Ishga tushgandan keyin bir necha soniya bering. Faqat `status: ok` yetarli emas: `worker_online` va `ffmpeg_available` ham `true` bo‘lishi kerak. `false` bo‘lsa server logi, worker flagi, volume va DB ulanishini tekshiring. Model bahosi chiqmayotgani bilan worker ishlamayotganini aralashtirmang: etalonsiz ijroda o‘lchovlar bor, an’anaviy mahorat ballari yo‘q.

## 5. APKlarni oling

GitHub → Settings → Secrets and variables → Actions → Variables:
`API_BASE_URL = https://baxshi-ai-production.up.railway.app`.

Actions → **Test and build APKs** → oxirgi yashil run → Artifacts:
- `baxshi-user-debug`: talaba ilovasi;
- `baxshi-admin-debug`: administrator ilovasi.

Arxivlarni ochib APKni telefonga o‘rnating. Bu sinov buildi. Eski APK boshqa debug kaliti bilan imzolangan bo‘lsa Android update’ni rad qiladi; eski ilovani o‘chirish mahalliy yozuvlarni ham o‘chiradi, avval kerakli ma’lumotni saqlang. Keyingi doimiy yangilanishlar uchun o‘zingizning release signing key’ingizdan foydalaning.

## 6. Telefon orqali qabul sinovi

1. O‘z hisobingiz bilan kiring; Bosh sahifada tahlil xizmati tayyorligini ko‘ring.
2. Profil → rasm tanlash: JPG/PNG/WebP, 3 MBgacha. Qayta kirib avatar va ism saqlanganini tekshiring.
3. Kurslar → dars → savollarga javob → natija. Tugagan dars bosh sahifa progressida ko‘rinsin. Offline rejimda matn ochiladi, testni serverga topshirish internet talab qiladi.
4. 5–20 soniya tiniq ovoz yozing, rozilikni belgilang, etalonsiz yuboring. Hisobotdan davomiylik va chastota kabi o‘lchovlarni tekshiring.
5. Texnik etalonni tanlab yuklang: texnik taqqoslash va ogohlantirish chiqsin. Haqiqiy doston uchun admin litsenziyalangan etalon yuklashi kerak.
6. Mikrofon ruxsatini rad etish, juda jim yozuv va internet uzilishini sinang: tushunarli xabar chiqishi kerak. Ishlamagan vazifada qayta urinish tugmasi bor.
7. Xabarlar → administrator → xabar. Admin ilovasidagi Xabarlar orqali javob bering. Ustoz ko‘rinishi uchun admin guruh yaratib teacher va talabani biriktirsin. Ustoz oddiy foydalanuvchi ilovasidan kirib yozishadi.

Xabarlar ekran ochiq va ilova foreground bo‘lganda 5 soniyada yangilanadi; push notification va ovozli xabar bu relizda yo‘q.

## Muhim chegaralar

Ushbu paket jonli Railway serveringizga avtomatik o‘rnatilmagan. Haqiqiy telefon, sizning server loginlaringiz va ishlab turgan bazada sinov bajarilmadi. Avtomatik testlar natijasi VALIDATION.md’da. 6 dars pedagogik namuna; 4 etalon bir xil sun’iy signalga asoslangan va haqiqiy maktab/ustoz ijrosi emas. Breath/resonance/style uchun ilmiy tekshirilgan model bo‘lmagani sabab foiz uydirilmaydi.


## Ixtiyoriy Grok/Gemini/ChatGPT kaliti

Backendni v0.3.1 yangilangach, admin ilovasining **AI provayderlari** bo‘limiga kiring. Grok (xAI), Gemini, OpenAI/ChatGPT yoki Lokalni tanlab, provayderingizdagi model ID va API kalitni yozing. `ENCRYPTION_KEY`ni avvalgi qiymatda saqlang: server kalitni shu kalit bilan shifrlaydi. Yangi versiyada DB jadvali o‘zgarmaydi, yangi sozlama mavjud `objects` jadvalida saqlanadi. Admin o‘chirilsa avval configni boshqa superadmin yordamida yangilang. “Ulanishni sinash” bir kichik API so‘rovini yuboradi.

Talaba AI Coach ekranida alohida tugmani bosganda, faqat maktab tanlovi, akustik metric va audio sifati raqamlari yuboriladi. Audio, ism, profil va account ID yuborilmaydi. AI javobi tavsiya; tizim avvalgi worker/audio tahlilga API chaqirmaydi. Kalit yo‘q yoki provider xato bersa lokal tavsiya qaytadi. Kalitni hech qachon GitHub variable, oddiy app config, APK, chat yoki logga joylamang.
