# Ego

Ego is a private voice journal for iPhone. You talk, the phone turns the recording into text, and a small language model on the device picks out observations and writes a review of your week. Speech recognition and the language model both run on the iPhone, so once you download the models, Ego works without a network connection. The interface is in English and Russian.

## Features

I tested installation, audio recording, and all three models on an iPhone 16 Pro Max.

Recording and entries:

- Record your voice with a live waveform, pause and resume, or type an entry instead
- Ego keeps the original audio next to the transcript
- In an entry you can edit the text, add context, rerun recognition with the other speech model, copy the text, or export it

Calendar and search:

- The calendar switches between month and year views, and you can jump straight to any year
- Search runs locally over text, context, topics, and observations
- A search matches every word of the query and treats the Russian letters е and ё as the same letter

The interface language follows your iOS settings. The **Interface language** row opens Ego's page in iOS Settings, where you pick English or Russian. You set the speech recognition language separately. Ego writes new observations and weekly reviews in the interface language and never translates existing text.

Settings cover Face ID, a daily reminder, a notification when an entry is ready, languages, and model downloads. Home Screen widgets and a Shortcuts action, which you can assign to the Action Button, open the recording screen. Ego has no server, accounts, subscriptions, ratings, or social features.

## On-device models

You download each model separately. The sizes below are the pinned model files, without temporary download files or the Core ML system cache.

| Model | Used for | Files |
|---|---|---:|
| Parakeet TDT 0.6B v3, Core ML | Russian and multilingual speech | 632 MB |
| Whisper Large v3 Turbo, Core ML | Russian and multilingual speech | 631 MB |
| Qwen 3.5 2B, MLX 4-bit | Observations and weekly reviews | 1.75 GB |

On the test iPhone, the first Whisper load after app launch took about 90 seconds, and transcribing 15.5 seconds of speech then took about 2 seconds. A second load in the same process took about 1.8 seconds. The app shows model preparation as its own step, because load times depend on the system cache and the state of the device.

After the download, recognition and observations work offline. You can keep both speech models on the phone and pick the active one. Ego runs one model job at a time and loads Qwen separately from the speech models.

`Ego/Resources/*.json` pins the revision, size, and checksum of every model file. Ego verifies large files by SHA-256 and small files from Git by their Git blob SHA-1. An interrupted download never counts as an installed model, and a new download reuses files that already passed verification.

The vendored WhisperKit uses a local tokenizer and has no network fallback loader. `Vendor/WhisperKit/EGO_VENDOR.md` describes the change. The repository contains no model weights.

## Build and run

Ego targets iPhone 16 Pro Max and newer on iOS 26 or later. To reproduce the tested build, use Xcode 27 with the Metal Toolchain component installed.

The repository doesn't store a bundle ID prefix or a development team. `Config/Ego.xcconfig` sets neutral values (`com.example`, no team) and includes `Config/Local.xcconfig` if it exists. Git ignores that file. To build for a device, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your own prefix and Team ID. Every target then gets an identifier like `<prefix>.ego` or `<prefix>.ego.widgets`.

1. Open `Ego.xcodeproj` in Xcode.
2. Wait for Swift Package dependencies to resolve.
3. Select the `Ego` scheme and a connected, unlocked iPhone with Developer Mode on.
4. Create `Config/Local.xcconfig` as described above, then run the app.
5. In Ego's settings, download a speech model. Download Qwen as well if you want observations.

`project.yml` is the source of truth for the project. After you change it, regenerate the project with `xcodegen generate`. The shared `Package.resolved` pins the versions of remote dependencies.

To build from the terminal:

```sh
xcodebuild -project Ego.xcodeproj -scheme Ego \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation ONLY_ACTIVE_ARCH=YES build
```

The `-skipPackagePluginValidation` flag allows the MLX build plugin to run. Neither this command nor running from Xcode publishes anything to the App Store or TestFlight.

## Storage and privacy

Ego stores entries, context, reviews, and audio references in a JSON archive inside Application Support and writes it atomically. Each recording is a separate AAC file. The folder is excluded from iCloud backup, and nothing syncs between devices. To keep your own copy, export to Markdown, JSON, or a ZIP archive with the audio.

With the lock turned on, an opaque screen covers the interface when the app goes to the background, and you need system authentication to get back in. Notifications never include journal text. Copied text goes to the local pasteboard only and expires after two minutes. Ego deletes temporary export files once you close the share sheet.

## Background behavior

Model jobs run only while the app is active. When the app moves to the background, Ego cancels the job and saves the unfinished step so it can resume later. Microphone recording uses its own audio background mode. Ego writes the review of a finished week the first time you open the app after Sunday evening. It doesn't promise to run on schedule while the app is closed.

Observations are model output. Ego checks that each quote matches the entry word for word and that supporting passages exist, but that doesn't prove the conclusion is right. The original recording always stays available.

## Tests

`EgoTests` covers saving and restoring the journal, handling corrupted data, search, calendar boundaries, export, and quote checks. `EgoUITests` covers creating a text entry, search, the calendar, the main screens, and audio recording. The `--uitest` and `--preview` launch arguments exist only in Debug builds, and the sample entries in preview mode are fictional.

`EgoModelCheck` is a macOS tool that uses the same `LocalIntelligence.swift` as the app. It confirms that the downloaded models actually run. It doesn't measure speed or memory use on iPhone.

## Dependencies

FluidAudio, a trimmed WhisperKit, and MLX Swift LM are vendored as source in `Vendor`, each with notes on its origin and changes. The MLX patch adds cancellation between chunks when processing long text. MLX Swift and ZIPFoundation come in through Swift Package Manager. Library licenses are kept, and Ego's settings link to the models and credit their authors.

Ego isn't on the App Store.

## License

Ego's code is released under the MIT license, see [LICENSE](LICENSE). Libraries in `Vendor` keep their own licenses.
