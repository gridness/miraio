# Official Anime365 playback delivery contract

Research date: 2026-08-20

## Question

Using only Anime365's official API documentation and first-party API schema, what published contract turns an Episode and a Translation into authorized playback, and which details needed by a native macOS player remain unspecified?

## Sources and method

The authority for this note is Anime365's current, first-party [API documentation](https://smotret-anime.org/api-docs), which loads the service's [OpenAPI 3.0.3 document, API version 1.0](https://smotret-anime.org/api/openapi.yaml?v=1786984811). The schema was retrieved from the official domain on 2026-08-20. Public first-party API calls were used only to check the documented example resources and unauthenticated error path; no credential, cookie, token, or returned media URL was requested or recorded. No community wrapper, reverse-engineered web-player implementation, or undocumented response shape was used as a contract.

The OpenAPI document uses `https://smotret-anime.app/api` as its example server and explicitly permits relative `/api` requests against the domain serving the documentation. The `.org` documentation host was reachable during this research; the example `.app` host was not reachable from the research environment. That observation is not evidence of a product guarantee or outage and does not change the published contract. ([OpenAPI `info` and `servers`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

## Finding

The published native-facing contract stops at a subscriber-authorized, translation-scoped **playback-information lookup**. It does not publish a sufficiently typed media-delivery contract for a native player.

The documented flow is:

1. Start from an Episode ID. The description of `GET /api/episodes/{id}` says that it returns the episode and its translations, although the `Episode` schema does not declare the translations property. The explicitly typed alternative is `GET /api/translations?episodeId={episodeId}`, which returns `Translation` records filtered by Episode ID. ([OpenAPI `/episodes/{id}`, `/translations`, and schemas `Episode`/`Translation`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))
2. Choose a Translation. Anime365 defines one Translation as one dub or subtitle translation for one episode. Its typed metadata includes `id`, `episodeId`, `seriesId`, `type`, `typeKind`, `typeLang`, `qualityType`, `duration`, `width`, `height`, and `embedUrl`; the schema does not enumerate translation types or quality values. ([OpenAPI `/translations` and schema `Translation`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))
3. Request `GET /api/translations/embed/{translationId}?access_token=...`. The token must belong to an account with an active subscription. The operation documents `403` for unauthenticated/non-subscriber access and `404` for a missing Translation. ([OpenAPI `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))
4. Interpret the returned playback information. The prose says the response contains video and subtitle links and names an ASS soft-subtitle field, `subtitlesUrl`. However, the success response is only `GenericObjectResponse`: an untyped `data` object with arbitrary properties. No video URL field, rendition object, or other playback property is declared. ([OpenAPI `/translations/embed/{id}` and schema `GenericObjectResponse`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

Anime365 also documents a hosted HTML5 player page at `/translations/embed/{translationId}?access_token=...` (without `/api`). That is a web-player entry point, not a typed native media contract. ([OpenAPI `/translations/embed/{id}` description](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

## What the official contract does and does not specify

| Concern | Published contract | Status for native playback |
| --- | --- | --- |
| API authorization | `access_token` is an API key carried in the query string. The API asks clients to identify the site or application in `User-Agent`. ([OpenAPI authorization and `securitySchemes.accessToken`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Specified for the API request only. |
| API-token expiry | Anime365 states that an access token has no time limit and remains valid until the user's password changes. ([OpenAPI authorization](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Specified; this says nothing about media-URL expiry. |
| Subscription gate | Playback information requires a token for an account with an active subscription; unauthenticated or non-subscriber access is `403`. ([OpenAPI `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Specified. |
| Stream URL acquisition | The translation-scoped embed operation says it returns video and subtitle links, but its `data` payload has no declared video-link field or structure. ([OpenAPI `/translations/embed/{id}` and `GenericObjectResponse`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Endpoint specified; usable response contract unspecified. |
| Media-URL expiry and renewal | No TTL, expiry marker, revocation rule, refresh operation, retry rule, or `401`/`403` recovery behavior is documented for returned media URLs. The operation declares only `200`, `403`, and `404`. ([OpenAPI `/translations/embed/{id}` responses](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Unspecified. Do not equate token lifetime with stream lifetime. |
| Media headers and cookies | Apart from the API request's query token and requested `User-Agent`, the schema defines no `Referer`, `Origin`, `Authorization`, cookie, or other header requirement for fetching media or subtitles. ([OpenAPI authorization and `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Unspecified. A native client cannot assume that API credentials should be forwarded to a media origin. |
| Redirects and CDN hosts | No redirect responses, redirect policy, host allow-list, CDN host stability, TLS requirements, or cross-host credential policy is published. ([OpenAPI `/translations/embed/{id}` responses](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Unspecified. |
| Alternative channels | No playback-channel identifier, channel-list operation, selection parameter, fallback ordering, or health signal appears in the published API schema. `GET /api/upload/endpoints` does define country-dependent labelled upload channels, recommended upload destinations, and fallback tus URLs, but its contract explicitly concerns contributor uploads and does not connect those channels to playback. ([OpenAPI `/upload/endpoints` and `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Playback channels are unspecified; upload-channel semantics must not be reused for playback. |
| Quality selection | `Translation` exposes an opaque string `qualityType` plus `width` and `height`, and `/translations` accepts a `qualityType` filter. The schema gives no quality enum and no playback-rendition list or selection protocol. ([OpenAPI `/translations` and schema `Translation`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Translation metadata is specified; playable variants and automatic/manual quality selection are not. |
| `Video.urlList` | The separate `Video` schema has `urlList: string[]`, and `GET /api/videos/{id}` exists. The schema does not publish a Video ID on Episode or Translation, define `urlList` semantics, or connect that endpoint to the authorized embed flow. ([OpenAPI `/videos/{id}` and schemas `Video`, `Episode`, and `Translation`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Not a documented route from a chosen Translation to playback; it must not be treated as a rendition/channel contract. |
| Containers, manifests, and codecs | The playback response has no declared MIME type, container, manifest type, video codec, profile/level, frame-rate, HDR, audio codec, or byte-range capability. ([OpenAPI `/translations/embed/{id}` and `GenericObjectResponse`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Unspecified. |
| Audio resources | Translation metadata distinguishes dub/sub/raw using string fields, but the playback schema declares no separate audio resources, languages, tracks, defaults, or switching semantics. ([OpenAPI schema `Translation` and `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Translation kind is specified; media audio tracks are not. |
| Subtitles | Anime365 says most subtitles are soft subtitles and directs clients to attach ASS subtitles from `subtitlesUrl`. ([OpenAPI `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | ASS and the field name are specified in prose. URL lifetime, fetch headers, encoding, MIME type, fonts/attachments, and ASS feature level are unspecified. |
| SRT and WebVTT | No SRT, WebVTT, alternate-subtitle array, conversion service, or content-negotiation behavior appears in the operation or schema. ([OpenAPI `/translations/embed/{id}` and `GenericObjectResponse`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Unspecified; native-compatible SRT/WebVTT cannot be assumed. |
| Playback progress and watch history | The published path set contains series, episodes, videos, translations/embed, upload/create, account, and login/token operations. It contains no progress, position, watched-state, or watch-history operation or schema. ([OpenAPI `paths`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | No official API contract is published. |

## Development resources and fixtures

Anime365 publishes two useful read-only example resources, but does not designate either as a stable test fixture:

- Series `19730` appears in the successful-response example in the OpenAPI introduction. On the research date, the public [`GET /api/series/19730`](https://smotret-anime.org/api/series/19730?fields=id%2Ctitles%2CtypeTitle%2CisActive) operation returned an active Series in the documented `data` envelope.
- Translation `2423373` appears in the OpenAPI authorization and hosted-player examples. On the research date, public [`GET /api/translations/2423373`](https://smotret-anime.org/api/translations/2423373) returned active translation metadata, while [`GET /api/translations/embed/2423373`](https://smotret-anime.org/api/translations/embed/2423373) without an Access Token returned the documented authorization error. The [official schema](https://smotret-anime.org/api/openapi.yaml?v=1786984811) requires an Access Token from an account with an active Subscription for a successful embed lookup.

These resources can exercise public response decoding and the protected endpoint's negative path. The official documentation publishes no fixed success fixture, sample Subscriber, sample Access Token, stable test Translation, non-expiring media URL, sandbox host, or permission to bypass the Subscription gate. It also gives no stability guarantee for the two example IDs. A successful integration test must therefore use a real registered API client and eligible Subscriber, keep the Access Token outside source and logs, and avoid snapshotting any returned signed or credential-bearing URL. This is an application testing constraint inferred from the published authorization boundary; it is not evidence that Anime365 lacks private fixtures.

## Planning consequence

The native app may safely design around Episode and Translation discovery followed by an **opaque playback-information lookup**, but it cannot yet commit to direct `AVPlayerItem` construction, channel failover, rendition selection, subtitle conversion, or server watch-history synchronization from the official API contract alone.

Before implementation planning treats native playback as feasible, Anime365 must publish or directly confirm at least:

- the successful embed response schema and which URL is the primary playable resource;
- media/subtitle URL lifetime, renewal, headers/cookies, redirect and allowed-host rules;
- channel and quality/rendition identifiers and fallback behavior;
- supported containers, manifests, video/audio codecs, and subtitle formats/encodings;
- progress/history read and write endpoints plus update and conflict semantics.

Until then, the hosted HTML5 player page is the only end-to-end playback entry point that Anime365's API documentation explicitly identifies. Using its internal behavior, scraping undocumented fields, or relying on a community wrapper would create an unapproved and unstable contract rather than resolve this gap.
