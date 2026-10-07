# Changelog

## 0.3.1 — optional AI coach provider settings

- Added Super Admin settings for xAI/Grok, Google Gemini, OpenAI/ChatGPT, or local-only coach mode.
- API credentials are encrypted on the backend with the existing `ENCRYPTION_KEY`; secrets are never returned to clients.
- Added admin-only provider connectivity test with rate limiting.
- Added a one-request consent dialog before sending anonymous acoustic metrics to the selected provider.
- Audio, account identifier, and profile data are not included in AI requests. Disabled or unavailable providers use existing local coach feedback.
- No database schema migration required. Preserve Railway `DATABASE_URL`, `JWT_SECRET`, `ENCRYPTION_KEY`, media volume, and existing super admin.

## 0.3.0 — student experience and working analysis flow

See README and `docs/VALIDATION.md` for functionality and verified baseline results.
