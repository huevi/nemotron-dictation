# Nemotron Dictation

Press **Control–Space**, speak, then press it again to turn your speech into text. Nemotron Dictation is a macOS menu bar app for offline English dictation. It can paste into the text field where you started or copy the result to your clipboard.

## Install

Requires **macOS 14 or newer** and an Apple Silicon Mac or an Intel Mac with AVX2. Setup downloads about **939 MB** for the speech model. The app itself is a small download and requires no developer tools.

1. Download the ZIP for **Apple Silicon** (`arm64`) or **Intel** (`x86_64`) from [GitHub Releases](https://github.com/huevi/nemotron-dictation/releases/latest). If you’re unsure which to choose, look for **Chip** or **Processor** in **Apple menu → About This Mac**.
2. Unzip it and move **Nemotron Dictation.app** to **Applications**. Quit any older copy before opening the new one.
3. Open the app from Applications. These release builds are ad-hoc signed and lack Apple notarization. If macOS blocks the first launch, go to **System Settings → Privacy & Security**, click **Open Anyway** for Nemotron Dictation, then confirm **Open** if you trust the download. See [Apple’s instructions](https://support.apple.com/en-us/102445). If your Mac is managed and your organization restricts overrides, contact your administrator.

The Intel build was tested end to end with a fresh model download and prerecorded audio. The Apple Silicon build uses the upstream Metal engine and has been cross-compiled and checked. It still needs a hardware smoke test.

## First launch

1. Click **Download model** in the setup window. The app shows progress and verifies the download against a pinned SHA-256 digest. If the transfer fails, click **Retry download**. The app reuses the verified model on later launches.
2. Click **Allow microphone** and approve the macOS prompt.
3. For automatic paste, click **Enable automatic paste** and turn on the app under **Privacy & Security → Accessibility**. You can skip this and paste the clipboard result yourself with **Command–V**.
4. Click in the setup test field, press **Control–Space**, say “This is my first dictation,” and press **Control–Space** again. The recording pill shows the timer, waveform, and stop and discard buttons. The smaller transcribing pill appears while the model runs.
5. Click **Done**. Use the waveform icon in the menu bar to reopen **Setup…**, change automatic paste, copy the last transcript, or quit.

To start Nemotron Dictation when you sign in, choose **Open at Login** from the waveform menu. Click it again to turn it off. If macOS asks for approval, enable it under **System Settings → General → Login Items & Extensions**.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| **Control–Space** | Start or stop recording. |
| **Control–Option–Space** | Hold to talk and release to transcribe. |
| **Fn / Globe** (optional) | Start or stop on keyboards that expose Fn. Enable it from the menu bar. This shortcut requires Input Monitoring. |

## Troubleshooting

- **Control–Space changes the input language.** In **System Settings → Keyboard → Keyboard Shortcuts → Input Sources**, disable or reassign **Select the previous input source**, then quit and reopen Nemotron Dictation. You can also use the hold-to-talk shortcut.
- **The transcript didn’t paste.** Check that Accessibility is enabled and the original field is still available. Try **Command–V**. If a new build replaced an older one and the Accessibility switch is on but paste still fails, remove the old entry, add the current app from Applications, then reopen it.
- **Nothing records.** Check **Privacy & Security → Microphone**, then check the input level under **Sound → Input**. Microphone permission and the model download are required for recording.
- **You can’t find the app window.** The app lives under the waveform icon in the menu bar. Choose **Setup…** to reopen the window.

## Privacy and storage

The app downloads the model from Hugging Face during setup. It runs English recognition locally after that, including when the Mac is offline. The app writes audio to a temporary file and removes it after transcription or discard. A successful transcript goes to the system clipboard and stays available from the menu until you quit. The app asks for Input Monitoring only if you choose to set up Fn.

The model lives in `~/Library/Application Support/Nemotron Dictation/Models`. To uninstall, quit the app and move it to the Trash. Remove that folder if you also want to reclaim the model space.

## Build from source

With Apple’s Command Line Tools installed (`xcode-select --install`):

```sh
git clone https://github.com/huevi/nemotron-dictation.git
cd nemotron-dictation
./scripts/build.sh
open "build/$(uname -m)/Nemotron Dictation.app"
```

The build script checks the pinned Parakeet engine archive and ad-hoc signs the app. It accepts `arm64` or `x86_64` to select a target. You can smoke-test the recognizer with a prerecorded 16 kHz mono WAV after setup.

```sh
"build/$(uname -m)/Nemotron Dictation.app/Contents/MacOS/NemotronDictation" --test-file /path/to/test.wav
```

## Credits

- App source is [MIT licensed](LICENSE).
- [parakeet.cpp v0.6.1](https://github.com/mudler/parakeet.cpp/releases/tag/v0.6.1) provides the MIT-licensed recognition engine. Its license and third-party notices are bundled with the app.
- [NVIDIA Nemotron-Labs-Unified-ASR-0.6B](https://huggingface.co/nvidia/nemotron-labs-unified-asr-0.6b) is published under OpenMDW 1.1. The app downloads the [Q8 GGUF conversion by mudler](https://huggingface.co/mudler/parakeet-cpp-gguf).
