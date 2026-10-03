# FastAPI contract — implementation required

This document specifies required behavior. No HTTP server or trained model is
included. All endpoints are under an HTTPS origin supplied via API_BASE_URL.
JWT access tokens identify the subject. Every lookup/upload/reference/report
must enforce ownership or explicit license entitlement on the server.
Never trust a subject ID, school selection, asset ID or score supplied by a client.

## Auth
POST /v1/auth/refresh {refresh_token} -> {access_token, refresh_token}
Rotate refresh tokens, revoke token families on replay, hash stored refresh tokens.
An OIDC authorization-code + PKCE login flow is recommended. The mobile reference
contains a TokenStore and refresh logic but DOES NOT implement interactive login.
An auth adapter writes Tokens(access, refresh, verifiedSubject). On logout cancel
requests, invalidate account providers, clear account cache and tokens, stop players.
Do not ship access/refresh tokens in dart-define, source code or a login bypass.

## Resumable uploads
POST /v1/uploads with Idempotency-Key: stable recording UUID
{recording_id, size, sha256, mime} -> 201 {id}
GET /v1/uploads/{id} -> {offset: integer}
PUT /v1/uploads/{id}/chunks/{offset}, application/octet-stream -> 204
Headers: Content-Range, X-Chunk-SHA256, Idempotency-Key.
POST /v1/uploads/{id}/complete {sha256} -> {asset_id}

Server must transactionally accept only the next contiguous byte range. A retry
of an already accepted range must return success only for IDENTICAL bytes and hash.
A mismatched body under the same idempotency key returns 409. Serialize overlapping
requests per upload. GET offset is authoritative after a crash or lost response.
Complete verifies expected length and full hash before media probing and ingestion.
Duplicate complete returns the SAME asset_id, including after a lost response.
Persist idempotency responses for the entire resumable session lifetime. Return
410 for an expired upload; current client surfaces an error (restart UX is pending).
Limit per-file duration/bytes, user quota, concurrent uploads and chunk size.
Never concatenate untrusted path strings or interpret byte chunks as WAV files.
Mobile hashes file using streams and holds at most ~1 MiB for each upload chunk.
Mobile cancel stops transport but leaves the server session resumable.

## Analysis jobs
POST /v1/analyses with Idempotency-Key
{asset_id, school, locale, reference_id: string|null, consent_version} -> 202 {job_id}
GET /v1/analyses/{job_id} -> {status: queued|running|completed|failed,
  progress: 0..1, report_id: string|null, error_code: string|null}
GET /v1/reports/latest -> the report schema in assets/demo_report.json
GET /v1/reports/{id} -> same schema
GET /v1/reports/{id}/coach-audio -> {asset_id, sha256}
GET /v1/assets/{id}/content -> AAC/M4A bytes, with byte-range support

Report response must have schema_version=1 and all five metric keys exactly once.
Unavailable score is null with a reason, NEVER zero. Confidence is [0,1], score is
[0,100]. Samples are strictly increasing seconds and aligned normalized pitch
scores, not Hz. Feedback start/end identify source-recording time. Return localized
coach content according to the job locale. Never put user audio or transcripts in logs.
Set demo=false only for actual computed reports. Attach real model and reference IDs.
A reference_id=null should not invent a master comparison; return empty samples
and null metrics where the analysis method requires a matching licensed reference.

The reference UI submits jobs and displays their ID; it does not poll completion.
The refresh button fetches the latest report. Production: add resumable job polling
or authenticated SSE, status notification, cancellation and exact report navigation.

## Errors
Use 401 expired/invalid session, 403 ownership/entitlement, 404 unknown,
409 hash/idempotency mismatch, 410 expired upload, 413 too large,
422 bad audio/schema, 429 rate limit with Retry-After, 503 temporary unavailable.
Response: {code, message, request_id}; do not include internal exception details.
Require JSON content type for JSON responses. Unavailable report -> 404, not demo data.

## Production deployment (not included)
FastAPI handles auth/validation/job scheduling; PostgreSQL stores metadata and
row-level access; private object storage holds audio; a queue dispatches CPU/GPU
workers. Model inference and ffmpeg must run outside HTTP request processes.
Use signed short-lived download URLs only through a separate unauthenticated
client with a strict storage-host allowlist. Current client only uses same-origin
API content endpoints. Configure HTTPS byte streaming or internal object proxying.
