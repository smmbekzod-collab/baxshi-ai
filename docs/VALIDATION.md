# Baxshi AI v0.3.1 tekshiruvlari — 2026-10-05

| Tekshiruv | Natija |
|---|---|
| Flutter 3.47.4 / Dart 3.13.3 analyze | No issues found |
| Flutter unit/widget tests (v0.3 baseline) | 15 passed |
| New admin provider and optional coach Flutter screens | Added, not executed in this workspace (Flutter SDK unavailable) |
| FastAPI + SQLite + FFmpeg tests (v0.3 baseline) | 20 passed |
| New AI-provider backend tests | Added, not executed in this workspace (dependency install network blocked) |
| OpenAPI | v0.3 sxemasi koddan qayta yaratildi |
| Yangi SVG logo | PNGga render qilinib ko‘zdan kechirildi |
| Android user APK | Urinish bajarildi, Gradle distribution yuklashda tarmoq bloklandi; APK yaratilmadi |
| Android admin APK | Xuddi shu build infratuzilmasi talab qilinadi; native build tasdiqlanmagan |
| Jonli Railway va haqiqiy Android qurilma | Ushbu tekshiruv doirasida tasdiqlanmagan |

## Nimalar real testdan o‘tdi

Backendning 20 testi: oldingi 11 xavfsizlik/upload/worker testi va 9 ta yangi integratsiya testi. Yangi testlar dars seeding idempotentligi, javoblar oldindan sizmasligi, shaxsiy quiz progressi, profil, avatar resize/validation/owner isolation, admin/ustoz ruxsatlari, chat IDOR va takroriy yuborish, ustoz ruxsatini bekor qilish, hisob o‘chirilganda avatar va shaxsiy matnni tozalashni qamraydi.

Audio zanjirida haqiqiy FFmpeg ishlatildi: WAV upload → job → DB worker → etalon dekodlash → DTW → report. Shu signal bilan pitch kontur mosligi ≥95 chiqishi tekshirildi; bu inson ijrosining ilmiy aniqligi degani emas. Alohida M4A/AAC dekodlash, etalonsiz 220 Hz o‘lchash va startupda alohida worker servisisiz embedded worker heartbeat paydo bo‘lishi tekshirildi.

Flutterning 15 testi retry siyosati, report/null metric validatsiyasi, tarjima kalitlari, dashboardning 390/1100 px hamda 1.4x matnda layouti, coach feedback, etalonsiz o‘lchov paneli, savollar to‘liq belgilanmaguncha quiz yuborilmasligi va profil/avatar boshqaruv elementlarini qamraydi.

## APK holati

v0.2 APK hash va natijalari v0.3 dalili sifatida ishlatilmadi. v0.3.1 arxivida source-code bor, tasdiqlangan yangi APK yo‘q. JDK 17, Android SDK va Flutter tayyorlangan, ammo Gradle wrapper’ning distribution yuklashi `java.net.SocketException: Network is unreachable` bilan to‘xtagan. GitHub Actions `Test and build APKs` har bir flavor uchun analyzer/test/build bajaradi; yashil natija va artifact hosil bo‘lgandan keyingina APKni sinang.

## Hali tekshirish kerak

Haqiqiy telefon mikrofon/fayl tanlash/TTS/lifecycle va sust internet; sizning Railway bazangiz va volume ruxsatlari; Postgres parallel yuklama; backup/restore; signed release va ilmiy model validatsiyasi. Yangi community/kurs ekranlari hozir o‘zbekcha. Push yo‘q, chat foreground polling qiladi. Darslar namunaviy, etalonlar sun’iy texnik signal.

Test runner `httpx` → `httpx2` deprecation ogohlantirishi berdi; testlar muvaffaqiyatli. Batafsil mahalliy loglar `docs/test-results/`da.


v0.3.1 qo‘shimchasi: Grok/Gemini/OpenAI provider sozlamalari va on-demand coach kodlari v0.3 test natijalaridan keyin qo‘shildi. Shu sabab v0.3 test sonlari yangi kod uchun dalil hisoblanmaydi; yangi backend va Flutter sinovlari CI’da yashil bo‘lishi kerak.
