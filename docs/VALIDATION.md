# Tekshiruv natijalari — 2026-10-03

| Tekshiruv | Natija |
|---|---|
| Flutter 3.47.4 / Dart 3.13.3 analyzer | No issues found |
| Flutter test | 12 passed |
| FastAPI + SQLite + FFmpeg integration/acoustics | 11 passed |
| User Android debug APK | assembleUserDebug — muvaffaqiyatli |
| Admin Android debug APK | assembleAdminDebug — muvaffaqiyatli |

Flutter testlari: retry policy, null metric va schema validatsiyasi, tarjima
kalitlari tengligi, 390/1100 px va 1.4x matnli dashboard, coach feedback.
Backend testlari: RBAC/OTP replay, refresh reuse/session revocation, logout,
lockout persistence, chunk retry/checksum, owner isolation, job idempotency,
worker report, optimistic policy version, teacher ACL, deletion cleanup,
signal/silence va local faylga murojaat qiluvchi playlistni rad etish.

Android buildlar JDK 17 va rasmiy Android SDK bilan bajarildi. API URL
`https://api.example.invalid` edi. Bu **kompilyatsiya tekshiruvi**; jonli
serverga kirish yoki real mikrofon sinovi emas. ZIP source-code paketidir;
161 MB atrofidagi har bir debug APK arxivga qo‘shilmagan. GitHub Actions
API_BASE_URL bilan qurilmaga mos APK’larni qayta yaratadi.

Qolgan tekshiruvlar: real Android device, Postgres concurrency/load,
server deploy/TLS, worker restart/disk failure, signed-release APK/AAB,
Play Store, backup/restore va ilmiy model validatsiyasi.

Build ogohlantirishi: flutter_tts hozir Kotlin Gradle Plugin qo‘llaydi;
kelajak Flutter versiyasida migratsiya talab qilishi mumkin. Shu sabab SDK va
pubspec.lock mahkamlangan. Backend test runner httpx→httpx2 deprecation
ogohlantirishi berdi; testlar muvaffaqiyatli o‘tdi.
