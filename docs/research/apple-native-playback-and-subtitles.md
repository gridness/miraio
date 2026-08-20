# Native Apple playback and subtitle capabilities

Research for [Document native Apple playback and subtitle capabilities](https://github.com/gridness/miraio/issues/5), 2026-08-20.

## Scope and evidence

This note answers what the public Apple media stack can support for a macOS 26+ app while preserving a viable iOS 26+ service/player core. It uses only Apple-owned sources: current Apple Developer documentation, the HLS authoring specification and Apple session material, plus the public interface declarations in Xcode 26.6's macOS 26.5 and iOS 26.5 SDKs.

Statements below are marked as one of:

- **Documented** — promised by a public Apple API or specification.
- **Inference** — an architectural consequence of those public interfaces, but not itself promised by Apple.
- **Empirical gate** — behavior that must be exercised with representative Anime365 assets before it becomes a product assumption.

## Answer in brief

Use `AVPlayer` for transport and decoding, hosted by `AVPlayerView` on macOS and by `AVPlayerViewController` on a future iOS interface. This is the public Apple path to native controls, seeking, rate selection, full-screen presentation, Picture in Picture, system Now Playing integration, and native media selection. Do not rebuild the player UI around `AVPlayerLayer` merely to add subtitles: Apple explicitly positions AVKit's player views as the full-featured presentation path and `AVPlayerLayer` as the custom-controls path ([AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer)).

Native subtitles are a strong fit only when they arrive as a legible media option that AVFoundation understands. Apple explicitly supports HLS WebVTT and text-profile IMSC1 and renders selected legible options inside `AVPlayerView`, `AVPlayerViewController`, and `AVPlayerLayer` ([HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/), [selecting subtitles and alternative audio tracks](https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks)). Apple documents no playback API that attaches an arbitrary external `.srt`, `.vtt`, or `.ass` file to an existing `AVPlayerItem`. SRT is documented as an input to Apple's *authoring* tool that converts it to segmented WebVTT, not as a sidecar playback format ([Using Apple's HLS tools](https://developer.apple.com/documentation/http-live-streaming/using-apple-s-http-live-streaming-hls-tools)). ASS is absent from Apple's public playback, caption, and HLS surfaces.

Consequently, Miraio can remain a native AVKit player and add a supplemental overlay only when the service supplies an external SRT/WebVTT/ASS sidecar. `AVCaptionRenderer` is a cross-platform Apple renderer for a programmatically supplied collection of `AVCaption` values, available well before the deployment targets (macOS 12+, iOS 18+), but the app must parse the source itself and its caption model cannot express full ASS semantics ([AVCaptionRenderer](https://developer.apple.com/documentation/avfoundation/avcaptionrenderer), [caption authoring](https://developer.apple.com/documentation/avfoundation/caption-authoring)). An ASS-specific renderer is required for the agreed fidelity target of dialogue, timing, positioning, styles, and signs; advanced effects may then degrade deliberately.

There is also a hard network-integration gate. Public `AVURLAsset` initialization options support applicable HTTP cookies and a custom User-Agent, but not arbitrary request headers ([initialization options](https://developer.apple.com/documentation/avfoundation/avurlasset-initialization-options), [`AVURLAssetHTTPCookiesKey`](https://developer.apple.com/documentation/avfoundation/avurlassethttpcookieskey), [`AVURLAssetHTTPUserAgentKey`](https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey)). Prefer service-issued signed URLs or domain-correct cookies. If every playlist, segment, or progressive byte-range request requires a bearer token or `Referer`, the native player needs a public `AVAssetResourceLoader`/custom-scheme adapter or another authorization bridge; that path must be prototyped for redirects, ranges, HLS child resources, expiry, stalls, and energy before it is accepted.

## Capability map at macOS 26 and iOS 26

| Need | macOS 26+ | iOS 26+ | Boundary |
| --- | --- | --- | --- |
| Native player UI | `AVPlayerView` (AppKit, macOS 10.9+) | `AVPlayerViewController` (UIKit/AVKit) | Keep thin platform adapters; share `AVPlayer`, item construction, selection, and observation. |
| Play/pause, seeking, buffering | `AVPlayer` plus native AVKit controls | Same | Documented for local, progressive remote, and HLS media ([controlling transport](https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player)). |
| Playback speed | `AVPlayerView.speeds`, macOS 13+ | `AVPlayerViewController.speeds`, iOS 16+ | Native speed UI is available at both deployment targets. |
| Full screen | Full-screen toggle and `AVPlayerViewDelegate` lifecycle | Full-screen presentation and enter/exit behaviors on `AVPlayerViewController` | Native presentation; no custom player required. |
| Picture in Picture | `AVPlayerView.allowsPictureInPicturePlayback`, macOS 10.15+ | `AVPlayerViewController`, iOS 9+ | Explicitly documented; Apple directs macOS apps to `AVPlayerView` for PiP ([AVPlayerViewController](https://developer.apple.com/documentation/avkit/avplayerviewcontroller)). |
| Keyboard transport | Space, arrows, and J/K/L are built into `AVPlayerView` regardless of control style | System player interactions | macOS shortcuts are documented by [`AVPlayerView`](https://developer.apple.com/documentation/avkit/avplayerview). |
| Now Playing / media controls | `AVPlayerView.updatesNowPlayingInfoCenter`, default `true` | Equivalent player-view-controller property, default `true` | Now Playing publication is documented ([macOS property](https://developer.apple.com/documentation/avkit/avplayerview/updatesnowplayinginfocenter)). Validate physical media keys and Control Center; explicitly register `MPRemoteCommandCenter` handlers if native publication alone is insufficient. |
| Embedded audio/subtitle selection | `AVMediaSelectionGroup` / `AVMediaSelectionOption`; native AVKit presentation | Same | `AVPlayer` selects defaults from system preferences or the app may select explicitly ([media selection](https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks)). |
| HLS adaptive quality | Automatic variant selection; bit-rate and resolution ceilings | Same | The controls are preferences, not exact locks. |
| Supplemental caption drawing | `AVCaptionRenderer`, macOS 12+ | `AVCaptionRenderer`, iOS 18+ | The app supplies parsed `AVCaption` objects and draws into a graphics context. |
| Playback telemetry | AVMetrics event model | AVMetrics event model | HLS metrics exist on both; progressive-download metric coverage was added in macOS/iOS 26 ([What's new in HLS 2025](https://developer.apple.com/streaming/Whats-new-HLS.pdf)). |

All availability statements in the table were checked against the public API annotations in Xcode 26.6's `MacOSX26.5.sdk` and `iPhoneOS26.5.sdk`; none needs a compatibility fallback below Miraio's declared macOS/iOS 26 floors.

### What “native player” includes on macOS

`AVPlayerView` is an `NSView` that presents video and the standard playback controls. Its public surface includes selectable control styles, a full-screen button, built-in playback speed choices, PiP, Now Playing publication, and a `contentOverlayView` positioned between video and controls ([`AVPlayerView`](https://developer.apple.com/documentation/avkit/avplayerview), [`contentOverlayView`](https://developer.apple.com/documentation/avkit/avplayerview/contentoverlayview)). It also presents the audio and legible options made available by the asset. This is the correct SwiftUI bridge: wrap one `AVPlayerView` using `NSViewRepresentable`, rather than reproducing the transport bar in SwiftUI.

On iOS, the corresponding shell is `AVPlayerViewController`, not the macOS view. It supplies native controls, full-screen behavior, playback speeds, PiP, AirPlay, Now Playing updates, and its own `contentOverlayView` ([`AVPlayerViewController`](https://developer.apple.com/documentation/avkit/avplayerviewcontroller)). The shared layer should therefore own player/item state and expose platform-neutral commands and observations, while the two platform shells remain small.

### Media keys are a validation item, not a reason for a custom player

Apple documents automatic Now Playing updates, but that property alone does not explicitly promise every Mac keyboard's media-key routing. The public fallback is `MPRemoteCommandCenter`, whose macOS interface includes play, pause, toggle, stop, rate, skip, seek, and change-position commands. **Empirical gate:** verify media keys and Control Center against the native `AVPlayerView` first; add command handlers only for missing actions. This is integration around the native player, not a replacement for it.

## Authorized network playback

### Public, low-risk authorization forms

**Documented:** `AVPlayer` accepts remote file URLs and HLS URLs. `AVURLAsset` has public initialization support for:

- HTTP cookies, including supplemental cookies for HLS requests whose media, keys, or variant playlists live at other applicable paths or hosts;
- a custom User-Agent;
- cellular, constrained, and expensive-network policy;
- MIME override and URL-request attribution.

Cookie domain/path rules still apply; `AVURLAssetHTTPCookiesKey` does not turn a cookie into an unrestricted header. Query parameters in a signed media URL naturally remain part of the URL, but child HLS URLs receive authorization only if the playlist itself carries suitable signed URLs or the cookie policy covers them.

The public initialization-options list contains no general header dictionary. Inspection of the macOS/iOS 26.5 SDKs also finds no public declaration of `AVURLAssetHTTPHeaderFieldsKey`; although the framework's text-based binary stub exports a similarly named symbol, using an undeclared symbol/string key is private-SPI reliance and is incompatible with the App-Store-ready constraint. **Decision consequence:** do not build on the commonly circulated `AVURLAssetHTTPHeaderFieldsKey` technique.

### Authentication challenges and resource loading

**Documented:** `AVAssetResourceLoaderDelegate` can answer an `NSURLAuthenticationChallenge`. It can also handle resources AVURLAsset cannot load itself (Apple's example is a custom URL scheme), provide response and byte-range data, cancel work, renew resources, and set an `AVAssetResourceLoadingRequest.redirect`; that redirect is restricted to an HTTP URL ([`AVAssetResourceLoader`](https://developer.apple.com/documentation/avfoundation/avassetresourceloader), [`redirect`](https://developer.apple.com/documentation/avfoundation/avassetresourceloadingrequest/redirect)). These APIs exist on both deployment targets.

An authentication challenge is suitable for challenge/credential mechanisms represented by `URLAuthenticationChallenge`; it is not a documented arbitrary-header callback for every AVFoundation request. In particular, no Apple document promises that it can inject a bearer or `Referer` header into all HLS playlist and segment requests.

**Inference:** a custom-scheme loader can proxy a progressive resource through app-owned `URLSession` requests while honoring AVFoundation byte ranges. For HLS, the adapter may also have to rewrite the master playlist, variant playlists, segment URLs, encryption-key URLs, and subtitle URLs into the handled scheme so authorization is retained on every child resource. That is a materially larger and more failure-prone transport adapter than passing a signed URL to AVPlayer.

Apple's SDK documentation warns that when a resource-loader delegate supplies playback media data, `AVPlayer.automaticallyWaitsToMinimizeStalling` should be set to `false`, because AVPlayer's future-availability predictions do not work as expected with client-controlled loading. The default may remain enabled when the delegate only answers authentication challenges or supplies a dynamically generated HLS master playlist. This warning makes full media proxying an explicit startup/stall/energy prototype, not a default architecture.

### Redirect gates

For an app-managed `URLSession`, redirect policy is controllable through Foundation. AVPlayer's direct HTTP stack is opaque. The resource-loader redirect property is public but only covers requests the delegate is handling and only redirects to HTTP URLs.

Test these service-specific cases before locking the native URL path:

1. 302, 303, 307, and 308 responses from the API/stream host;
2. same-host versus cross-host CDN redirects;
3. whether authorization is needed only to mint/resolve the URL or on every redirected request;
4. whether cookies survive under their actual domain/path/SameSite policy;
5. progressive `Range` requests after a redirect and after seeking;
6. HLS master, variant, segment, key, and subtitle requests;
7. token/signed-URL expiry during a long episode.

If the official Anime365 API returns a short-lived URL that redirects to a self-authorizing CDN URL, pre-resolving that URL with the authenticated API client and handing the final URL to AVPlayer is the simplest **inferred** design. It remains an empirical gate until exercised against the official service.

## Channels, renditions, and quality

### Audio and subtitles inside an asset

**Documented:** load the asset's audible and legible media-selection groups, inspect their `AVMediaSelectionOption` values, and call `AVPlayerItem.select(_:in:)` for an explicit choice. AVPlayer otherwise applies automatic selection criteria based on system language/accessibility preferences. Selected legible content is drawn by `AVPlayerView`, `AVPlayerViewController`, and `AVPlayerLayer` ([selecting subtitles and alternative audio tracks](https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks)).

This is appropriate for HLS `EXT-X-MEDIA` audio/subtitle renditions and recognized embedded tracks. It does not discover Anime365 concepts such as translation, voice-over team, alternate host, or API-defined stream channel unless the service encodes those concepts as HLS media groups.

### API-defined alternative channels

**Inference:** model API channels as candidate playable sources above AVFoundation. Selecting one replaces the `AVPlayerItem`; the app can restore the previous item time after the new item becomes ready. Channel failover is therefore a service-layer policy, not an AVKit control to reimplement. Preserve the native player view and player instance where possible.

**Empirical gate:** determine whether a channel switch can seek to the same logical episode time, whether durations/timelines differ, and whether a new authorization URL must be minted.

### HLS quality selection is preference-based

**Documented:** AVPlayer performs adaptive HLS variant selection. `preferredPeakBitRate` asks it to limit network consumption, and `preferredMaximumResolution` applies a preferred HLS resolution ceiling; AVPlayer may still choose what it needs to continue playback ([`preferredPeakBitRate`](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredpeakbitrate), [`AVPlayerItem`](https://developer.apple.com/documentation/avfoundation/avplayeritem)). `startsOnFirstEligibleVariant` influences only the initial choice, and the player may switch later. `AVAssetVariant` exposes variant metadata for inspection, while the public playback API does not offer an exact persistent “select this `AVAssetVariant`” operation.

Therefore:

- **Auto** should leave ceilings at their defaults and let AVPlayer adapt.
- A user-facing “up to 720p” or data-saver choice can set resolution/bit-rate ceilings honestly.
- A label such as “720p locked” is not truthful for a multivariant playlist using only these properties.
- If Anime365 exposes separate fixed-quality URLs, choosing that URL can provide an explicit service-level quality choice while playback remains native.

AVMetrics in macOS/iOS 26 can report playlist/resource activity, stalls, and HLS variant switches, including selected video/audio/subtitle rendition information. Use it for diagnostics and acceptance measurements, while scrubbing signed URLs before persistence or export ([What's new in HLS 2025](https://developer.apple.com/streaming/Whats-new-HLS.pdf)).

## Subtitle compatibility

| Input shape | Native playback status | Recommended handling |
| --- | --- | --- |
| HLS WebVTT subtitle rendition | **Documented native.** Apple requires WebVTT text segments with `X-TIMESTAMP-MAP`; AVPlayer exposes the legible option and renders it. | Prefer native selection/rendering. |
| HLS text-profile IMSC1 in fMP4 | **Documented native** for the general macOS/iOS HLS authoring profile. | Prefer native selection/rendering; verify actual service encoding. |
| Recognized embedded subtitle/closed-caption track in a playable QuickTime/MPEG-4 asset | **Documented at the media-selection abstraction**, but Apple does not promise every subtitle codec/container combination in the overview. | Use native media selection after an actual asset exposes a legible group. Maintain a fixture matrix. |
| Standalone WebVTT sidecar | No public API is documented to attach it to an existing player item. WebVTT-specific `AVPlayerItem.textStyleRules` apply to WebVTT the player is already presenting ([`textStyleRules`](https://developer.apple.com/documentation/avfoundation/avplayeritem/textstylerules)). | Parse/render as an overlay, or author a local HLS presentation only if a prototype justifies the complexity. |
| Standalone SRT sidecar | No public runtime attachment/parser is documented. Apple's subtitle segmenter accepts SRT as authoring input and converts it to WebVTT. `AVCaptionRegion` includes an SRT bottom-region semantic, but that is not a file loader. | Parse SRT into a simple caption model and use `AVCaptionRenderer` or another lightweight overlay. |
| ASS/SSA sidecar | Not present in Apple's public HLS formats, media types, player APIs, or caption authoring interfaces. | Use an ASS-aware parser/renderer overlay; define and test the allowed degradation. |

The HLS specification's supported caption list is CEA-608, CEA-708, WebVTT, and text-profile IMSC1. Its subtitle-delivery rule is WebVTT or IMSC1; SRT and ASS are not listed ([HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/)). This is stronger evidence than file-extension experiments, but **empirical compatibility tests remain required** for every format/container combination the official Anime365 API actually returns.

### What `AVCaptionRenderer` can and cannot do

**Documented:** the app supplies `AVCaption` objects and a drawing bounds, asks for scene-change ranges, and renders the scene for a media time into a `CGContext`. The scene API identifies periods that need periodic refresh for embedded animation, allowing redraws to be event-driven rather than unconditional ([`AVCaptionRenderer`](https://developer.apple.com/documentation/avfoundation/avcaptionrenderer), [`captionSceneChanges(in:)`](https://developer.apple.com/documentation/avfoundation/avcaptionrenderer/captionscenechanges(in:))).

The Xcode 26.5 SDK's public `AVCaption` model includes time ranges, text, percentage/cell regions, horizontal/vertical writing, alignment, foreground/background color, bold/italic, underline/strike/overline, ruby text, and one character-reveal animation. It does not expose ASS's full style and override-tag vocabulary: arbitrary font family/size, outline and shadow semantics, transforms/rotation, vector drawings, blur, clip paths, layered collision behavior, or the range of karaoke animations.

So `AVCaptionRenderer` is a credible Apple-native supplemental renderer for SRT and deliberately simplified WebVTT/ASS, but not evidence of ASS fidelity. For the agreed product requirement, a dedicated ASS renderer remains necessary unless API research proves every usable stream also offers native WebVTT/IMSC1.

### Overlay integration and PiP

`AVPlayerView.contentOverlayView` is explicitly intended for custom views between the video and controls, so it is the lowest-risk macOS attachment point for a supplemental subtitle layer. The iOS player view controller has a corresponding overlay view. Drive overlay timing from the player's item time/timebase, update only at cue/scene boundaries, and render continuously only during effects that actually animate.

Apple does **not** document that arbitrary views in `contentOverlayView` are composited into Picture in Picture. **Empirical gate:** test native HLS subtitles and the supplemental overlay separately in inline, window full-screen, macOS PiP, iOS full-screen, iOS PiP, seeking, rate changes, and display scaling. If custom subtitles disappear in PiP, the subsequent product decision is among graceful subtitle degradation in PiP, disabling PiP for that subtitle mode, or undertaking a custom composited-video/PiP path. The last option risks the native-player and battery goals and should not be assumed.

## Decode path and battery implications

AVPlayer is Apple's high-level playback pipeline and should be allowed to own demuxing, decode, buffering, audio synchronization, and presentation. The public VideoToolbox API can ask whether hardware decode is supported and can enable/require/report hardware acceleration for an app-created `VTDecompressionSession`, but those flags do not configure or prove AVPlayer's internal decoder ([hardware-accelerated VideoToolbox decoder key](https://developer.apple.com/documentation/videotoolbox/kvtvideodecoderspecification_enablehardwareacceleratedvideodecoder)). AVPlayer's public APIs offer no “require hardware decoder” switch.

**Inference:** leaving video presentation in `AVPlayerView` preserves the best opportunity for the system to choose its optimized hardware path. Adding a separate subtitle overlay need not force the app to pull or recompose every video pixel. In contrast, using `AVPlayerItemVideoOutput`, a custom video compositor, or app-owned VideoToolbox decode to burn subtitles into frames creates a more expensive pipeline and risks native PiP/controls behavior.

Hardware decode and energy are therefore acceptance measurements, not compile-time guarantees:

1. Use representative service fixtures for every codec, container, quality, frame rate, and subtitle mode.
2. Compare the same Mac, brightness, display, network, asset, quality ceiling, and playback interval.
3. Establish an AVKit-only/native-caption baseline, then measure SRT and ASS overlay modes.
4. Record CPU wakeups, CPU/GPU time, memory, thermal state, dropped frames, network bytes, stalls, and system Energy Impact; use AVMetrics for playback/network events and Instruments/power tooling for device energy.
5. Confirm hardware decode empirically with platform tooling rather than inferring it merely from successful playback.
6. Keep `canUseNetworkResourcesForLiveStreamingWhilePaused` false unless live-state freshness is required; Apple explicitly warns that enabling it spends extra networking and power ([property documentation](https://developer.apple.com/documentation/avfoundation/avplayeritem/canusenetworkresourcesforlivestreamingwhilepaused)). Leave `preferredForwardBufferDuration` at `0` unless measurements justify a change, because Apple notes that high values increase system demand ([buffer documentation](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration)).

The agreed target of no more than 10% additional playback energy over an AVKit-only reference, under 1% idle CPU, and no continuous background polling is compatible with the architecture, but can only be accepted after the overlay and authorization paths are known.

## Decision-ready recommendation

1. Make `AVPlayer` + `AVPlayerView` the macOS playback baseline. Enable its full-screen toggle, PiP, speed list, automatic Now Playing integration, and native media-selection UI. Wrap it for SwiftUI; do not recreate transport controls.
2. Keep the player/session coordinator, `AVURLAsset`/`AVPlayerItem` construction, media-selection logic, quality policy, timing observation, history progress, and metrics behind shared macOS/iOS protocols. Keep only `AVPlayerView` versus `AVPlayerViewController` in platform UI adapters.
3. Prefer native legible renditions in this order: HLS WebVTT/IMSC1, then recognized embedded subtitle tracks. They offer the best system behavior and lowest custom energy cost.
4. For external SRT, use a small parser plus `AVCaptionRenderer` unless a common subtitle abstraction with the ASS path proves simpler. For ASS, use a dedicated supplemental renderer over the native player and explicitly scope graceful degradation.
5. Do not use private `AVURLAssetHTTPHeaderFieldsKey`. Prefer signed stream URLs or applicable cookies. Treat any bearer/`Referer`-on-every-request requirement as a resource-loader prototype gate.
6. Present HLS quality controls as **Auto** or an upper limit. Promise a fixed quality only when the service provides a fixed-quality source URL.
7. Before implementation planning closes, run two narrow prototypes with real authorized fixtures: the stream authorization/redirect/range matrix, and the subtitle fidelity/PiP/energy matrix. These are the remaining unknowns Apple documentation cannot settle.

## Required empirical fixture matrix

The implementation specification should not claim “native playback works” until it records results for:

- each Anime365 stream type and codec returned by the official API;
- progressive and HLS assets, including all redirect hosts and range behavior;
- signed URL, cookie, bearer, User-Agent, and `Referer` requirements actually returned by the API;
- each alternative channel and quality representation;
- native WebVTT/IMSC1/embedded subtitle examples;
- representative SRT and ASS files with overlapping dialogue, positioned signs, fonts, outlines, karaoke, drawings, and malformed cues;
- inline, full screen, seeking, 0.5×/1×/2×, sleep/wake, PiP, external display, and token expiry;
- an AVKit-only energy baseline and the same run with the supplemental renderer.

This matrix separates what Apple guarantees from what Miraio must prove against the service.
