# Official Anime365 identity and catalogue API contracts

Research snapshot: 2026-08-20

## Question and source boundary

This note answers what the official Anime365 contract says about identity, Subscription eligibility, Catalogue browsing, search, Series, Episode, translation metadata, and Watch History. The source of truth is Anime365's current [API documentation](https://smotret-anime.org/api-docs) and the exact [OpenAPI 3.0.3 schema loaded by that page](https://smotret-anime.org/api/openapi.yaml?v=1786984811). Anime365's [help page](https://smotret-anime.org/help) independently directs developers to that documentation and to the first-party API-client registration page.

No community wrappers, reverse-engineered endpoints, or inferred first-party web-client calls are treated as contracts here. Live unauthenticated calls were used only to check whether the published contract behaves as described; observations that diverge from the schema are explicitly labelled as observations.

## Executive answer

The official API is sufficient to build tolerant, read-only clients for Catalogue, search, Series, Episode, and translation metadata, and to read a coarse authenticated Subscription state. It does **not** document a complete native-app identity lifecycle: credentials are exchanged by a `GET` query, tokens are long-lived until password change, and there is no refresh, revoke, scope, or device-session API. It also contains **no Watch History or playback-progress endpoint or schema**. Therefore, Anime365 cannot be treated as the canonical Watch History store unless Anime365 supplies an additional official contract.

## Authentication, token lifecycle, and Subscription

The official authentication contract is an `apiKey` named `access_token` in the query string. Catalogue, Episode, and translation metadata are public; user data and the protected translation embed operation require the token. Anime365 asks every client to send a `User-Agent` naming its site or program. The documented default server is `https://smotret-anime.app/api`, while the introduction permits relative `/api` requests on the domain serving the documentation; the documentation was served from `smotret-anime.org` for this snapshot. These details are all stated in the [OpenAPI introduction and security scheme](https://smotret-anime.org/api/openapi.yaml?v=1786984811).

| Operation | Official contract | Documented failures or gaps |
|---|---|---|
| Register an API client | Create a client on [`/api-clients`](https://smotret-anime.org/api-clients) and receive an `app` identifier. `app` is explicitly public and may be embedded in a public/open-source application. | No machine API, registration schema, approval policy, redirect URI, bundle-ID binding, or client-secret concept is documented. |
| `GET /api/login` | Required query parameters are `app`, `email`, and `password`; success returns `{ "data": { "access_token": string } }`. | `403` means either unknown application or invalid email/password. Putting credentials in a URL query is the only documented direct native-client exchange. |
| `GET /api/accessToken` | Required `app`; issues the same token shape for the user already signed into the Anime365 website, including social-login users. | `403` means either no website session or unknown application. No OAuth authorization redirect, callback, PKCE, authorization code, or native handoff is specified. |
| Token use | Pass `access_token` as a query parameter to protected operations. | No authorization-header alternative is documented. Query-bearing URLs must consequently be treated as secrets in logging, diagnostics, caches, and error reporting. |
| Token lifetime | The token has no expiry and remains valid until the user changes their password. | No refresh endpoint, refresh token, expiry timestamp, proactive renewal, explicit revocation, logout, token inventory, or remote device/session management is documented. Password change is the only documented invalidation event. |
| `GET /api/me` | With a token (or current site session), returns a `User`; without authenticated state it still returns `200` with `isLogined: false`. The declared fields are `isLogined: Bool`, integer `id`, `name`, `isPremium: Bool`, and `premiumUntil: String`. | No error response is declared for this operation. `premiumUntil` has no OpenAPI `date-time` format or timezone semantics. No Subscription tier, grace period, renewal state, billing state, family entitlement, or entitlement-change stream is defined. |
| Playback eligibility | The protected translation embed operation requires a token belonging to an account with an active Subscription; `403` covers either not being logged in or not having an active Subscription. | The failure does not distinguish authentication from entitlement. There is no separate eligibility endpoint beyond interpreting `/me` and handling the protected-operation result. |

The table above comes from the schema's `Account` operations, `User` and `AccessTokenResponse` schemas, and authorization introduction in the [official OpenAPI document](https://smotret-anime.org/api/openapi.yaml?v=1786984811). A first-party unauthenticated [`/api/me`](https://smotret-anime.org/api/me) response also currently demonstrates the documented guest shape, but it should not be used to infer behavior for invalid or revoked tokens.

### Identity state that a client may safely model

The documented states are only:

- guest (`isLogined == false`);
- signed in without current premium (`isLogined == true`, `isPremium == false`);
- signed in with current premium (`isLogined == true`, `isPremium == true`, with an opaque `premiumUntil` string);
- failed protected access (`Error.code == 403`), whose cause may be either authentication or Subscription eligibility.

Anything more detailed would be an application policy, not an Anime365 contract. In particular, automatic “token refresh” should not appear in the design: the only documented recovery is to reacquire a token after credentials/session authentication. The long-lived token is the persistent credential and belongs in Keychain; `app` is configuration, not a secret.

## Catalogue, search, Series, Episode, and translation metadata

All successful responses are wrapped in `data`; list operations place an array there. Errors use `{ "error": { "code": integer, "message": string, "fields"?: object } }`. `pretty=1` and `callback` are documented globally for formatted JSON and JSONP respectively. The following surface is declared in the [official OpenAPI paths](https://smotret-anime.org/api/openapi.yaml?v=1786984811).

| Resource | Operations and filters | Declared fields and relationships | Declared errors |
|---|---|---|---|
| Series | `GET /series`; `GET /series/{id}`. List parameters: `limit`, `offset`, `fields`, title `query`, catalogue `chips`, `afterId`, `order=id`, exact `myAnimeListId`, `isActive`, `isAiring`, `type`, `year`, and `season`. | Integer `id`; external `myAnimeListId`; scores; episode count; season/year/type; integer active/airing/hentai flags; poster URLs; language-keyed `titles`; open-ended `links`. The detail description says it includes Episodes, but the `Series` schema does not declare their property or shape. | Detail declares `404`; list declares only `200`. |
| Episode | `GET /episodes`; `GET /episodes/{id}`. List filters: `seriesId`, numeric `episodeInt`, `episodeType` (`tv`, `movie`, `ova`, `ona`, `special`), `isActive`, and `isFirstUploaded`, plus common paging/projection. | Integer `id` and `seriesId` link the Episode to Series; `episodeFull`, numeric `episodeInt`, title/type, first-upload timestamp string, and integer flags. The detail description says it includes translations, but the `Episode` schema does not declare their property or shape. | Detail declares `404`; list declares only `200`. |
| Translation metadata | `GET /translations`; `GET /translations/{id}`. List filters: `seriesId`, `episodeId`, `feed`, `afterId`, `type`, `qualityType`, and `isActive`, plus common paging/projection. Feeds are `recent`, `id`, `all`, `updatedDateTime`, and `addedDateTime`. | Integer `id`, `seriesId`, and `episodeId` define both relationships. Other declared fields include added/active/updated timestamp strings, authors, `fansubsTranslationId`, integer active/priority flags, quality/type/kind/language/title/URLs, and media dimensions/duration. | Detail declares `404`; list declares only `200`. |
| Video metadata | `GET /videos/{id}`. | Integer `id`, `episodeId`, and `seriesId`, plus filename, translation type/kind/language, and an array `urlList`. | Declares `404`. The operation itself declares no security even though the document introduction says video links through embed require authorization; do not infer stream authorization from `Video.urlList`. |

The public [`/api/series`](https://smotret-anime.org/api/series?limit=1&fields=id%2Ctitles%2CtypeTitle%2CposterUrlSmall), [`/api/episodes`](https://smotret-anime.org/api/episodes?limit=1&fields=id%2CseriesId%2CepisodeFull%2CepisodeInt%2CepisodeTitle%2CepisodeType%2CisActive), and [`/api/translations`](https://smotret-anime.org/api/translations?limit=1&fields=id%2CseriesId%2CepisodeId%2CauthorsSummary%2Ctype%2CtypeKind%2CtypeLang%2CqualityType%2CisActive) endpoints were sampled without authentication and returned the documented envelope and projected relationships on 2026-08-20.

### Search and filtering limits

`query` is the only documented title-search input, and search is the same paged Series-list response rather than a separate resource. `chips` accepts the site's advanced-filter string; the sole documented grammar example is `genre@=8,35;genre_op=and`. No complete chips grammar, allowed keys/value catalogue, escaping rules, search normalization, locale behavior, relevance ordering, match score, highlighting, autocomplete, or fuzzy-match guarantee is specified. Exact filters are only those enumerated on `/series`. These limits are visible in the [`/series` operation](https://smotret-anime.org/api/openapi.yaml?v=1786984811).

### Identifiers and schema resilience

Anime365 identifiers in these models are integers. The stable joins actually declared are `Episode.seriesId -> Series.id`, `Translation.seriesId -> Series.id`, `Translation.episodeId -> Episode.id`, and equivalent Series/Episode links on `Video`; `Series.myAnimeListId` is the only declared external catalogue identifier. No globally unique string, slug, revision, or deletion tombstone is documented.

All four resource schemas set `additionalProperties: true`, and their listed response properties are not marked `required`. Several timestamp fields are plain strings with no format or timezone. A conforming client must therefore tolerate unknown fields and missing declared fields, and it should preserve raw identifiers rather than synthesize identity from names, episode numbers, or URLs. The text promises nested Episodes/Translations on detail operations, but their property names and nested shapes are not schema-level contracts. These conclusions follow directly from the [official component schemas](https://smotret-anime.org/api/openapi.yaml?v=1786984811).

## Pagination and ordering

The shared list contract is `limit` (default 50, documented maximum 1000), `offset` (default 0), and optional comma-separated `fields`. No total count, next link, page number, cursor token, or end-of-list flag is declared. End of data therefore has to be inferred from the returned array.

For large scans, Anime365 explicitly says not to use `offset`, because it becomes slow on hundreds of thousands of records. `/series` and `/translations` support `afterId`, meaning records with `id` greater than the supplied value. Series can request ascending `order=id`; Translation can request `feed=id` (or `all`, which includes inactive records) for a stable full scan. Episodes have no declared `afterId` scan. The contract does not define snapshot isolation, behavior when records are inserted during a scan, duplicate suppression, or upper bounds for concurrent requests. See the [pagination introduction and list parameters](https://smotret-anime.org/api/openapi.yaml?v=1786984811).

## Watch History and mutation semantics

There is no Watch History, watched-state, playback-position, progress, resume, or history-mutation path or schema anywhere in the complete official OpenAPI path list. The only documented paths are Series, Episodes, a Video lookup, Translations, protected embed, upload/translation creation, `/me`, `/login`, and `/accessToken`. Consequently, the official contract specifies none of the following:

- how a history record is identified or related to Series/Episode/Translation;
- how progress, duration, completion, rewind, or “mark watched” is represented;
- mutation method, idempotency key, conflict/version semantics, timestamps, batching, offline replay, or deletion;
- history pagination, ordering, retention, or multi-device merge behavior.

The only documented catalogue mutation is `POST /translations/create`, which uploads a contributor translation and is outside this subscriber viewer's intended v1 behavior. Token issuance uses `GET`, and there is no identity or Subscription mutation in the API. This absence is established by the complete [official OpenAPI path set](https://smotret-anime.org/api/openapi.yaml?v=1786984811), not by assuming undocumented site behavior does not exist.

**Planning consequence:** the previously desired “Anime365 Watch History is canonical” rule is unsupported by the official API. Before implementation, either (a) Anime365 must provide and approve an additional documented contract, or (b) v1 must explicitly choose local-only history/progress and stop promising Anime365 account synchronization.

## Cache metadata, rate limits, and error behavior

The OpenAPI contract defines no `ETag`, `Last-Modified`, `Cache-Control`, expiry, conditional request, image-cache directive, or resource revision for catalogue responses. Poster fields are URL strings, not cache contracts. Translation has updated/added timestamp strings, but the schema does not define them as validators. Cache duration, revalidation, invalidation, and stale/offline behavior must therefore be app policy and must not be presented as server guarantees.

The contract also defines no request quota, rate-limit headers, concurrency limit, `429` response, or `Retry-After` behavior. Its only traffic guidance is to identify the program in `User-Agent` and to prefer `afterId` over large offsets. A client should impose conservative concurrency and backoff locally, but no numerical rate is authoritative. See the [official API introduction and response declarations](https://smotret-anime.org/api/openapi.yaml?v=1786984811).

Declared endpoint errors are narrow:

- missing Series, Episode, Video, or Translation detail: `404`;
- login: `403` for unknown app or invalid credentials;
- browser-session token issue: `403` for no login or unknown app;
- protected embed: `403` for no login or no active Subscription, and `404` for missing Translation;
- the common error schema carries application `code`, `message`, and optional field errors.

No `400` for malformed catalogue filters, `401`, `409`, `422`, `429`, or `5xx` schema is declared for these reader operations. Network and decoding failures remain client concerns.

### Published status codes versus live behavior

There is a material discrepancy to guard against. On 2026-08-20, a live request for a [missing Series](https://smotret-anime.org/api/series/0) returned HTTP `200` with `{ "error": { "code": 404, ... } }`, and an [unauthenticated protected embed](https://smotret-anime.org/api/translations/embed/0) returned HTTP `200` with embedded error code `403`. The OpenAPI operations declare HTTP `404` and `403` respectively. These are first-party observations, not a promise that HTTP will always be `200`.

A robust client must inspect the `data` versus `error` envelope even on HTTP success, while still handling the documented non-2xx statuses. It should not rely exclusively on `URLSession` HTTP status classification.

## Decisions this research enables

1. **Identity cannot be specified as OAuth.** The official choices are credential-in-query token issue or token issue from an already authenticated website session. A production Mac App Store design needs an explicit security/product decision and, preferably, confirmation from Anime365 about an approved native sign-in flow.
2. **There is no token-refresh subsystem to build.** Store the long-lived token as a Keychain secret, validate coarse account/Subscription state through `/me`, handle an embed `403`, and reacquire authentication when needed. Do not log complete request URLs.
3. **Subscription is a coarse capability.** `isPremium`/`premiumUntil` and protected-access success are the only official signals; billing/account administration remains a website handoff.
4. **Catalogue adapters should be narrow and tolerant.** Decode the documented projection, ignore unknown fields, allow missing fields, parse date strings defensively, and keep endpoint DTOs separate from shared app domain models.
5. **Search is server-backed but minimally specified.** Use `/series?query=...`; treat chips as an optional opaque feature until Anime365 publishes the grammar needed by the desired UI.
6. **Watch History synchronization is blocked by contract, not implementation effort.** Local history can be designed now, but server-canonical history cannot be promised without a new official source.
7. **Caching and request budgets are client policy.** They need measurable app defaults plus a kill-switch/configuration path because the server publishes neither validators nor rate limits.

## Requested behavior not specified by the official contract

- native authorization redirect/callback, OAuth/PKCE, MFA/challenge behavior, captcha, social-login handoff, or App Store–appropriate sign-in guidance;
- token refresh, explicit revocation/logout, scopes, expiry, rotation, device sessions, or compromised-token recovery other than password change;
- precise invalid-token behavior on `/me`, or a machine-readable distinction between no login and no Subscription;
- Subscription products, renewal/grace/billing state, eligibility eventing, or purchase management;
- complete advanced-filter grammar and search ranking/locale semantics;
- shapes of Episodes nested in Series detail and Translations nested in Episode detail;
- Watch History and every related read/write/merge contract;
- catalogue cache validators/TTL and authoritative rate limits;
- schema evolution policy, deprecation/version negotiation beyond the document's static API version `1.0`, and service-domain failover policy.

These gaps must remain explicit decisions or vendor questions; they must not be filled from community clients or accidental web behavior.
