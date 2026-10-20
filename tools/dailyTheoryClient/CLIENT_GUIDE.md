# dailyTheory: client app developer guide

This is a handoff for anyone (or any AI chat) building a client app against the dailyTheory API, in parallel with the server.
Give it this file **and `docs/API.md`**. API.md is the authoritative contract: if this guide and API.md ever disagree, API.md wins.

## 1. What the server does
dailyTheory serves short theories (≤200 words), each with sources and matched to the user's free-text interests. A user signs up with
interests plus a daily limit (1–10), gets a bearer token, and then asks for theories one at a time until the limit resets
at 00:00 UTC. Theories never repeat, and the user can view their history.

## 2. Server status (as of 2026-10-20)
| Endpoint | Available |
|---|---|
| `GET /healthz` | ✅ now (Phase 1) |
| `GET /v1/topics`, `POST /v1/users`, `GET/PUT /v1/me`, `POST /v1/theories/next`, `GET /v1/theories` | ⏳ Phase 3 |
| `429 rate_limited` on signup | ⏳ Phase 5 |

Until Phase 3 ships, build against a **mock** (§7). The shapes in API.md are frozen for v1. Any change will be recorded
under "Contract changes" in `docs/PROGRESS.md`, so check that file when you sync.

## 3. Basics
- Base URL is configurable; the default is `http://localhost:8080`. Don't hard-code it.
- Every request and response body is JSON (UTF-8). Times are RFC 3339 UTC strings.
- The server **rejects unknown JSON fields** with 400. Send only the documented fields.
- Request bodies are limited to 16 KiB.
- Auth: `Authorization: Bearer <token>`. The token is returned **only once**, by `POST /v1/users`. Store it securely
  (OS keychain / secure storage). It can't be recovered: if it's lost, the user has to sign up again.
- If the server has a registration key set, signup also needs `X-Registration-Key: <key>`. Add an optional settings field for it.

## 4. Endpoints at a glance
| Method & path | Auth | Purpose | Typical latency |
|---|---|---|---|
| `GET /healthz` | – | Liveness check | <100 ms |
| `GET /v1/topics` | – | Curated catalog, used for interest suggestions | <100 ms |
| `POST /v1/users` | reg. key (optional) | Sign up `{interests, daily_limit?}` → token + profile | **3–10 s** (LLM) |
| `GET /v1/me` | ✅ | User, profile and `quota` | <100 ms |
| `PUT /v1/me` | ✅ | Partial update `{interests?, daily_limit?}` (at least one field) | 3–10 s if interests changed |
| `POST /v1/theories/next` | ✅ | Next theory + `quota` (no body) | **3–10 s, p95 <15 s** |
| `GET /v1/theories?limit=N` | ✅ | History, newest first (N is 1–100, default 20) | <100 ms |

See API.md for the full request and response JSON.

## 5. Data types (TypeScript notation; port them to your language)
```ts
type Source = { title: string; author: string; year: string; type: string }; // year is free text, e.g. "c. 125 CE"
type Reading = { title: string; author: string };
type Theory = {
  id: string; title: string; originator: string; topic: string; subtopic: string;
  theory: string;            // ≤200 words, plain text
  key_takeaway: string;
  sources: Source[];         // ≥1
  related: string[];
  further_reading: Reading[];
  disclaimer: string;        // always show it
  model: string; generated_at: string;
};
type Quota = { used: number; limit: number; resets_at: string };
type Subtopic = { name: string; seeds: string[] };
type ProfileTopic = { name: string; catalog_id?: string; weight: number; subtopics: Subtopic[] }; // catalog_id may be absent/empty for free-form topics
type Profile = { topics: ProfileTopic[] };
type User = { user_id: string; interests: string; daily_limit: number; profile: Profile;
              created_at: string; updated_at: string };
type Me = User & { quota: Quota };
type SignupResponse = User & { token: string };
type NextResponse = { theory: Theory; quota: Quota };
type HistoryResponse = { theories: Theory[] };
type CatalogTopic = { id: string; name: string; subtopics: string[] };
type TopicsResponse = { topics: CatalogTopic[] };
type ApiError = { error: { code: string; message: string; resets_at?: string } };
```
Parse leniently: ignore fields you don't recognise, and treat missing optional arrays as empty.

## 6. Error handling
Every non-2xx response has the `ApiError` shape. Branch on `error.code`, not on the HTTP status or the message text.

| code | Suggested UX |
|---|---|
| `invalid_request` | Show `message`; it names the field |
| `no_topics` | "Couldn't find topics in that, try being more specific." Offer suggestions from `/v1/topics` |
| `unauthorized` | Token invalid: clear it and go back to signup |
| `forbidden` | Ask for, or fix, the registration key |
| `quota_exceeded` | "You've had all N for today." Show a countdown to `resets_at` (converted to local time) |
| `rate_limited` | "Too many signups, try again later" |
| `generation_failed` / `upstream_unavailable` | "Couldn't generate right now," with a Retry button. **These don't use up quota** |
| `internal`, network error, timeout | Generic error + Retry |

## 7. Building before the server exists: the mock
Use a mock that returns the example payloads from API.md. Options: a tiny local mock server (any language), MSW (web),
or a fake `ApiClient` implementation behind an interface. Put a single `ApiClient` interface in the app, with one
real implementation and one mock, so switching over is a config flag.

The mock should simulate:
- 3–8 s of latency on `POST /v1/users`, `PUT /v1/me` (when interests change) and `POST /v1/theories/next`
- the quota: count `/next` calls, return `429 quota_exceeded` with `resets_at` = next UTC midnight once `used == limit`
- a different `title`/`id` on each `/next` call, with history returning the served theories newest first
- occasional `503 upstream_unavailable`, to exercise the retry UI
- `401` for a wrong token

To check against the real server once Phase 3 lands: from the server repo, `scripts/with-server.sh` starts a
throwaway server and exports `$SERVER`. You can also run `go run ./cmd/server`, which needs an OpenRouter key in its env.

## 8. Client requirements and tips
- **Timeouts:** set ≥30 s for the three LLM-backed calls (the server's own LLM timeout is 60 s), 10 s for everything else.
  Show a loading state; there's no streaming in v1.
- **Don't auto-retry `/next` in a loop.** Every attempt can cost shared free-tier LLM quota on the server (about 50 requests/day per server).
  Retry only when the user taps.
- Prevent double taps on "Next": disable the button while a request is in flight.
- Show quota as `used / limit` and `resets_at` in local time. Refresh it from the `quota` in each `/next` response or from `GET /v1/me`.
- Always display `disclaimer` and the `sources`. The sources are AI-claimed and unverified, and there are no URLs in v1.
- For an interest picker, offer `/v1/topics` subtopics as chips that append to the free-text interests string. The server only takes the text.
- If the user lowers `daily_limit` below today's usage, that's allowed: `/next` just returns 429 until the reset.

## 9. Known constraints / open questions
- **Browser apps:** the server currently sends **no CORS headers**, and a web frontend is out of scope for v1 (PRD §7).
  A native, mobile or desktop app (or a web app behind a same-origin proxy) works as is. If you need direct browser
  access, raise it with the server owner; adding CORS is a server change that needs approval.
- No accounts, logout endpoint or token rotation in v1. "Log out" means deleting the token locally.
- No push notifications or scheduling on the server. If you want "remind me 3×/day", do it client-side with local notifications.
- English only. Resets happen at UTC midnight, not the user's local midnight.
