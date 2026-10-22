<p align="center">
  <img src="FrameTrail/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" height="112" alt="FrameTrail app icon">
</p>
<h1 align="center">FrameTrail</h1>
<p align="center"><strong>Every story leaves something behind.</strong><br>Remember what you watched. Discuss the ending. Keep what stayed with you.</p>
<p align="center"><a href="README.md">Русский</a> · <strong>English</strong></p>
<p align="center">
  <a href="https://github.com/eljke/FrameTrail/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/eljke/FrameTrail/build.yml?branch=main&amp;style=for-the-badge&amp;logo=githubactions&amp;logoColor=white&amp;label=CI&amp;labelColor=241d42" alt="Current CI status"></a>
  <a href="https://github.com/eljke/FrameTrail/releases"><img src="https://img.shields.io/github/v/release/eljke/FrameTrail?include_prereleases&amp;sort=semver&amp;style=for-the-badge&amp;label=release&amp;labelColor=241d42&amp;color=ffc65d" alt="Latest published version"></a>
  <a href="https://github.com/eljke/FrameTrail/releases"><img src="https://img.shields.io/github/downloads/eljke/FrameTrail/total?style=for-the-badge&amp;label=downloads&amp;labelColor=241d42&amp;color=ffc65d" alt="Asset downloads across all releases"></a>
</p>
<p align="center">
  <a href="https://github.com/eljke/FrameTrail/stargazers"><img src="https://img.shields.io/github/stars/eljke/FrameTrail?style=for-the-badge&amp;logo=github&amp;logoColor=white&amp;label=stars&amp;labelColor=241d42&amp;color=ffc65d" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/eljke/FrameTrail?style=for-the-badge&amp;label=license&amp;labelColor=241d42&amp;color=ffc65d" alt="MIT license"></a>
  <a href="#requirements-and-first-launch"><img src="https://img.shields.io/badge/iOS-26%2B-ffc65d?style=for-the-badge&amp;logo=apple&amp;logoColor=white&amp;labelColor=241d42" alt="Requires iOS 26 or later"></a>
</p>

A companion for movies and television: recall watched events, discuss an ending, and save your own impressions. Apple's system model generates responses on your device; the library, sources, and journal also work without generation.

[Download IPA](https://github.com/eljke/FrameTrail/releases) · [Builds and checks](https://github.com/eljke/FrameTrail/actions) · [Privacy (RU)](docs/PRIVACY.md) · [Sources and licenses (RU)](docs/THIRD_PARTY_NOTICES.md)

Current release: **1.0.0-beta.1**, app version **1.0.0**, build **1**. This is a prerelease. Automated results are published in Actions; the local model, latency, and LiveContainer installation have not yet been verified on a physical device. Check Releases for the actual IPA and the status of each published version.

The badges use public GitHub metadata: actual build status, published version, stars, and downloads. Downloads counts **all release asset downloads**, not users or installations. Cached badges may update with a delay. There are no visitor trackers or view counters.

## What the beta does

| Feature | How it works |
| --- | --- |
| Movie and show search | TVmaze shows and Wikidata movies work without a key. A personal TMDB API Read Access Token enables the expanded TMDB catalog. |
| Personal library | Save a search result or add a title manually. Mark watched episodes and completed movies. |
| Recall watched events | Read a watched episode's summary or ask the assistant. Inspect available source material and links without generation. |
| Discussion after the ending | Mark a title as finished to use its available full-film material and discuss a recap, ending, motivations, or open questions. Answer quality depends on the sources. |
| Your own sources | Paste text or import UTF-8 TXT, SRT, and VTT files. Assign a specific episode when importing material for a show. |
| Personal reflection | Save thoughts, favorite details, open questions, and a 1–10 rating. Find saved reflections in the journal. |
| Viewing statistics | The journal shows saved titles, completed titles, watched episodes, reflections, and a rating average and distribution. Ratings use reflection records: multiple records for one title count separately. |
| TMDB account | Approve sign-in on the provider's website. Each account has a separate local library. |
| Watchlist import | An explicit action reads up to 10 movie pages and 10 show pages from TMDB: up to 400 titles with the standard page size. Existing entries are preserved. |
| Data portability | Export or import a JSON library, merge by entry modification time, and clear source materials separately from your notes. |

Catalogs provide information and links to titles. The app does not contain a video player, free access to paid movies, or a complete screenplay database. TVmaze and Wikidata coverage differs from TMDB; searching the original title often helps. Wikidata movie results are restricted to entities explicitly classified as a film or feature film. Their cards provide a name, an available release year, and a short description without a poster. This is not a detailed plot: load Wikipedia or import your own material for a deeper discussion. Progress, conversations, and reflections do not automatically synchronize between devices. Watchlist import only runs when requested and makes no changes to TMDB.

## Requirements and first launch

Installation requires **iOS 26 or later**. Generation additionally requires an eligible device, enabled Apple Intelligence, a downloaded system model, and a language it supports. The app checks readiness and the selected language on the device before responding. [Apple Intelligence requirements](https://support.apple.com/en-us/121115).

The interface is primarily Russian. On first launch, the response language is **Russian when the primary system language is Russian, otherwise English**. A saved preference takes precedence. Russian responses have two local paths: direct generation when Foundation Models supports Russian on the device, or on-device Apple Translation from Russian to English before source retrieval and from the English model's answer back to Russian. The translation path requires an available language pair and prepared system language packs. Support is checked at runtime; native Russian Foundation Models support is not promised. If the model, language, or packs are unavailable, the app explains the limitation. There is no cloud fallback.

1. Open [Releases](https://github.com/eljke/FrameTrail/releases) and download `FrameTrail-1.0.0-beta.1.ipa`. A SHA-256 checksum is provided alongside it.
2. Install the IPA through AltStore or another compatible tool that applies your own signature. The published IPA is **unsigned**. Your installation tool manages signature refreshes and its installation limits.
3. In Settings, check the local assistant status and response language. For Russian through translation, prepare the language packs using the system dialog. Their initial download requires a connection.
4. Find a title in Overview or add one manually. Open it in the library and mark what you have watched.
5. If needed, add material for one episode or a completed movie. Open the discussion and inspect its available sources.
6. After finishing, save a personal reflection; it appears in the Journal.

Discussing saved sources does not require a network request to a language model; Russian through translation requires language packs to be prepared beforehand. Search, episodes, posters, plot downloads, and TMDB sign-in require internet access. Apple separately downloads and updates the system model and translation packs. Foundation Models and Apple Translation inside LiveContainer, and the behavior of a particular re-signed installation, still require physical-device verification. Compatibility is not guaranteed.

## Connect TMDB and sign in

1. Create an account at [TMDB](https://www.themoviedb.org) or use an existing one.
2. Obtain your application's **API Read Access Token** in [TMDB API settings](https://www.themoviedb.org/settings/api), following TMDB's terms. Paste the token itself without a `Bearer` prefix. This field is not for a password or the short v3 API key.
3. Open FrameTrail Settings, find the expanded catalog section, paste the token, and save it.
4. Tap the TMDB sign-in action. Sign in on the provider's website in the browser and approve the request.
5. Close the browser, return to FrameTrail, and tap **«Я подтвердил вход в TMDB»** (“I approved sign-in on TMDB”). Completion is manual; this beta does not complete sign-in automatically through a callback link.
6. Optionally use the TMDB watchlist import action.

TMDB handles your password. The app stores its API token and session in Keychain. Guest and account libraries are separate; signing in does not upload or automatically merge guest entries. Signing out retains that account's library on the device, making it available when you sign in to the same account again. Use explicit export and import to move entries between libraries.

## Viewing boundaries and accuracy

Before sending text to the model, application code selects sources for the current title and only episodes explicitly marked as watched. Movie plot material is allowed after completion. Material assigned to a future episode is excluded from that source packet. Reducing viewing progress clears the previous conversation because its answers may discuss events that are now outside your boundary. Every question creates a new model session; previous assistant answers are not treated as evidence.

These are testable restrictions on the **supplied sources**. Free-form generation can still make a mistake, invent a fact, or recall a spoiler from pretraining. Asking the model to stay within its sources reduces that risk without guaranteeing zero spoilers. Compare claims and references with the available materials. An episode synopsis is not a detailed screenplay, and missing evidence does not trigger a hidden web search.

This beta uses **fully watched episodes** as its boundary. SRT/VTT import converts subtitles into text for the selected episode; playback position is not a viewing boundary in the interface. Do not assign an entire season's plot to an early episode: the app relies on the scope you choose.

An explicit button can load a completed movie's plot from English Wikipedia. Candidate matching checks the title and, where available, the year, but ambiguous names can still select the wrong article. Follow the saved revision link and verify the movie. If no suitable plot section is found, import your own material.

## Storage and privacy

The IPA contains neither model weights nor an offline copy of the catalog. Apple's system model and downloaded translation packs use storage separately from the IPA; iOS manages them. CI rejects a release if either the app or the IPA exceeds **40 MiB**. The release asset shows the actual file size.

Selected titles are stored in JSON libraries with a **10 MiB per-account limit**. This limits library files, not peak memory use or the combined storage of every account. Network response bodies are limited to 2 MiB. Text imports accept a file up to 512 KiB and retain up to 40,000 characters. Conversations and source records also have saving limits.

Clearing downloaded materials removes source texts, including imported material, and saved episode lists from the current library. Progress, conversations, and reflections remain. You will need to download or import sources again. Library exports contain user records and source material **without encryption**, excluding tokens and sessions. Save backups somewhere you trust. The app has no advertising or analytics SDK, and does not send conversations to a cloud model. Apple's system Translation API may collect usage/performance metadata such as the app bundle ID and language pair, excluding the original and translated text. [Privacy details (RU)](docs/PRIVACY.md).

## Build and test

You need macOS, stable Xcode 26 or later with an iOS SDK, Python 3.11+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Compilation needs no third-party runtime packages or secrets. `project.yml` generates the Xcode project.

This development checkout is located at `C:\Projects\iOS\FrameTrail` on Windows. On a Mac, clone the repository and run the following commands from its root. Windows can be used for editing; the iOS app builds with Xcode or GitHub Actions.

```sh
brew install xcodegen
export DEVELOPER_DIR="$(python3 scripts/select_xcode.py)"
python3 scripts/validate.py
python3 scripts/test_delivery.py
swift test --package-path Packages/FrameTrailCore
xcodegen generate
```

Run tests on an installed iOS 26+ simulator:

```sh
SIMULATOR_ID="$(python3 scripts/select_simulator.py)"
xcodebuild -project FrameTrail.xcodeproj -scheme FrameTrail \
  -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/simulator \
  -resultBundlePath build/FrameTrailTests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Build an unsigned device IPA:

```sh
xcodebuild -project FrameTrail.xcodeproj -scheme FrameTrail \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
python3 scripts/package_ipa.py \
  --app build/device/Build/Products/Release-iphoneos/FrameTrail.app \
  --version "$(cat VERSION)" --output dist --max-size-mb 40
```

CI runs domain, service, filesystem, and UI checks; retains simulator results and screenshots; and builds the device app and IPA. A simulator run does not establish system-model availability on a physical iPhone. See the actual result in [Actions](https://github.com/eljke/FrameTrail/actions).

## Versions and contributions

`VERSION` contains the release's SemVer string, `1.0.0-beta.1`, and is bundled as a resource. Settings shows this value alongside the actual bundle build number. The bundle uses numeric version `1.0.0` and build `1`. Tag `v1.0.0-beta.1` must match `VERSION` exactly. The workflow publishes the prerelease with its IPA and SHA-256 only after successful checks. Stable version tags are not marked as prereleases.

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), for example `feat: add episode source import`, `fix: preserve library on failed writes`, or `chore: prepare 1.0.0-beta.1`. The beta contract, structure, and acceptance criteria are documented in the [specification](docs/specs/1.0.0-beta.1.md). Keep both README languages aligned when behavior changes. To report a bug, include the iOS version, installation method, steps to reproduce, and expected result. Do not publish tokens, private library exports, or personal conversations in Issues.

The application code and original icon use the [MIT license](LICENSE). MIT does not apply to external texts, posters, metadata, the TMDB logo, or Apple's platform components. See [THIRD_PARTY_NOTICES (RU)](docs/THIRD_PARTY_NOTICES.md) for their terms.
