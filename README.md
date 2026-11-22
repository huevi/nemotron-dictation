# Nemotron Dictation

Nemotron Dictation turns spoken English into text on your Mac. Press **Control–Space** to record, then press it again to transcribe. The transcript goes to your clipboard and can also be pasted into the field where you started.

## Install

You need macOS 14 or newer and an Apple Silicon Mac or an Intel Mac with AVX2.

1. Get the **Apple Silicon** (`arm64`) or **Intel** (`x86_64`) ZIP from [GitHub Releases](https://github.com/huevi/nemotron-dictation/releases/latest). Check **Apple menu → About This Mac** if you’re unsure which to choose.
2. Unzip it and move **Nemotron Dictation.app** to your **Applications** folder.
3. Open it from Applications. The app is ad-hoc signed. If macOS blocks it, see [Apple’s instructions for opening a trusted app](https://support.apple.com/en-us/102445).

## First launch

1. Click **Download model** to get the English speech model (about 939 MB).
2. Click **Allow microphone** and approve the macOS prompt.
3. If you want automatic paste, click **Enable automatic paste** and turn on Nemotron Dictation under **Privacy & Security → Accessibility**.
4. Try a short dictation in the setup text field, then click **Done**.

## Everyday use

- Press **Control–Space** to start or stop recording.
- Hold **Control–Option–Space** to talk, then release to transcribe.
- Press **Command–V** to paste the transcript from your clipboard.

Click the **waveform** in the menu bar to copy the last transcript, toggle **Paste Automatically**, reopen setup, or turn on **Open at Login**.

If Control–Space changes the input language, reassign **Select the previous input source** under **System Settings → Keyboard → Keyboard Shortcuts → Input Sources**, then reopen Nemotron.

## Update an existing install

1. Quit the app from its menu.
2. Keep a backup of the old app outside Applications. Put the new app in the same Applications location, then open it.
3. If setup asks for Microphone or Accessibility again, follow the setup prompts. If Accessibility appears enabled but paste still fails, remove the old entry and add the updated app from Applications.

If your local build uses a custom bundle identifier, keep that identifier and re-sign the replacement before installing it. This preserves your preferences and login item.

## Privacy and storage

Transcription runs offline after setup. The app deletes temporary recordings after transcription or discard. The model is stored in `~/Library/Application Support/Nemotron Dictation/Models`.

## Build and verify

Install Apple’s Command Line Tools with `xcode-select --install` if needed.

```sh
git clone https://github.com/huevi/nemotron-dictation.git
cd nemotron-dictation
./scripts/build.sh
```

The app is in **build/arm64** or **build/x86_64**. Use the same Applications install steps above. After downloading the model, you can test transcription with a 16 kHz mono WAV.

```sh
"build/$(uname -m)/Nemotron Dictation.app/Contents/MacOS/NemotronDictation" --test-file /path/to/test.wav
```

Intel builds have been tested on hardware. Apple Silicon has been cross-built and still needs a hardware test.

## Credits

- App source is [MIT licensed](LICENSE).
- [parakeet.cpp v0.6.1](https://github.com/mudler/parakeet.cpp/releases/tag/v0.6.1) provides the MIT-licensed recognition engine.
- [NVIDIA’s Nemotron speech model](https://huggingface.co/nvidia/nemotron-labs-unified-asr-0.6b) is licensed under OpenMDW 1.1. The app uses the [Q8 GGUF conversion](https://huggingface.co/mudler/parakeet-cpp-gguf).
