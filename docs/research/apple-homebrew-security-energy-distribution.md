# Apple and Homebrew constraints for Miraio

Research date: 2026-08-20

## Question

What factual constraints govern Keychain storage, App Sandbox network access and related entitlements, Mac App Store review readiness, Developer ID signing, notarization and stapling, Homebrew Cask packaging and updates, network and image caching, and reproducible measurement of playback energy and idle CPU on Apple Silicon?

## Executive answer

Miraio can use one sandbox-compatible architecture for both its first Homebrew release and a later Mac App Store release. The direct release should be an Apple Silicon, macOS 26+ app built with App Sandbox and only the outgoing-network entitlement, signed with Developer ID Application, hardened, timestamped, notarized, stapled, and shipped in a versioned, checksummed DMG through a project-owned Homebrew tap. The App Store build uses the same product capabilities but a separate App Store Connect signing/export path and no independent updater.

Authentication secrets should be private, non-synchronizing data-protection Keychain items. Authenticated API traffic should not use a persistent HTTP cache; public catalogue images can use a bounded `URLCache` that obeys server cache semantics and resides in purgeable cache storage. Apple publishes no numeric battery or idle-CPU acceptance limits. Miraio's agreed limits—playback energy no more than 10% above an AVKit-only reference, less than 1% idle CPU, and no continuous polling—are therefore project release gates that must be measured on fixed Apple Silicon hardware with paired, repeated workloads.

The largest nontechnical App Store risk is authorization. Apple says an app that accesses or displays a third-party service must be specifically permitted under that service's terms, and authorization may be requested; streaming can require the same proof. An official API is useful evidence but is not, by itself, proof that an independent client may be distributed through the Mac App Store.

## Classification

### Hard requirements

- A Mac App Store build must be sandboxed. A sandboxed streaming client needs `com.apple.security.network.client = true` to initiate remote connections; it does not need the server entitlement merely to receive responses on connections it initiated. [Apple: Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), [Apple: `com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
- App Transport Security (ATS) applies to `URLSession` and requires HTTPS connections that meet its security checks by default. Broad arbitrary-load exceptions reduce security and require App Review justification. [Apple: `NSAppTransportSecurity`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity), [Apple: `NSAllowsArbitraryLoads`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads)
- A current direct release that works under default Gatekeeper policy must use Developer ID signing and Apple notarization. Notarization requires valid signatures on all executable code, Developer ID certificates, Hardened Runtime, secure timestamps, no shipping `get-task-allow`, and well-formed entitlements. [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- A Mac App Store app must be self-contained, packaged and submitted using Xcode-provided technologies, may not install code or resources in shared locations, and must receive updates through the Mac App Store rather than an independent updater. [Apple App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/)
- App Review requires a working subscribed demo account or approved full demo mode for login-gated functionality, live backend services, complete metadata, an accessible privacy policy, and proof of authorization if requested for third-party service access or streaming. [Apple: App Review](https://developer.apple.com/app-store/review/), [Apple App Review Guidelines 2.1, 5.1, and 5.2](https://developer.apple.com/app-store/review/guidelines/)
- A cask in Homebrew's official repository must work on every OS/architecture it declares, work on the latest macOS, and must not require Gatekeeper or System Integrity Protection to be disabled. Official-repository acceptance additionally applies public-interest/notability criteria; software that is not yet eligible can be maintained in a third-party tap. [Homebrew: Acceptable Casks](https://docs.brew.sh/Acceptable-Casks), [Homebrew: Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy)

### Recommended project baseline

- Keep App Sandbox enabled in every release build, including Developer ID/Homebrew, so the first release exercises the later App Store security boundary.
- Use only `com.apple.security.app-sandbox` and `com.apple.security.network.client` unless a demonstrated feature requires another entitlement. Do not add incoming network, file, media-library, microphone, camera, app-group, or Keychain-sharing privileges speculatively.
- Store refresh/access tokens as non-synchronizing `kSecClassGenericPassword` items using `kSecUseDataProtectionKeychain = true` and the app's private default access group. Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` while tokens are only needed in the interactive app.
- Keep authenticated requests in an ephemeral `URLSession` with no persistent cache or credential store. Use a separate, bounded persistent `URLCache` only for responses known to be non-sensitive, initially catalogue artwork.
- Publish a signed, notarized, stapled DMG containing only `Miraio.app`; use a project-owned tap initially, with Homebrew—not an in-app updater—moving users between versions.
- Maintain separate Developer ID and App Store Connect archive/export jobs from the same source target and entitlement baseline.

### Empirical questions and release gates

- Do Anime365 API, artwork, subtitle, manifest, media-segment, redirect, and alternative-channel hosts all pass ATS without an exception? This must be tested against the official API's real redirect graph. An HTTP media fallback is not automatically acceptable: Apple's media-wide ATS exception is intended only for encrypted media without personalized information and still requires App Review justification. [Apple: `NSAllowsArbitraryLoadsForMedia`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsformedia)
- Do Developer ID and App Store-signed builds with the same team and bundle identifier retain access to the same Keychain item and sandbox container during an upgrade? Verify this with real distribution-signed artifacts before promising a seamless channel migration.
- What memory/disk image-cache capacities give useful hit rates without excessive disk use on the actual catalogue? Apple defines the mechanism but not a correct capacity for this product.
- Does the production player remain within 10% of the AVKit-only playback reference, and below 1% CPU at idle, on each supported Apple Silicon performance class? Only controlled measurement can answer this.
- Will App Review accept the service authorization supplied for an independent Anime365 client? No technical test can guarantee a review outcome.

## Security and entitlement findings

### Keychain

Apple describes Keychain Services as encrypted storage for small secrets. On macOS there are legacy file-based and data-protection Keychain implementations. `kSecUseDataProtectionKeychain = true` makes macOS items behave like iOS items, is safe to include on all Apple platforms, and Apple highly recommends it for portability unless legacy-item access is specifically required. That makes it the appropriate shared macOS/iOS service-layer choice. [Apple: Keychain Services](https://developer.apple.com/documentation/security/keychain-services), [Apple: `kSecUseDataProtectionKeychain`](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain), [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)

By default, code signing gives an app a private access group derived from its team and bundle identifiers. Explicit Keychain access groups are for sharing among apps from the same development team; an item belongs to exactly one group. Miraio v1 has one executable and does not need Keychain Sharing. Avoiding that entitlement reduces provisioning and migration surface. [Apple: Sharing access to Keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)

`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is recommended by Apple for data only needed while the foreground app is active and prevents migration to another device. That fits subscriber tokens and avoids silently copying a session to a future Mac or iOS device. Do not set `kSecAttrSynchronizable`; Apple notes that synchronization causes iCloud propagation, while the data-protection key provides iOS-like behavior without synchronization. [Apple: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), [Apple: Restricting Keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)

Implementation consequences:

- Persist only credentials/tokens and minimal identity needed to address them. Subscription status, expiry calculations, catalogue data, playback URLs, cookies, and watch history are not secrets that belong in Keychain merely because they are account-related.
- Address a generic-password item with a stable service name plus the Anime365 account identifier. Treat access and refresh tokens as separate values if their rotation/deletion semantics differ.
- Replace rotated tokens atomically with `SecItemUpdate`; on sign-out or terminal refresh failure, delete every account token with `SecItemDelete`, clear in-memory copies, and purge authenticated caches.
- Never print Keychain query dictionaries or token values. A Keychain item protects at rest; it does not make a copied token safe in logs, crash metadata, or `UserDefaults`.

### App Sandbox and network security

App Sandbox removes capabilities and restores only declared privileges. Miraio's first-party feature set initiates HTTPS connections and reads/writes only its own container, so its minimal release entitlement set is:

```plist
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

The client entitlement controls initiation of TCP connections; responses can flow over that connection. The server entitlement is for accepting connections initiated elsewhere and is unnecessary for catalogue browsing or streaming. Sandbox denial should be tested in Activity Monitor's Sandbox column and in system sandbox logs, as Apple's configuration guide describes. [Apple: Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), [Apple: `com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)

ATS requires HTTPS for URL Loading System traffic and imposes checks beyond ordinary TLS trust evaluation. Start with no `NSAppTransportSecurity` dictionary at all, because its defaults are suitable for most apps. If one concrete host fails, fix the server or select an API-provided secure alternative before considering a narrowly scoped domain exception. `NSAllowsArbitraryLoads = true` is incompatible with the desired security posture and creates an explicit review burden. [Apple: Preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections), [Apple: `NSExceptionDomains`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains)

Stream authorization headers and redirects do not require additional entitlements. They do require an application-level redirect policy: re-evaluate each redirect target against the API's documented host allowlist and do not forward `Authorization`, cookies, signed query values, or origin-specific headers to an unrelated host. This is a security recommendation inferred from the credential boundary, not a special Apple entitlement rule.

## Mac App Store readiness

Apple's Mac-specific review rules require sandboxing, a self-contained single-app bundle, Xcode packaging, no privilege escalation, no third-party installer, no automatic execution without consent, and no separate update mechanism. Consequently, the App Store build must not contain Sparkle or another updater even if dormant. Prefer no in-app updater in the Homebrew build either; Homebrew already owns the update operation. [Apple App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/)

The subscriber model is compatible in principle with the reader-app rule: reader apps may let users access previously purchased video subscriptions and manage an existing account. The safe App Store baseline is sign-in and sign-out only, with no subscription purchase or purchase call to action. The direct/Homebrew build can hand registration, recovery, and subscription changes to Anime365's website, but the App Store build must treat those links as a separate eligibility decision. External-link rules vary by storefront and the External Link Account Entitlement concerns a website the app developer owns or maintains; an independent client should not assume it can link to Anime365's account or purchase pages under that entitlement. [Apple App Review Guidelines 3.1.3(a)](https://developer.apple.com/app-store/review/guidelines/)

There is a separate authorization gate. Guidelines 5.2.2 and 5.2.3 require specific permission under the third-party service's terms and allow Apple to ask for authorization for service access and streaming. Before an App Store submission, retain a review packet containing the applicable official API documentation/terms, written service permission if needed, permitted branding/assets, geographic constraints, and a working subscribed reviewer account. [Apple App Review Guidelines 5.2](https://developer.apple.com/app-store/review/guidelines/), [Apple: App Review preparation](https://developer.apple.com/app-store/review/)

Privacy readiness requires an in-app and metadata privacy-policy link explaining catalogue/account/history data, collection, use, sharing, retention, deletion, and revocation. The app does not create Anime365 accounts, so Apple's in-app account-deletion requirement is not triggered by Miraio account creation; Miraio must still offer sign-out and deletion of its local data. The review submission must include a live subscribed demo account and explain authentication, subscription gating, translations, stream selection, and any non-obvious subtitle behavior in Review Notes. [Apple App Review Guidelines 2.1 and 5.1.1](https://developer.apple.com/app-store/review/guidelines/)

## Developer ID, notarization, and stapling

Developer ID and Mac App Store distribution are separate export paths:

| Concern | Homebrew/direct build | Mac App Store build |
| --- | --- | --- |
| App signature | Developer ID Application | App Store Connect distribution signing/profile |
| Runtime protection | Hardened Runtime; App Sandbox retained | App Sandbox required; distribution signing/profile |
| Container | Versioned signed DMG containing the app | Self-contained app submitted through Xcode/App Store Connect |
| Trust processing | Notarize direct artifact and staple ticket | App Store submission performs equivalent security checks; separate notarization is not required |
| Updates | `brew update`/`brew upgrade` through the tap | Mac App Store only |

For direct distribution, every executable and nested code object must be correctly signed. Apple explicitly warns not to use `codesign --deep` to *sign* complex products; sign nested code in dependency order or let Xcode export the archive. Hardened Runtime, a secure timestamp, and removal of `com.apple.security.get-task-allow` are notarization requirements. [Apple: Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac), [Apple: Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)

The automated direct-release path should:

1. Archive a Release build and export it for Developer ID with Xcode.
2. Verify nested signatures with `codesign -vvv --deep --strict`, inspect embedded entitlements with `codesign -d --entitlements :-`, and assess Gatekeeper policy with `spctl --assess --type exec`.
3. Put only the exported app and presentation assets in a read-only UDIF DMG; sign the DMG with Developer ID Application and a secure timestamp.
4. Submit the DMG with `xcrun notarytool submit ... --wait`; always fetch and inspect the notarization log, including accepted submissions.
5. Staple and validate the ticket with `xcrun stapler`; publish nothing until a quarantined download launches on a clean non-development Mac, including while offline.

Apple recommends a DMG for a single bundle when a signed container is desired. A ZIP can contain a signed/stapled app but cannot itself be signed or stapled, so a DMG gives the Homebrew release a stronger container-integrity and offline Gatekeeper story. [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## Homebrew Cask packaging and updates

The initial channel should be a project-owned tap, not a promise of immediate inclusion in `homebrew/cask`. Homebrew explicitly permits anyone to create a tap; casks live in its top-level `Casks` directory. Official-repository submissions normally need public interest beyond the author and a repository at least 30 days old; a self-submission normally needs 90 forks, 90 watchers, or 225 stars, subject to documented exceptions and maintainer discretion. [Homebrew: How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), [Homebrew: Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy)

Use a conventional cask shaped like this (exact release URLs and hashes belong to the release pipeline):

```ruby
cask "miraio" do
  version "1.0.0"
  sha256 "<sha256-of-published-dmg>"

  url "https://<endorsed-release-host>/miraio-#{version}-arm64.dmg"
  name "Miraio"
  desc "Native Anime365 catalogue and playback client"
  homepage "https://<public-project-homepage>/"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Miraio.app"
end
```

Each cask needs version, SHA-256, URL, name, description, homepage, and an artifact stanza. `depends_on arch: :arm64` expresses Apple Silicon and `depends_on macos: :tahoe` expresses macOS 26+. The download must be published by the developer or a publicly endorsed distribution source. Prefer HTTPS and an immutable versioned URL with a real checksum. [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Homebrew: Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)

Do not set `version :latest` or `sha256 :no_check`; Homebrew says to use a checksum whenever possible, while `:latest` prevents normal autobumping. Do not add `auto_updates true`: that stanza asserts the app itself downloads and installs updates, and a menu item that merely opens a web page does not qualify. With a normal versioned cask, the installed tap is refreshed by `brew update` and the outdated app is replaced by `brew upgrade`. [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Homebrew: Homebrew FAQ](https://docs.brew.sh/FAQ), [Homebrew: How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)

Release CI should generate the cask change only after the notarized DMG is immutable at its final URL, calculate the SHA-256 from those exact bytes, audit the cask, install it on a clean Apple Silicon macOS 26 machine, open the app under Gatekeeper, then test `brew upgrade` from the preceding release and `brew uninstall`. A `zap` stanza is optional and should never delete user-created files; if later added, limit it to verified Miraio cache/preferences/container paths and leave Keychain removal to explicit app sign-out or local-data deletion semantics. [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

## Network and image cache policy

Foundation's `URLCache` is a composite memory/disk response cache with configurable capacities and persistent location. `URLSessionConfiguration.default` uses a persistent disk cache and can store credentials and cookies; `ephemeral` keeps caches, cookies, credentials, and session state out of persistent storage. The default request policy, `useProtocolCachePolicy`, follows protocol cache freshness and revalidation behavior. [Apple: `URLCache`](https://developer.apple.com/documentation/foundation/urlcache), [Apple: `URLSessionConfiguration.default`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/default), [Apple: `URLSessionConfiguration.ephemeral`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral), [Apple: `requestCachePolicy`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/requestcachepolicy), [Apple: `useProtocolCachePolicy`](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy-swift.enum/useprotocolcachepolicy)

That supports two deliberately separate clients:

- **Authenticated API/authorization client:** ephemeral configuration, `urlCache = nil`, no shared credential storage, controlled cookie handling only if the official API requires it, and bearer tokens injected from in-memory Keychain-derived session state. Persist selected non-secret domain state (for example, last-known catalogue pages or history) through an explicit repository with documented retention—not accidentally through HTTP caching.
- **Public artwork client:** a dedicated `URLCache` with explicit memory and disk bounds, `useProtocolCachePolicy`, request coalescing, and image decoding/downsampling sized to the displayed pixel dimensions. Persist it in the app's caches directory so it is disposable rather than user data. Apple's performance guidance recommends caches storage for regenerable content so the system can purge it when needed. [Apple: Improving your app's performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)

Do not persist manifest URLs, signed media URLs, subtitle URLs containing credentials, authorized redirect responses, or personalized images. Clear the authenticated session, cookies, and any account-derived cached representations on sign-out. The actual artwork capacity, expiry override (if any), and decoded-image memory ceiling remain empirical choices: record hit rate, bytes transferred, disk use, decode time, memory pressure, and catalogue scroll energy before setting them.

## Reproducible energy and idle-CPU acceptance

Apple's App Review rules say apps should use power efficiently and should not rapidly drain battery, generate excessive heat, or place unnecessary strain on resources, but Apple specifies no numeric pass/fail threshold. Activity Monitor's Energy Impact is explicitly a *relative* measure, and lower is better. Apple recommends measuring before and after changes, profiling on a physical device, and using Instruments/Time Profiler and energy tooling to identify CPU, network, I/O, and power causes. [Apple App Review Guidelines 2.4.2](https://developer.apple.com/app-store/review/guidelines/), [Apple: View energy consumption in Activity Monitor](https://support.apple.com/guide/activity-monitor/view-energy-consumption-actmntr43697/mac), [Apple: Improving your app's performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)

The `powermetrics(1)` manual shipped with macOS 26 documents estimated SoC power, per-process energy-impact proxies, CPU time, GPU time on supported hardware, network/I/O activity, wakeups, and coalition grouping. It warns that estimates may be inaccurate and must not be compared across devices, while permitting their use to optimize apps. Therefore, Miraio's 10% target must be a same-device paired comparison, not an absolute wattage claim and not a comparison between Mac models.

Use this release protocol:

1. Build optimized, distribution-signed Release artifacts with diagnostics disabled; run without Xcode or a debugger.
2. Fix the Mac model, macOS build, display resolution/brightness, power source, battery state band, audio route/volume, network path, player size/full-screen state, media item, stream host, codec, quality, subtitles, and playback duration. Record all of them with the result.
3. Implement a minimal AVKit-only reference app that plays the exact same authorized stream with the same native controls and subtitle selection. This is the baseline required by the agreed target.
4. Warm both apps and the stream path, then run alternating baseline/Miraio trials to reduce thermal, CDN, and battery drift. Use at least five valid paired runs per supported hardware class and report the median paired ratio plus the range; reject runs interrupted by buffering, thermal-state changes, background jobs, or network changes.
5. Sample whole-system estimated power and the full app coalition, not only the UI process, because media and helper services can otherwise be missed. Retain raw `powermetrics` output and an Instruments trace for regressions. Activity Monitor Energy Impact is a useful smoke signal, not the sole benchmark.
6. Define playback acceptance as `median(Miraio net energy / AVKit-reference net energy) <= 1.10`, with the same idle-system baseline subtraction method for both. Run once with native subtitles and once with the supplemental renderer if the latter exists; the renderer cannot hide inside an aggregate average.

For idle CPU, Activity Monitor exposes per-process CPU time/activity and updates its display every five seconds by default. A reproducible threshold should instead derive CPU percentage from coalition CPU time divided by wall time, where 100% is one logical core. After launch, authentication, initial synchronization, and image work settle, hold a fixed catalogue screen with no input or playback for ten minutes, then repeat minimized/backgrounded. The release gate is mean coalition CPU below 1% of one logical core in both states, with raw five-second samples retained to reveal periodic polling. [Apple: View information about Mac processes in Activity Monitor](https://support.apple.com/guide/activity-monitor/view-information-about-processes-actmntr1001/10.14/mac/26), [Apple: View CPU activity in Activity Monitor](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac)

"No continuous background polling" is a behavioral gate rather than an Apple numeric rule: after pending writes finish, Instruments Network and system traces should show no timer-driven catalogue/history/subscription requests. Refresh on launch, foreground transition, explicit user action, playback milestones that need history synchronization, and server-indicated expiry. Coalesce pending history writes and use cache validators rather than fixed-frequency refresh loops.

## Decision-ready constraints

Downstream architecture and release planning can treat these as settled constraints:

1. One sandboxed app architecture, minimal outgoing-network entitlement, ATS defaults, and no speculative privileges.
2. Private, non-synchronizing data-protection Keychain items for tokens; separate ephemeral authenticated networking and bounded public-image caching.
3. Two signing/export pipelines: Developer ID + Hardened Runtime + notarized/stapled DMG for Homebrew, and App Store Connect signing/submission with no independent updater for the store.
4. A project-owned Homebrew tap is the initial dependable path; official `homebrew/cask` is a later eligibility decision.
5. App Store work remains gated on demonstrable Anime365 authorization, a subscribed reviewer account, privacy/support material, and ATS-compatible production endpoints.
6. Energy and CPU numbers are project benchmarks, not Apple guarantees: validate with paired same-device measurements and retain raw traces for each release.
