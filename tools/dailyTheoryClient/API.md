# dailyTheory: HTTP API v1

This is the contract between the server (Phase 3) and the CLI client (Phase 4). Field types follow ARCH §2.
- Base URL: `http://localhost:8080` (configurable).
- All bodies are JSON (`Content-Type: application/json`, UTF-8). Times are RFC 3339 UTC.
- Request bodies are limited to 16 KiB. Unknown JSON fields are rejected (400).

## Authentication
- Authenticated routes need `Authorization: Bearer <token>`. The token is returned once by `POST /v1/users`.
- If the server has `REGISTRATION_KEY` set, `POST /v1/users` also needs `X-Registration-Key: <key>`.

## Errors
Every non-2xx response has this shape:
```json
{"error": {"code": "quota_exceeded", "message": "Daily limit of 5 reached.", "resets_at": "2026-10-21T00:00:00Z"}}
```
`resets_at` is present only for `quota_exceeded`. This holds for 404/405/413 too (never the stdlib plain-text bodies);
405 responses also carry an `Allow` header.

| HTTP | code | When |
|---|---|---|
| 400 | `invalid_request` | Malformed JSON, unknown fields, validation failure (message says which field) |
| 400 | `no_topics` | Interests text yielded no usable topics |
| 401 | `unauthorized` | Missing/invalid bearer token |
| 403 | `forbidden` | Missing/wrong `X-Registration-Key` |
| 404 | `not_found` | Unknown route |
| 405 | `method_not_allowed` | Wrong method on a known route |
| 413 | `payload_too_large` | Body > 16 KiB |
| 429 | `quota_exceeded` | Daily limit reached |
| 429 | `rate_limited` | Too many requests from this IP (Phase 5, signup) |
| 502 | `generation_failed` | LLM answered but output unusable after retries |
| 503 | `upstream_unavailable` | OpenRouter rate-limited/down/timeout after retries |
| 500 | `internal` | Anything else (details only in server logs) |

---

## `GET /healthz`
No auth. → `200 {"status": "ok"}`

## `GET /v1/topics`
No auth. Returns the curated catalog.
```json
{"topics": [
  {"id": "philosophy", "name": "Philosophy", "subtopics": ["Ancient Greek philosophy", "Stoicism", "Existentialism"]},
  {"id": "productivity", "name": "Productivity", "subtopics": ["Procrastination", "Habit formation", "Deep work"]}
]}
```

## `POST /v1/users`
Creates a user and derives their interest profile (one LLM call, ~3–10s).

Request:
```json
{"interests": "Stoicism, beating procrastination, and how the brain forms habits", "daily_limit": 5}
```
- `interests`: required, 3–1000 characters after trimming.
- `daily_limit`: optional, 1–10, default 5.

`201 Created`:
```json
{
  "user_id": "usr_3f9a1c2b7d4e8f60",
  "token": "dt_qJ8x...43chars",
  "interests": "Stoicism, beating procrastination, and how the brain forms habits",
  "daily_limit": 5,
  "profile": {
    "topics": [
      {"name": "Philosophy", "catalog_id": "philosophy", "weight": 4,
       "subtopics": [{"name": "Stoicism", "seeds": ["Dichotomy of control", "Marcus Aurelius"]},
                     {"name": "Virtue ethics", "seeds": ["Aristotle's golden mean"]}]},
      {"name": "Productivity", "catalog_id": "productivity", "weight": 4,
       "subtopics": [{"name": "Procrastination", "seeds": ["Temporal Motivation Theory"]},
                     {"name": "Habit formation", "seeds": ["Habit loop"]}]}
    ]
  },
  "created_at": "2026-10-20T09:12:00Z",
  "updated_at": "2026-10-20T09:12:00Z"
}
```
Errors: `invalid_request`, `no_topics`, `forbidden`, `generation_failed`, `upstream_unavailable`.

## `GET /v1/me`
Auth. Returns the user (without the token) plus the current quota.
```json
{
  "user_id": "usr_3f9a1c2b7d4e8f60",
  "interests": "…",
  "daily_limit": 5,
  "profile": { "…": "same profile object as in POST /v1/users" },
  "created_at": "…", "updated_at": "…",
  "quota": {"used": 2, "limit": 5, "resets_at": "2026-10-21T00:00:00Z"}
}
```

## `PUT /v1/me`
Auth. Partial update; omitted fields stay unchanged. At least one field must be present.
```json
{"interests": "Existentialism and quantum physics basics", "daily_limit": 8}
```
- If `interests` changed, the profile is re-derived (one LLM call). History and the no-repeat rule are kept.
- Lowering `daily_limit` below today's usage is allowed and simply blocks further theories today.

`200` returns the same shape as `GET /v1/me`. Errors are the same as `POST /v1/users`, plus `unauthorized`.

## `POST /v1/theories/next`
Auth. No request body. Generates the next theory (~3–10s) and counts it against the quota.

`200`:
```json
{
  "theory": {
    "id": "th_8c1e2a9f0b3d",
    "title": "Dichotomy of Control",
    "originator": "Epictetus",
    "topic": "Philosophy",
    "subtopic": "Stoicism",
    "theory": "Epictetus, a former slave turned teacher, argued that ... (≤200 words)",
    "key_takeaway": "Before reacting, ask: is this up to me? Put your energy only into what is.",
    "sources": [
      {"title": "Enchiridion", "author": "Epictetus (recorded by Arrian)", "year": "c. 125 CE", "type": "primary"},
      {"title": "Discourses", "author": "Epictetus (recorded by Arrian)", "year": "c. 108 CE", "type": "primary"}
    ],
    "related": ["Amor fati", "Serenity Prayer", "Locus of control"],
    "further_reading": [{"title": "A Guide to the Good Life", "author": "William B. Irvine"}],
    "disclaimer": "AI-generated summary; verify sources before citing.",
    "model": "provider/model-name:free",
    "generated_at": "2026-10-20T09:15:31Z"
  },
  "quota": {"used": 3, "limit": 5, "resets_at": "2026-10-21T00:00:00Z"}
}
```
`429` example:
```json
{"error": {"code": "quota_exceeded", "message": "Daily limit of 5 reached.", "resets_at": "2026-10-21T00:00:00Z"}}
```
Errors: `unauthorized`, `quota_exceeded`, `generation_failed`, `upstream_unavailable`. A failed generation does **not** count against the quota.

## `GET /v1/theories?limit=20`
Auth. History, newest first. `limit` defaults to 20 and must be 1–100 (otherwise `invalid_request`).
```json
{"theories": [{"id": "th_8c1e2a9f0b3d", "title": "Dichotomy of Control", "...": "full theory object as above"}]}
```
