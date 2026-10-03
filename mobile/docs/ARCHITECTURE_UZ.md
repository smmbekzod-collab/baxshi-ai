# Baxshi AI — mobil platforma arxitekturasi

## Maqsad va chegaralar
Ushbu paket uchta asosiy ekran va muhim infratuzilma uchun reference implementation.
Bu sinovdan o‘tgan production APK, tayyor backend yoki tayyor sun’iy intellekt modeli emas.
“Super APK” mahsulot nomi bo‘lishi mumkin; APK — Android o‘rnatish fayli, barcha
hisoblashlarni uning ichiga joylashtirish shart emas. Dastlab og‘ir tahlil serverda,
yozuv, amplituda, kesh va tinglash telefonda bajariladi.

## Qatlamlar va bog‘lanishlar
Presentation -> Domain <- Data. Core/providers.dart kompozitsiya ildizi.
Domain ichida Flutter yoki Dio yo‘q. AnalysisRepository va Recorder portlari Data
adapterlarini almashtirishga imkon beradi. LoadLatestReport use-case; Riverpod
controller asinxron yozuv holatlarini boshqaradi. UI faqat provider orqali murojaat
qiladi. Upload orchestration hozir ekran ichida: kengaytirishda alohida
SubmitAnalysis use-case va UploadController ga ko‘chirish rejalashtiriladi.

lib/
  core/          tarmoq, token, shifrlangan Hive, kesh, chunk uploader, DI
  features/
    analysis/    domain/report, data/repository, presentation/dashboard
    recording/   domain/recorder, data/device, presentation/controller + screen
    coach/       presentation/feedback
  shared/        holat UI va offline audio player
  l10n/          uz/kaa/en matn kataloglari va til holati
backend_reference/  FFmpeg konvertatsiya yordamchisi, AI emas

## Yozuv siyosati
48 kHz mono WAV — tahlil uchun asl ovoz; AAC 128 kbit/s — trafikni kamaytiruvchi
muqobil. Qurilma kodek imkoniyati tekshiriladi. Amplituda 60 ms oralig‘ida olinadi,
oxirgi 100 nuqta saqlanadi. Bu PCM waveform yoki spektrogramma emas, dBFS envelope.
Avtomatik gain/noise suppression/echo cancellation o‘chirilgan: timbrni sun’iy
ravishda o‘zgartirmaslik uchun. Qurilma signali baribir kalibrlashni talab qiladi.
Tanaffus va davom ettirish bor. Ekran fon holatiga o‘tganda yozuv pauzalanadi.
20 daqiqa foreground limit bor; OS jarayonni o‘ldirganda WAVni tiklash kafolati yo‘q.
Yozuvning metadata va yo‘li Hive’da saqlanadi, fayl app-private katalogda qoladi.
Yozuvlar ushbu starterda qurilmaga tegishli, account tarixi ekrani hali yo‘q.

Konvertatsiya telefondagi fayl kengaytmasini almashtirish emas. FFmpeg worker
asl yozuvdan 48 kHz analysis WAV, 16 kHz speech-model WAV yoki AAC nusxa yaratadi.
Asl faylni saqlang. Pitch/timbr tahliliga lossless master bering, tinglash uchun
siqilgan nusxa bering. Live inference uchun kelajakda PCM freymlar, sequence number,
backpressure va reconnect protokoli kerak; byte upload chunking buni almashtirmaydi.

## Baholash metodikasi: eng muhim qism
1. Ohang: etalon jumla bilan moslashtirilgan F0 trayektoriyasi, cents xatosi,
   voiced-frame ulushi. Vokal diapazoni/transpozitsiyani hisobga olish kerak.
2. Ritm: onset va fraza vaqtlari; erkin ritmli ijroda metronomga majburlamang.
3. Nafas: fraza uzunligi va pauzalardan ehtiyotkor akustik taxmin. Oddiy mikrofondan
   o‘pka hajmi yoki fiziologik nafas nazoratini aniq o‘lchab bo‘lmaydi.
4. Rezonans: spektral xususiyatlar asosidagi taxmin. Mikrofon/cholg‘u/shovqin
   ta’sirida ishonchlilik past bo‘lsa ball bermang.
5. Uslub: maktabga o‘xshashlik, “san’at sifati” yoki “haqiqiy baxshi” degani emas.
   Aralash uslub va unknown holati bo‘lsin. Kalibrlanmagan similarityni ehtimollik
   sifatida ko‘rsatmang. Ushbu UI 0–100 rubric score va alohida confidence ko‘rsatadi.

Backend har bir metrikaning dalili, vaqt belgisi, model va etalon versiyasini
qaytaradi. Umumiy ball yo‘q: o‘zboshimcha o‘rtacha baho ishlab chiqilmagan.
Ustozlar tasdiqlagan vaznli rubrika keyingi bosqichda qo‘shiladi.

## AI pipeline (ishlab chiqilishi kerak)
Qabul -> checksum/MIME/duration -> sifat darvozasi -> kerak bo‘lsa vokalni ajratish
-> F0/onset/timbre xususiyatlari -> bir xil asar/parchani vaqt bo‘yicha moslashtirish
-> maktabga mos rubrika -> confidence calibration -> dalilli tavsiya -> TTS.
LLM tayyor metrikaning izohini tuzadi; o‘zi eshitmagan audio uchun ball yaratmaydi.
TTS oddiy litsenziyali ovozdan foydalanadi. Ustoz ovozini klonlash alohida ruxsat
va huquqlar boshqaruvini talab qiladi; bu starterda mavjud emas.
Dataset ijrochi, asar va qurilma bo‘yicha ajratilsin; bir ijrochining nusxalari
train/testga birga tushmasin. Har maktab bo‘yicha xatolik va ustozlar bilan
kelishuv o‘lchansin. Qurilma, yosh/ovoz diapazoni, jins va shovqin kesimlari tekshirilsin.

## Men qo‘shishni tavsiya qiladigan modullar
P0 — haqiqiy pilot uchun:
- Sifat darvozasi: sukut, clipping, shovqin, cholg‘u balandligi, juda qisqa yozuv.
- Litsenziyali etalon katalogi: ustoz, maktab, asar, parcha, ruxsat muddati.
- Ustoz bahosi: AIga tuzatish, rubrika, ikki baholovchi, fikrlar tarixi.
- Akkaunt/PKCE, consent, eksport/o‘chirish, retention va account-scope offline tarix.
- Upload/job queue: process restart, Wi-Fi only, batareya sharti, cancel, retry.
- Noma’lum/aralash uslub, confidence va baholashni rad etish holati.

P1 — o‘rganish qiymati:
- A/B tinglash, jumla takrori (loop), tezlikni pitchni o‘zgartirmay pasaytirish.
- Vaqt belgili tavsiyani bosganda aynan xato parchasiga o‘tish.
- 7/30/90 kunlik o‘sish: bir xil rubrika/model versiyasi bo‘yicha taqqoslash.
- Kunlik reja, mashq bajarilganligini qayd etish, mahalliy eslatmalar.
- Doston matni + vaqtga mos satrlar; sheva/transkripsiya ustoz tekshiruvi bilan.
- Talaba va ustoz kabineti, guruh topshiriqlari, baholash izohlari.

P2 — kengayish:
- Sizning ilmiy tajriba-sinovingiz uchun rozilikka asoslangan anonim ID,
  boshlang‘ich/yakuniy natija eksporti, guruhlar va rubrika versiyasi.
- BaxshiAI.uz bilan yagona akkaunt, ustozlar, darslar va kontent API.
- Katalog, to‘lov va obuna, tashkilot uchun tariflar — asosiy ta’lim funksiyalaridan
  alohida modul. Avval AI aniqligi va ustoz foydaliligini pilotda tekshirish.
- Oflayn yengil tahlil: faqat aynan qurilmada validatsiya qilingan model bilan.

## Xavfsizlik va kuzatuv
JWT secure storage; Hive AES kaliti secure storage’da; media esa app sandboxda,
lekin qo‘shimcha per-file shifrlash yo‘q. LRU kesh faqat qayta yuklanadigan media
uchun; foydalanuvchi yozuvlarini avtomatik o‘chirmaydi. Demo va live qatlamlari
aralashtirilmaydi. Loglarda audio, token yoki matn bo‘lmasin. Crash reporting opt-in,
request ID, upload latency, queue duration, model latency va quota kuzatilsin.

## Release mezonlari
Flutter analyze/test + Android debug/release build; haqiqiy qurilma mikrofonlari;
ruxsat rad etilishi, qo‘ng‘iroq/audio focus, ekran o‘chishi, past xotira, disk to‘lishi;
401 concurrency, refresh outage, logout race; chunk response yo‘qolishi, 410 upload,
413 va 429; ishchi background service; mahalliy cache migration; privacy/export/delete;
TalkBack, 200% matn, dark/light va til tekshiruvi. Keyin ichki imzolangan APK/AAB.
