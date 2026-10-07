# Ommaviy production oldidan

Bu ro‘yxat tugamaguncha mahsulotni **pilot** deb belgilang.

1. Haqiqiy HTTPS API domen, maxfiy kalitlar, doimiy signing key va birinchi admin.
2. Real Android qurilmalarda mikrofon ruxsati, interruption, fon/pauza, qayta kirish,
   sust internet, upload resume, logout cleanup, file picker va TTS sinovi.
3. Postgres bilan parallel chunk yozish, refresh rotation, worker lease/restart,
   API/worker crash va disk to‘lish sinovlari. Shared-volume bir host deployment;
   object storage/distributed worker uchun alohida adapter kerak.
4. Versiyalangan DB migratsiyalar, backup/restore drill, maxfiy kalit recovery,
   monitoring/alerting, dependency/security review, edge rate limiting.
5. Admin listlari (users 200, jobs 200), umumiy JSON object storage va ba’zi ACL
   tekshiruvlari katta bazaga mos query/pagination bilan qayta tuzilishi kerak.
   Bu versiya kichik pilot uchun; cheksiz foydalanuvchi masshtabi sinovdan o‘tmagan.
6. Mahalliy yozuvlar OS app sandboxida, baytlar shifrlanmagan. Threat model talab
   qilsa audio encryption va qurilma yo‘qolganda kirish siyosatini qo‘shing.
7. Hisob o‘chirilganda server kirishi darhol bloklanadi; worker audio/hisobotni
   tozalaydi. Pseudonymous audit/job/asset yozuvlari saqlanadi; backup retention
   va huquqiy privacy matni mahsulot siyosatiga mos yakunlanishi kerak.
8. Etalon yozuvlar uchun litsenziya va ijrochi roziligini tasdiqlang. Research CSV
   pseudonymous — qayta bog‘lash ehtimoli yo‘q degani emas. Litsenziya bekor qilinsa,
   oldin offline keshga tushgan nusxani masofadan yo‘q qilish kafolatlanmaydi.
9. Haqiqiy model/dataset, annotatsiya, ekspert validatsiyasi, fair evaluation va
   maktablar bo‘yicha xato tahlili. Nafas fiziologiyasi telefon audio’dan qat’iy baholanmaydi.
10. Auth/admin/history yordamchi UI tarjimalari va qoraqalpoqcha native review.

Bu paketda yo‘q: push notification/WorkManager background sync, to‘lovlar,
jonli transkripsiya, streaming AI inference, spektrogramma, o‘qitilgan maktab
klassifikatori, ovoz klonlash, LLM coach, tayyor Play Store listing.
Backendda guruh/topshiriq va teacher-review API mavjud; alohida teacher ilovasi yo‘q.


v0.3: profil avatari va matnli chat qo‘shildi. Account deletion avatarni o‘chiradi va yuborilgan xabar matnini redact qiladi; conversation/audit metadata saqlanadi. Dars/quiz/texnik etalonlar pilot namunalari; pedagog va baxshi ekspert ko‘rigidan o‘tkazing.

11. For optional LLM Coach, confirm privacy disclosure, vendor retention/billing terms and key rotation before enabling. Keep `ENCRYPTION_KEY` stable or add re-encryption migration first. Validate each vendor's current model ID and account quota. Provider API errors must fall back to local recommendations.
