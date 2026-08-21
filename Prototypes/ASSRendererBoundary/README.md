# ASS renderer boundary prototype

> Throwaway evidence for “Validate the supplemental ASS renderer and Picture in Picture boundary.” This is not production Miraio code.

## Question

Can a real ASS engine remain a bounded, player-time-driven overlay while AVKit retains the Playback Session, native controls, full screen, and Picture in Picture—and is libass materially better than a narrower `AVCaptionRenderer` mapping for Miraio’s required ASS fidelity?

The prototype uses generated local video and a synthetic ASS fixture. It performs no networking, stores no Anime365 resource, and never receives an Access Token.

## Run

Requirements: macOS 26+, Apple Silicon, Xcode 26+, and Homebrew libass 0.17.x.

```sh
brew install libass
./Prototypes/ASSRendererBoundary/run.sh
```

On first run, a clearly named throwaway video is generated under the system temporary directory. The app then loops its 24-second fixture.

## Human walkthrough

1. Use each fixture jump button in `libass` mode. Confirm dialogue, top-positioned sign, overlapping lines, authored styles, karaoke, motion, and the vector sign are present and readable.
2. Repeat in `Apple captions` mode. Confirm ordinary text remains readable but arbitrary positioning, ASS outlines/shadows, layer composition, karaoke timing, motion, and vector drawing do not survive the narrow mapping.
3. Seek backward and forward; pause; select 0.5× and 2× from AVKit’s native speed control. Confirm subtitle state follows player-item time rather than wall-clock time.
4. Resize the window and enter AVKit full screen. Confirm the overlay scales and remains below the native control surface.
5. Start Picture in Picture from AVKit’s native controls in both modes. Record whether the supplemental image is visible in the PiP window.
6. With VoiceOver, focus the video’s subtitle element. Confirm the active plain-language caption is spoken and vector drawing commands are not exposed.
7. Toggle the dialogue boost in libass mode. Confirm ordinary dialogue becomes larger while the explicitly positioned sign retains authored placement; treat any wrong heuristic override as a veto on automatic appearance changes.
8. For a controlled energy run, use Xcode Instruments’ Power Profiler with the same fixed Mac/display/power conditions. Record repeated 10-minute runs in `AVKit only`, then `libass`, subtract the same idle-system baseline, and require `median(libass / AVKit only) <= 1.10`. Do not use the on-screen render-call time as a substitute.

## Boundary exercised

- Input is capped at 1 MiB and 10,000 events; output is capped at 3840×2160.
- Embedded font extraction is disabled. libass uses the public CoreText font provider with Helvetica Neue fallback.
- Glyph and bitmap caches have explicit hard ceilings.
- The adapter has no URL, credential, persistence, or playback-control surface.
- Rendering consumes `AVPlayer` item time. The periodic observer advances only with media time; paused idle has no independent timer or polling loop.
- Pixels attach to `AVPlayerView.contentOverlayView`; AVKit remains responsible for video, controls, full screen, speed selection, and PiP.
- Semantic active text is exposed separately for accessibility; it is not reverse-engineered from rendered pixels.

## Expected comparison

| Concern | libass adapter | `AVCaptionRenderer` mapping |
| --- | --- | --- |
| Core dialogue/timing | Direct ASS parse/render | Requires a separate ASS parser and mapping |
| Authored positioning/signs | Preserved by the fixture | Arbitrary ASS positioning and drawings are not representable |
| Styles/overlap | ASS-native | Narrow caption styles and regions only |
| Karaoke/animation | ASS-native rendering | Character reveal is only a readable approximation |
| Appearance adjustment | Best-effort selective libass heuristic | Native caption appearance model |
| Accessibility | Requires parallel semantic cues | Caption text is already semantic |
| PiP | Unknown until human walkthrough; overlay is not documented as composited | Same overlay attachment problem |
| Packaging | ISC libass plus transitive dependency review and vendoring work | Apple framework only |

`AVKit only` is also present as a paired measurement mode; it intentionally skips the supplemental renderer while retaining the same generated media and diagnostic callback.

## Deliberately not validated here

- Production XCFramework/dylib vendoring, hardened runtime, App Sandbox, signing, notarization, App Store submission, and third-party notices.
- Representative Anime365 ASS files or attached fonts; the official playback schema does not provide publishable stable fixtures.
- HDR color treatment, external displays, memory-pressure recovery, fuzzing, crash isolation, or malformed-input corpus behavior.
- Controlled Instruments energy measurements against an AVKit-only reference. The on-screen render-call timing is diagnostic, not an energy result.

Those are acceptance gates or packaging work after the engine/PiP policy is chosen; none should be inferred from a successful local run.
