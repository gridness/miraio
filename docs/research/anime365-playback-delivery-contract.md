# Official Anime365 playback delivery contract

Research date: 2026-08-22

## Question

What published contract turns an Anime365 Episode and Translation into authorized playback, which details needed by a native macOS player remain unspecified, and what do the working `a365dt` and Ichime clients demonstrate about a practical alternative?

## Sources and method

The authority for this note is Anime365's current, first-party [API documentation](https://smotret-anime.org/api-docs), which loads the service's [OpenAPI 3.0.3 document, API version 1.0](https://smotret-anime.org/api/openapi.yaml?v=1786984811). The exact OpenAPI artifact retrieved from the official domain on 2026-08-22 has SHA-256 `1b9533e38166bab72024fe4341c1dc22fe7a9795794753346e302b6c34c6a1e1`. That hash identifies this research snapshot; Anime365 does not describe either the URL's `v` query value or the OpenAPI `info.version` value as a playback-contract revision or publish an evolution policy.

The first-party [help page](https://smotret-anime.org/help) and [API-client registration page](https://smotret-anime.org/api-clients) were also checked for legitimate public access and support routes. Public first-party API calls were used only to check the documented example resources and unauthenticated error path; no credential, cookie, token, successful protected payload, or returned media URL was requested or recorded.

Two working open-source clients were then inspected as implementation evidence, not elevated to provider authority:

- Gridness [`a365dt` at `3a7842bb338ea1e7e0351daf8d085377a0e8a6ae`](https://github.com/gridness/a365dt/tree/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae), committed 2026-08-17.
- midori-no-me [`ichime` at `4a5b36527710965b00e0641e2f1bf7377536d73e`](https://github.com/midori-no-me/ichime/tree/4a5b36527710965b00e0641e2f1bf7377536d73e), committed 2026-08-19 with the subject “fix: breaking changes in Anime 365 API.”

Their source was compared field-by-field with the hashed official OpenAPI artifact. This comparison does not claim that either client's locally declared types are part of Anime365's contract, and it did not inspect hosted-player traffic or protected payloads.

The OpenAPI document uses `https://smotret-anime.app/api` as its example server and explicitly permits relative `/api` requests against the domain serving the documentation. The `.org` documentation host was reachable during this research; the example `.app` host was not reachable from the research environment. That observation is not evidence of a product guarantee or outage and does not change the published contract. ([OpenAPI `info` and `servers`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

## Finding

The published native-facing contract stops at a subscriber-authorized, translation-scoped **playback-information lookup**. It does not publish a sufficiently typed media-delivery contract for issue #39 as currently written. The two clients nevertheless demonstrate a viable, narrower engineering choice: call that official endpoint and maintain an application-owned compatibility decoder for fields that Anime365 permits in its open object but does not type.

That distinction matters. This approach is not hosted-player scraping: the request itself is documented. It is still an empirical dependency on undeclared response properties, so it cannot satisfy an acceptance criterion that specifically requires an “official typed success schema” and says the published untyped object is insufficient. Miraio can either keep that authority gate or deliberately amend it; lack of an Anime365 developer reply does not make native playback technically impossible.

The documented flow is:

1. Start from an Episode ID. The description of `GET /api/episodes/{id}` says that it returns the episode and its translations, although the `Episode` schema does not declare the translations property. The explicitly typed alternative is `GET /api/translations?episodeId={episodeId}`, which returns `Translation` records filtered by Episode ID. ([OpenAPI `/episodes/{id}`, `/translations`, and schemas `Episode`/`Translation`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))
2. Choose a Translation. Anime365 defines one Translation as one dub or subtitle translation for one episode. Its typed metadata includes `id`, `episodeId`, `seriesId`, `type`, `typeKind`, `typeLang`, `qualityType`, `duration`, `width`, `height`, and `embedUrl`; the schema does not enumerate translation types or quality values. ([OpenAPI `/translations` and schema `Translation`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))
3. Request `GET /api/translations/embed/{translationId}?access_token=...`. The token must belong to an account with an active subscription. The operation documents `403` for unauthenticated/non-subscriber access and `404` for a missing Translation. ([OpenAPI `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))
4. Interpret the returned playback information. The prose says the response contains video and subtitle links and names an ASS soft-subtitle field, `subtitlesUrl`. However, the success response is only `GenericObjectResponse`: an untyped `data` object with arbitrary properties. No video URL field, rendition object, or other playback property is declared. ([OpenAPI `/translations/embed/{id}` and schema `GenericObjectResponse`](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

Anime365 also documents a hosted HTML5 player page at `/translations/embed/{translationId}?access_token=...` (without `/api`). That is a web-player entry point, not a typed native media contract. ([OpenAPI `/translations/embed/{id}` description](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

## What the two working clients actually rely on

### `a365dt`

`a365dt` follows the public API authorization path closely. It fixes the API base to `https://anime365.ru/api`, obtains a per-user Access Token through its registered public `app` identifier, accepts an environment token or stores it in the macOS Keychain, identifies itself with `User-Agent: a365dt/<version>`, and sends the token as the `access_token` query parameter on `GET /api/translations/embed/{translationId}`. ([API base and client](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L11-L23), [token acquisition](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/auth.rs#L16-L75), [client and embed request](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L86-L104), [embed operation](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L189-L197), [query-token injection](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L251-L294))

It locally decodes the untyped `data` object as:

```text
download: [{ height: UInt16, url: String? }]   // array defaults to empty
subtitlesUrl: String?
```

Those are application-authored Serde types, not generated OpenAPI types. `subtitlesUrl` is named in the official operation's prose, but its type is not declared. `download`, `download[].height`, and `download[].url` are neither declared nor described in the current official artifact; they are merely permitted by `additionalProperties: true`. ([`Embed` and `MediaOption`](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L60-L72), [official operation and open response](https://smotret-anime.org/api/openapi.yaml?v=1786984811))

For each Episode, `a365dt` treats each non-null `download` URL's integer `height` as a fixed resolution, sorts and deduplicates heights, asks the user for a preferred height, and explicitly asks for a fallback height when that height is missing. It models one URL per height and no named Source or equivalent-channel set. ([resolution selection](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/select.rs#L191-L274), [height extraction](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/select.rs#L350-L360))

It then downloads the selected URL as a progressive file: `HEAD`, then `GET`, with `Range`/`If-Range` resume when strong `ETag` or `Last-Modified` state is available. On a retry it reacquires the embed object and substitutes a refreshed URL for the same height. This is useful evidence that returned URLs can be treated as short-lived capabilities, but it does not reveal a documented TTL or renewal rule. ([asset requests and conditional token forwarding](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L199-L235), [transfer behavior](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/download/acquisition.rs#L116-L220), [same-height reacquisition](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/download/acquisition/episode.rs#L71-L124))

The asset client is HTTPS-only and sends no `Referer`, `Origin`, bearer header, or cookie. It appends the Access Token only when the returned asset URL is on one of four exact Anime365 hosts; other origins receive no API token. It configures no explicit redirect policy or redirect-time host validation, relying on the HTTP library's defaults. `subtitlesUrl`, when present, goes through the same asset transfer and is treated as a separate ASS file; its absence is presented as subtitles being contained in the MP4. ([client and host policy](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L86-L104), [URL normalization and host list](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/api.rs#L310-L346), [video/subtitle acquisition](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/download/acquisition/episode.rs#L12-L68), [embedded-subtitle notice](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/crates/a365dt-cli/src/main.rs#L564-L575))

This proves a download workflow against the empirical shape. It does not prove that the same URL is an AVPlayer-supported resource, that the bytes are always MP4 despite the chosen output extension, or that AVFoundation's range, redirect, codec, subtitle, hardware-decode, and energy behavior meets Miraio's native gates.

### Ichime

Ichime defaults its service base to `https://smotret-anime.org` and calls the same official `GET /api/translations/embed/{translationId}` path, but passes no query parameters. Its shared default `URLSession` has a cookie store and application `User-Agent`; the app signs in by posting the website's `/users/login` HTML form and then reuses the resulting session cookies in the API client. That is not the OpenAPI's documented `GET /api/login?app=...` plus `access_token` query flow. Successful cookie authorization is therefore another empirical behavior, and Miraio should not copy it when the documented token flow is available. ([default base and session configuration](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Modules/IchimeCore/Sources/AppEnvironment.swift#L6-L55), [embed request](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Packages/Anime365Kit/Sources/Anime365Kit/API/Request/GetTranslationEmbed.swift#L3-L11), [API request construction](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Packages/Anime365Kit/Sources/Anime365Kit/API/ApiClient.swift#L33-L100), [website login](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Packages/Anime365Kit/Sources/Anime365Kit/Web/Request/Login.swift#L8-L35), [cookie-backed authentication](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Modules/IchimeProfile/Sources/AuthenticationManager.swift#L68-L112))

Ichime locally requires a different playback shape:

```text
stream: [{ height: Int, urls: [URL] }]
subtitlesUrl: String?
subtitlesVttUrl: URL?
```

`stream`, `stream[].height`, `stream[].urls`, and `subtitlesVttUrl` are all undeclared and unmentioned in the current official schema. Ichime requires the `stream` array and valid URL decoding, drops zero heights and empty URL arrays, and uses only `urls.first`; it discards any remaining URLs without assigning Source or fallback meaning. It resolves `subtitlesUrl` relative to the Anime365 base URL and falls back to `subtitlesVttUrl`. ([local embed type](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Packages/Anime365Kit/Sources/Anime365Kit/API/Type/TranslationEmbed.swift#L3-L16), [normalization and first-URL choice](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Modules/IchimeEpisode/Sources/Type/EpisodeTranslationStreamingInfo.swift#L21-L81))

Ichime's own adapter history reinforces the compatibility risk: commit [`2c38e56e43a4d04ff045880c9f045f5da580c6fb`](https://github.com/midori-no-me/ichime/commit/2c38e56e43a4d04ff045880c9f045f5da580c6fb) removed its former required `embedUrl` and `download` properties while retaining `stream`, and changed URL strings to typed URLs. That is evidence of client-model evolution, not evidence that Anime365 versioned or deprecated either shape.

Ichime does not itself fetch or natively play this media. It puts the first media URL, and for Infuse an optional subtitle URL, into an Infuse or VLC deep link. Its README explicitly states that Episodes open in external players. Media headers, cookies, redirects, container/codec support, and playback recovery therefore belong to those external applications rather than Ichime. When a subtitle URL has no extension, or when the user requests it, Ichime substitutes its own Cloudflare Worker subtitle proxy, which is not an Anime365 API contract. ([external-player behavior](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/README.md#L9-L18), [deep-link construction](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Packages/ThirdPartyVideoPlayer/Sources/ThirdPartyVideoPlayer/DeepLinkFactory.swift#L27-L117), [subtitle proxy decision](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Ichime/Sources/Episode/View/EpisodeQualitySelectorListView.swift#L177-L280), [proxy URL](https://github.com/midori-no-me/ichime/blob/4a5b36527710965b00e0641e2f1bf7377536d73e/Modules/IchimeVideoPlayer/Sources/SubtitlesProxyUrlGenerator.swift#L18-L35))

### Contract comparison

| Property or behavior | `a365dt` | Ichime | Current official status |
| --- | --- | --- | --- |
| Playback operation | `GET /api/translations/embed/{id}` | Same | Documented. |
| API authorization | Query `access_token`; active Subscription expected | Website session cookies; no token query | Only the query token is documented. |
| Video collection | `download[]` | `stream[]` | Neither property is declared or named. |
| Quality key | Required integer `height` | Required integer `height` | No embed response property is declared. Translation metadata has a separate `height`, but the schema does not relate it to embed items. |
| Media location | Optional singular `url` | Required `urls[]`, first only | Neither shape is declared or named. |
| ASS subtitle | Optional `subtitlesUrl` | Same, resolved relative to API base | Field name and ASS intent are stated in prose; type, resolution base, and fetch rules are not declared. |
| VTT subtitle | Ignored | Optional `subtitlesVttUrl` fallback | Undeclared and unmentioned. |
| Source/failover | None; one URL per height | Extra URLs discarded | No official Source identifier or equivalence semantics. |
| URL renewal | Re-call embed after transfer failure, retain same height | None in app; external player owns playback | TTL and renewal are undocumented. |
| Media request requirements | HTTPS; no special header/cookie; token only for exact official hosts | Handed to external player with no app-provided media headers/cookies | Undocumented. |
| Redirects | HTTP-library default; no app-defined host validation | API uses URLSession default; media redirect behavior is external-player-owned | Undocumented. |

## Can issue #39 be completed through public routes?

**As written, no. As an amended empirical-compatibility gate, yes.** Anime365 provides legitimate self-service access to the documented endpoint, and `a365dt` shows that the documented Access Token flow is enough to consume its successful response without private developer credentials. What self-service access cannot provide is the authority-issued type and exhaustive provider semantics that issue #39 currently requires.

| Public first-party route | What it legitimately provides | Why it does not complete the gate |
| --- | --- | --- |
| [API documentation](https://smotret-anime.org/api-docs) and its [OpenAPI artifact](https://smotret-anime.org/api/openapi.yaml?v=1786984811) | The official endpoint, token and Subscription gate, error cases, prose reference to `subtitlesUrl`, and an exact artifact that can be hashed. | The successful `data` object is declared only as open-ended; there is no typed example, playback schema, fixture catalogue, sandbox, changelog, or schema-revision semantics. |
| [API-client page](https://smotret-anime.org/api-clients) | After ordinary site sign-in, a user can create an API client. The page defines the client as the `app` identifier used to obtain an Access Token; the OpenAPI document says `app` is public and only the per-user token is secret. | Client registration grants access to the published API. It does not grant a private schema, special fixture entitlement, or a way to designate stable representative resources. |
| A user's own active Subscription and the documented `/login` or `/accessToken` flow | A registered client and eligible account can legitimately call the protected embed operation. This is sufficient to build and qualify an application-owned compatibility decoder without privileged developer credentials. ([OpenAPI authorization and `/translations/embed/{id}`](https://smotret-anime.org/api/openapi.yaml?v=1786984811)) | Observed keys are runtime compatibility evidence, not an authority-issued type or semantic guarantee. A chosen sample cannot prove that it covers every Source, Quality, media, subtitle, redirect, header, cookie, expiry, and renewal behavior. |
| The API entry on the [official help page](https://smotret-anime.org/help) | Anime365 links the API docs and client page and directs remaining API questions to `info@smotret-anime.ru`. This is the published first-party escalation route relevant to the contract gap. | The reviewed first-party pages publish no response-time commitment, public developer forum, issue tracker, schema-request workflow, or alternative API-specific contact. Sending a request does not itself supply the missing contract. |

A successful response obtained with the user's own account may confirm that access works and can responsibly inform a tolerant application decoder. It is not scraping the hosted player, but it is still deriving types from properties that the provider left open-ended. That distinction is acceptable only if issue #39 is amended to allow empirical decoding. Likewise, the public example IDs prove only that ordinary metadata and the protected negative path are currently reachable; Anime365 does not label them stable fixtures or say which playback behaviours they represent.

Consequently, issue #39 can be completed unchanged only if Anime365 publishes the missing schema and representative-resource taxonomy or confirms them through a verifiably first-party channel. The project does not, however, need to remain technically blocked: it can replace that authority gate with a narrower, explicitly empirical compatibility gate and accept the maintenance and product-scope consequences below.

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

## Concrete alternatives for Miraio

### 1. Replace GATE-01 with a compatibility gate (recommended if native V1 is still the goal)

Miraio can use the documented Access Token request and an application-owned, tolerant decoder whose initial real-time profile recognizes the Ichime-assumed shape without claiming provider semantics:

```text
stream[].height + stream[].urls[]
subtitlesUrl
subtitlesVttUrl
```

The adapter should accept unknown properties, reject malformed or non-HTTPS locations, never log or persist the protected response, never forward the Access Token to returned media origins, and fail closed when it cannot construct a supported path. Start with one path: the first valid URL at one positive observed height plus either embedded dialogue or a validated `subtitlesUrl` ASS asset. Reacquire the embed object once on a qualifying failure, as `a365dt` does. Do not call extra `urls[]` entries equivalent Sources, and do not advertise `subtitlesVttUrl`, alternative origins, adaptive HLS, or lower-height fallback until each has passed the relevant AVPlayer, subtitle, privacy, and energy matrix. Treat `download[]` as a known but unsupported shape in V1; adding it later requires its own compatibility qualification rather than silent fallback.

This requires an explicit issue/specification amendment rather than pretending the existing gate passed:

| Current issue #39 requirement | Necessary amendment |
| --- | --- |
| “Official typed success schema” | Accept a versioned Miraio compatibility schema over the official open-ended response. Identify it by adapter version, official OpenAPI SHA-256, observation time, and a redacted keys-and-types fingerprint; do not call that fingerprint an Anime365 contract revision. |
| Complete official Source and Quality semantics | Limit V1 to an app-defined **Playback Candidate** and integer **vertical resolution**. Advertise no Source choice and no provider-defined Quality enum until Anime365 publishes those meanings. |
| Resources cover every distinct official behavior and every advertised path | Require tester-owned authorized resources to cover every **Miraio-advertised compatibility path**. Unknown provider behaviors remain unsupported rather than presumed covered. |
| Fixture Manifest records provider contract revision and aliases | Record the OpenAPI artifact hash, compatibility-adapter revision, test alias, categorical shape/transport/subtitle coverage, candidate artifact hash, and timing. Continue excluding credentials, provider bodies, identifiers, URLs, and protected bytes. |
| The untyped embed object and reverse engineering cannot complete the gate | Permit direct authorized observation and decoding of the documented API response. Continue prohibiting hosted-player inspection, scraping, credential publication, access-control bypass, and inference from CDN hostnames. |

The same wording must be propagated to the parent specification and dependent issues: replace “contract-verified” with “compatibility-qualified” in issues #32, #40, and #44; replace “every officially supported alternative” with “every advertised compatibility path”; and remove equivalent-Source recovery until Source equivalence is actually known. PLAY-04, PLAY-09, and PRIV-05 can then execute against a tester-owned protected account as empirical product qualification, not proof of provider guarantees.

This path adds maintenance risk: Anime365 may change an undeclared property without a contract-version signal. Mitigate it with synthetic decoder tests for the primary shape and known unsupported shapes, a live protected smoke test that retains only redacted shape evidence, explicit unsupported-shape UI, and review whenever the official artifact hash or live keys-and-types fingerprint changes.

### 2. Reuse `a365dt` selectively

`a365dt` is the strongest complementary reference for documented query-token use and reacquisition because it already combines the documented flow, a program `User-Agent`, an empirical embed decoder, least-authority token forwarding, resolution selection, resumable asset checks, and same-height reacquisition. Its source is [Apache-2.0 licensed](https://github.com/gridness/a365dt/blob/3a7842bb338ea1e7e0351daf8d085377a0e8a6ae/LICENSE).

Porting its small DTO and acquisition-policy ideas into Swift is lower-risk than embedding the Rust CLI. Do not vendor its download pipeline wholesale: it writes offline MP4/ASS files, while Miraio's scope requires ephemeral AVPlayer playback and prohibits offline media downloads. `a365dt` also does not validate AVPlayer compatibility, redirects against Miraio's network policy, codecs, hardware decode, ASS presentation, or energy. This option is therefore an implementation strategy under alternative 1, not a way to retain issue #39 unchanged.

### 3. Adopt an Ichime-style external-player path

Ichime shows that a thin client can present `stream[].height` choices and hand `urls.first` to Infuse or VLC. That can produce working playback without Miraio owning media transport, but it is not the requested native AVKit experience and does not prove header, cookie, redirect, subtitle, recovery, privacy, accessibility, or energy behavior inside Miraio. Copying Ichime's website-cookie login or third-party subtitle proxy would also conflict with Miraio's documented-token and no-third-party-protected-data decisions.

Choosing this route would require removing native playback, AVKit-control, supplemental-ASS, hardware-decode, energy, and in-app recovery acceptance from V1, allowing an external-player handoff as the successful path, and separately deciding whether protected URLs may be placed in another application's deep link. It is a larger product reduction than alternative 1.

### 4. Ship only the documented hosted-page handoff

The hosted HTML5 page remains the only end-to-end player that Anime365 explicitly documents. It can be offered as a fallback, but the documented URL includes `access_token`; Miraio's current security decision forbids leaking that token through a browser handoff. Opening the page without a token and relying on an existing browser login is safer but is not documented as a guaranteed flow. Making this the V1 playback path would require removing native-playback acceptance and defining a safe, testable authorization handoff; it cannot close current GATE-01.

### 5. Keep the strict authority gate

If provider-guaranteed Source, Quality, expiry, redirect, header, cookie, media, subtitle, and fixture semantics are non-negotiable, issue #39 should remain blocked pending a schema update or authoritative reply. Continue hashing the official artifact, and send one bounded request if the support route becomes usable. This is the lowest compatibility risk and the only option that preserves every current acceptance sentence, but it leaves native V1 externally blocked.

## Recommendation

The repositories support revising the earlier all-or-nothing conclusion. A native prototype is feasible without Anime365 developer contact: use the official Access Token flow, adopt Ichime's `stream[].urls` model as the initial real-time compatibility profile, use `a365dt` as the reference for bounded reacquisition, and qualify only one narrowly advertised AVPlayer path with a tester-owned Subscription. Recognize other shapes as unsupported instead of silently treating them as equivalent. Do not borrow Ichime's cookie authentication or subtitle proxy, and do not interpret multiple URLs as official Sources.

That work should begin only after issue #39 and its dependent specification language are changed from an **authority contract gate** to an **empirical compatibility gate**. Without that amendment, the clients are evidence that software can work, not evidence that the current acceptance criteria have been met.
