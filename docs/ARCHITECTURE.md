# Architecture and operational contract

Two entrypoints and Android flavors share one Flutter codebase. JWT roles are
checked on the server for every request; hiding UI is never authorization.
Student audio files, upload session keys and reports are namespaced by subject.
Session restoration may use cached user profile during network failure;
administrative session restoration always requires online verification.

The recording controller serializes start/pause/resume/stop and publishes the
stopped state before persistence. Foreground-only recording pauses on lifecycle
interruption. Uploads send reusable byte arrays, one chunk at a time. Retrying a
consumed stream is forbidden. Network retry applies only to replayable idempotent
requests. A shared refresh future avoids parallel refresh races.

FastAPI owns auth, ownership/RBAC and storage metadata. PostgreSQL row locks
serialize upload offsets and user quota. Disk writes use temp files and atomic
rename; database/disk operations are not a distributed transaction. Crash recovery
may leave orphan files; production needs disk reconciliation and alerts.

Worker claims a persistent queued job with SKIP LOCKED, a 10-minute lease and
attempt count. It checks lease ownership before committing a result. Keep decoder
and analysis bounded well below the lease; heavier models require renewal.
A worker must share the exact media path with the API. No in-process background
Task is relied on for durable analysis.

Server retains audio for policy retention_days (default 30). Active tasks and
licensed references pin their assets. Reports remain until account deletion;
retention_days is not a report retention policy. Cleanup runs hourly in worker.

All acoustic reports are schema version 1. Five metrics must be distinct. Null
means unavailable, never zero. Model version and reference ID must match before
longitudinal comparisons are meaningful. DTW time labels are approximate;
this is not forced alignment or an objective artistic rubric.

Admin edits to policy include a version for optimistic concurrency. Other edits
are last-write-wins. Audit entries are database records, not tamper-proof external
security logs. Provisioning creates admin accounts locally, with Argon2 password
hashes and encrypted TOTP seeds. TOTP recovery is an operator task; no public admin
signup or default credentials exist.


## v0.3 additions

`runtime.py` starts an embedded durable DB worker by default, emits heartbeats, and supports a separate worker process via EMBEDDED_WORKER=false. Readiness includes FFmpeg and a recent heartbeat. New additive tables store worker heartbeats, conversations and idempotent messages. Owner-scoped JSON objects store profile and lesson progress. `social.py` rechecks teacher group membership on every conversation request. `education.py` grades quizzes on the server. `seed.py` creates original pilot lessons and synthetic technical references once. Avatar images are decoded, resized and stripped of metadata before atomic storage. New mobile community/learning screens use Riverpod and the shared authenticated Dio client.

## Optional LLM providers (v0.3.1)

The default remains local acoustics and rule-based coach feedback. Admin config chooses a fixed provider host (xAI, Google Gemini, or OpenAI) and model ID. The key is Fernet-encrypted in the existing JSON object store using the existing `ENCRYPTION_KEY`; API responses never include it. Do not rotate `ENCRYPTION_KEY` without first re-encrypting this stored credential.

A user must confirm each on-demand coach request. The backend sends anonymous acoustic metric JSON only, with no audio, account ID, or profile. Failures return the local coach message. Admin connectivity checks are explicit, token-limited requests. Provider hosts are fixed in code to prevent an admin value from creating an SSRF target.
