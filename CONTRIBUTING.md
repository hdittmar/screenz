# Contributing

Screenz uses Swift Package Manager and Apple's system frameworks. Open `Package.swift` in Xcode, or use the scripts in `scripts/`.

```sh
zsh scripts/test.sh
zsh scripts/build-app.sh
open dist/Screenz.app --args --show-window
```

`Sources/ScreenzCore` contains layout estimation and HTTP parsing. `Sources/Screenz` contains the native app, display APIs, Vision detection, server, and bundled phone page. Keep image processing local and preserve the explicit preview/apply/keep flow.

For changes to layout or upload behavior, add a test for a real failure mode. Do not modify system display settings in automated tests. Run physical display checks manually and state what you tested in the pull request.

Please include the macOS version, display count, and reproduction steps in bug reports. Avoid uploading desk photos, pairing tokens, or other personal information to public issues unless you intend to share them.

Packaging and signing instructions are in [docs/RELEASING.md](docs/RELEASING.md).
