# Prototype findings

Environment: macOS 26.6.2, Apple Silicon, Xcode 26.6, libass 0.17.5 from Homebrew. Observed 2026-08-21 with generated local media and the synthetic `fidelity-matrix.ass` fixture.

## Reproduced facts

- libass parses the in-memory ASS fixture, uses its public CoreText provider, and resolves the requested Helvetica Neue and Avenir Next families from system fonts.
- The bounded C adapter renders dialogue, explicit top positioning, simultaneous layers, authored styles, karaoke, motion/transform, and vector drawing into premultiplied RGBA without owning networking, credentials, persistence, playback, or a timer.
- The AppKit host attaches those pixels only to `AVPlayerView.contentOverlayView` and sizes them to `AVPlayerView.videoBounds`, not to the surrounding letterbox or native controls.
- Rendering is driven by an `AVPlayer` item-time observer. Seeks, rate changes, and the loop use the media timebase; no independent idle polling loop exists.
- Active text is exposed separately as a VoiceOver-labelled semantic value. Override tags and vector drawing instructions are not presented as spoken text.
- The synthetic animated frame captured during QA took 8.70 ms at an 839×471 overlay. That is a single diagnostic sample, not an energy result.
- `AVCaptionRenderer` can preserve readable text, limited regions/styles, overlap timing, and one character-reveal animation only after a separate ASS-to-caption mapping. It cannot represent the fixture’s arbitrary positioning, outline/shadow semantics, layers, karaoke timing, transforms, or drawings, so it does not meet Miraio’s agreed core ASS fidelity gates.
- The adapter rejects ASS input above 1 MiB or 10,000 events and output above 3840×2160; disables embedded-font extraction; and caps libass’s glyph cache at 10,000 entries and bitmap cache at 128 MiB. These are prototype bounds, not a substitute for fuzzing or process isolation.

## Packaging and license boundary

- libass itself declares ISC. The Homebrew 0.17.5 build dynamically links FreeType, FriBidi, HarfBuzz, and libunibreak plus Apple system frameworks.
- Homebrew declares FTL for FreeType, GPL-2.0-or-later **and** LGPL-2.1-or-later for FriBidi, MIT for HarfBuzz, and Zlib for libunibreak. Production must select and comply with the applicable license for the exact vendored build and ship notices/source or relinking mechanisms where required; this prototype is not legal advice.
- The prototype binary is ad-hoc signed and references `/opt/homebrew/opt/libass/lib/libass.9.dylib`. It is therefore intentionally unsuitable for sandboxed, notarized, Cask, or App Store distribution.
- A production integration needs a reproducible minimal arm64 Apple-platform build, embedded code-signed libraries or XCFrameworks, relative install names/rpaths, a complete transitive SBOM/notices bundle, hardened-runtime and App Sandbox verification, notarization, and App Review/license review. The CoreText provider avoids a runtime fontconfig dependency, but the exact production link graph must be audited rather than inferred from Homebrew.

## Human walkthrough result

Recorded 2026-08-21:

- Core fidelity, seeking, playback speeds, full screen, VoiceOver semantic output, and selective dialogue boost passed without observed misbehavior.
- Neither the libass overlay nor the flattened `AVCaptionRenderer` overlay was visible in native Picture in Picture.

## Decision

Choose libass behind the already-agreed supplemental renderer boundary; reject `AVCaptionRenderer` as the ASS engine. Keep Apple captions for native caption formats or deliberately simplified non-ASS inputs, not as a conversion target for Anime365 ASS.

Because native PiP omits both supplemental overlays, disable PiP while external ASS is selected. Keep native PiP available when AVKit owns the active subtitle rendition or no subtitles are selected. Do not silently drop selected external subtitles, and do not add a custom composited-video/PiP path that would replace native playback ownership and threaten the energy target.

The controlled Power Profiler ratio was not measured in the human walkthrough. The prototype includes paired `AVKit only` and `libass` modes so implementation acceptance can enforce the existing `median(libass / AVKit only) <= 1.10` release gate under fixed conditions. The single captured 8.70 ms animated-frame render remains diagnostic only.

## Acceptance results still to record during implementation

- Controlled paired Power Profiler result: median net-energy ratio and run conditions, or explicitly deferred release gate.
- Production vendored-build fuzzing, memory-pressure, sandbox, signing, notarization, transitive-license, and App Review results.
