# Baxshi AI — Android + Super Admin + FastAPI

**0.2.0 · GitHub uchun tayyor monorepo · pilot release.**

Bu arxiv kod, testlar, Android loyihasi va build workflowlarini o‘z ichiga oladi.
U jonli server yoki tayyor, ilmiy tasdiqlangan baxshichilik modeli degani emas.
`docs/VALIDATION.md` tekshiruv natijalarini, `docs/RELEASE_GATES.md` ommaviy ishga tushirishdan oldingi ishlarni ko‘rsatadi.

## 1. GitHub’dan ikkita APK olish

1. Arxivni oching. **Shu README turgan katalog ichidagi barcha fayllarni**, jumladan `.github`, repozitoriy ildiziga yuklang. Git bilan yuklash yashirin fayllar tushib qolmasligini ta’minlaydi:
   ```bash
   git init
   git add .
   git commit -m "Baxshi AI mobile, admin and backend"
   git branch -M main
   git remote add origin https://github.com/YOUR_ACCOUNT/baxshi-ai.git
   git push -u origin main
   ```
2. GitHub → Settings → Secrets and variables → Actions → **Variables**:
   `API_BASE_URL = https://SIZNING_API_DOMENINGIZ`.
   URL bo‘lmasa test APK `https://api.example.invalid` bilan yig‘iladi; login ishlamaydi.
3. Actions → **Test and build APKs** → muvaffaqiyatli run → Artifacts:
   - `baxshi-user-debug`: foydalanuvchi ilovasi (`uz.baxshiai.app`).
   - `baxshi-admin-debug`: alohida Super Admin ilovasi (`uz.baxshiai.admin`).

Debug APK sinash uchun. Do‘kon yoki ommaviy tarqatish uchun quyidagi imzolangan build kerak.
Admin APK faylini egallash admin huquqini bermaydi: server rolni va OTP’ni tekshiradi.

## 2. Backendni ishga tushirish

Talablar: Docker Engine + Compose, HTTPS domen, zaxiralash uchun disk.

```bash
python3 tool/setup_env.py
# .env yaratiladi. Uni GitHub, chat yoki ochiq logga yubormang.
docker compose build
docker compose up -d db
docker compose run --rm api python -m app.cli init-db
docker compose run --rm api python -m app.cli create-admin
docker compose up -d api worker
```

`create-admin` login va kamida 12 belgili parol so‘raydi. Oxirida chiqadigan
`otpauth://...` URI’ni autentifikatorga qo‘shing, maxfiy saqlang. OTP kod
30 soniyalik davrda faqat bir marta qabul qilinadi. Yangi admin yaratish faqat
server terminali orqali amalga oshiriladi.

API faqat `127.0.0.1:8000` portida ochiladi. Hostdagi Caddy/Nginx orqali TLS ulang.
`deploy/Caddyfile` namunasi bor: domenni almashtiring. `/healthz` tayyorlik endpointi.
Proxy ortida ushbu konfiguratsiya mijoz IP’sini ishonchli ajratmaydi; login rate
limiti proxy uchun umumiy bo‘lishi mumkin. Internet pilotidan oldin edge rate limit
va ishonchli proxy sozlamasini moslang. Bir xil media volume API va workerga kerak.

Ilova HTTPS talab qiladi. Oddiy `http://IP:8000` ni ilovaga bermang.
PostgreSQL porti internetga chiqarilmaydi. `init-db` faqat boshlang‘ich sxema uchun;
keyingi sxema o‘zgarishlarida versiyalangan migratsiya qo‘shish kerak.

## 3. Birinchi ish oqimi

1. Super Admin ilovasida login + parol + OTP bilan kiring.
2. **Foydalanuvchilar** → `+`: o‘quvchi hisobini yarating. Zarur bo‘lsa rolini `teacher` qiling.
3. **Etalon yozuvlar** → `+`: litsenziyasi bor WAV/M4A yuklang, maktab, ijrochi,
   litsenziya sharti va tugash vaqtini kiriting. `active` bilan oching.
   `license_until`/`due` hozir Unix sekund qiymatlaridir; admin formalari pilot uchun sodda.
4. Foydalanuvchi ilovasida hisob bilan kiring. 5–1200 soniyali ovoz yozing,
   maktab va mos etalonni tanlang, rozilikni belgilang va yuboring.
5. Navbat holati yangilanadi. Tugagach **Tahlilni yangilash** → Tahlil yoki AI Coach.
6. Admin tahlilni ko‘radi, ekspert bahosi qo‘shadi; muvaffaqiyatsiz vazifani qayta boshlaydi.

Etalonsiz audio sifat tekshiruvi va hisobot ishlaydi, pitch/rhythm sonli bahosi
chiqmaydi. Soxta raqam o‘rniga sabab ko‘rsatiladi.

## 4. Nimalar amalga oshirilgan

| Qism | Holati |
|---|---|
| Ovoz | WAV 48 kHz mono / AAC 128 kbps, jonli amplituda chizig‘i, pause/resume, 20 min limit, ilova foniga o‘tganda pauza |
| Yuklash | 1 MiB bo‘laklar, SHA-256, server offset orqali davom ettirish, idempotent complete/job yaratish |
| Mahalliy saqlash | Shifrlangan Hive metama’lumot/hisobot, secure storage token, account bo‘yicha audio papkalari, checksum kesh |
| Tinglash | Offline mahalliy fayl, seek, tezlik 0.5–1.5x, takrorlash; yozish boshlansa pleyerlar to‘xtaydi |
| Tahlil | Beshta metric modeli, null/reason, fl_chart grafiki, model/reference metadata, cached report |
| Akustik worker | FFmpeg 16 kHz konversiya, davomiylik/sukunat/clipping filtri, F0 kontur DTW va onset-interval taxminlari |
| AI Coach | Hisobotdan matn/mashq; mavjud tizim ovozi bilan ixtiyoriy TTS. Hozir qoidaviy tavsiya, LLM emas |
| Tarix | Mahalliy yozuvlar, server vazifalari, tanlangan tugagan hisobotni ochish, mashq kundaligi |
| Maxfiylik | Ixtiyoriy research consent, eksport, hisob o‘chirish so‘rovi, worker cleanup |
| Super Admin | Hisob/rol/faollik, sessiyalarni bekor qilish, etalon/litsenziya, material, vazifa, hisobot/ekspert bahosi, guruh/topshiriq, audit, siyosat, rozilikka asoslangan CSV |
| UI | Material 3 light/dark, moslashuvchan dashboard, navigatsiya, loading/retry/empty holatlari |
| Tillar | Asosiy 56 kalitli uz/kaa/en katalog. Yangi boshqaruv/tarix/auth ekranlari hozir o‘zbekcha; kaa matni native review talab qiladi |
| Build | Ikkita Android flavor, dependency lockfile, test/debug va alohida signed-release Actions |

Grafik **spektrogramma emas**, vaqtga taxminan bog‘langan normallashtirilgan moslik grafigi.
Amplitude visualizer raw PCM waveform emas. `confidence` API maydoni baseline’da
ovozli kadrlar ulushi; kalibrlangan ehtimollik emas. Audio kesh/app files OS sandboxida,
ammo audio baytlari alohida ilova kaliti bilan shifrlanmagan.

## 5. Ilmiy cheklov

`acoustic-baseline-0.2-unvalidated` badiiy mahorat baholovchisi emas. Pitch:
registrga moslashtirilgan kontur; rhythm: onset intervallari taqsimoti.
Breath, resonance va style hozir `null` + tushuntirish. Haqiqiy to‘rt maktab
klassifikatori uchun litsenziyalangan dataset, ustozlar annotatsiyasi, ijrochi bo‘yicha
ajratilgan holdout va kalibrlash kerak. Model uchun sun’iy “95% aniqlik” da’vosi yo‘q.
`DEMO_MODE=true` faqat ko‘rgazma; uning raqamlari UI’da DEMO deb belgilangan.

## 6. Lokal Flutter build

Flutter **3.47.4**, JDK 17 (javac bilan), Android SDK kerak.

```bash
cd mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug --flavor user -t lib/main.dart \
  --dart-define=API_BASE_URL=https://YOUR_API_DOMAIN
flutter build apk --debug --flavor admin -t lib/main_admin.dart \
  --dart-define=API_BASE_URL=https://YOUR_API_DOMAIN
```

APK’lar: `mobile/build/app/outputs/flutter-apk/`.
Android native loyiha arxivda mavjud, `flutter create` qayta bajarish kerak emas.

## 7. Imzolangan release

O‘zingizning doimiy Android upload keystore’ingizni yarating va zaxiralang.
GitHub Environment **production** yarating; review himoyasi tavsiya etiladi.
Actions secrets:

- `KEYSTORE_BASE64`: JKS faylining base64 qiymati (maxfiy).
- `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
- Actions variable `API_BASE_URL`: haqiqiy HTTPS API origin.

Actions → **Signed Android release** → Run workflow. Ikkala flavor uchun APK va
AAB artifact chiqadi; avtomatik Play Store’ga yuborilmaydi. Keystore’siz release
build ataylab to‘xtaydi. `version`/build number’ni keyingi relizda oshiring.

## 8. Testlar

```bash
cd backend
python3 -m venv .venv
# Windows: .venv\\Scripts\\activate
. .venv/bin/activate
pip install -r requirements-dev.txt
# ffmpeg PATH ichida bo‘lishi kerak
python -m pytest -q tests
```

SQLite integratsiya testlari Postgres concurrency/load sinovini almashtirmaydi.
Tekshiruv natijalari: `docs/VALIDATION.md`. OpenAPI: `docs/openapi.json`.

## Tuzilishi

- `mobile/lib/features/*/domain` — sof Dart entity/use case/interfeyslar.
- `mobile/lib/features/*/data` — recorder/repository adapterlari.
- `mobile/lib/features/*/presentation` — Riverpod controller va ekranlar.
- `mobile/lib/core` — Dio, token, Hive, upload va cache.
- `mobile/lib/application.dart`, `student.dart`, `admin.dart` — sessiya va ilova shell’lari.
- `backend/app` — auth, owner/RBAC tekshiruvi, uploads, learning/admin, worker.
- `deploy`, `compose.yaml`, `.github/workflows` — ishga tushirish va CI.

Asosiy audio/analytics feature’lari Clean Architecture qatlamlariga ajratilgan;
admin/pilot yordamchi UI qismlari hali umumiy API adapteridan foydalanadi. Ularni
katta jamoa uchun alohida feature repository/use case’larga ajratish keyingi refaktor.
