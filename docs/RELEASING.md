# Packaging and releases

`Packaging/Info.plist` is the source of truth for the app version and build number. Increment both before shipping. Keep the existing bundle identifier (`dev.screenz.mac`) to preserve Launch at Login and system preferences across updates.

## Local development package

```sh
zsh scripts/test.sh
zsh scripts/package.sh
```

The script builds `arm64` and `x86_64`, combines them with `lipo`, generates a full-resolution `.icns` icon from vector drawing code, bundles the phone page and MIT license, and signs the app ad hoc. It produces:

- `dist/Screenz.app`
- `dist/Screenz-<version>-universal.dmg` with an Applications shortcut
- `dist/Screenz-<version>-universal.zip`
- `dist/Screenz-<version>-universal.sha256`

The script checks both binary architectures, the app signature, and DMG integrity. It rebuilds only generated paths under `.build/` and `dist/`. No signing certificates or credentials belong in this repository.

## Developer ID and notarization

Install a **Developer ID Application** certificate with its private key in your login keychain. Configure a notarytool keychain profile using Apple's instructions, then run:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='screenz-notary' \
zsh scripts/package.sh
```

This enables hardened runtime and timestamped signing, submits the app ZIP to Apple, staples the accepted ticket to the app, creates the distributable ZIP and DMG, signs and notarizes the DMG, staples it, and checks Gatekeeper acceptance. A failed signing or notarization command stops packaging. Never label the ordinary ad-hoc build notarized.

See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). The signed/notarized path requires your own Apple Developer credentials and cannot be validated by unsigned CI.

## GitHub automation

- Pull requests and pushes to `main`: tests on Apple Silicon and Intel, followed by universal packaging. Packages are uploaded as workflow artifacts.
- Push `v<version>`: validates that the tag matches Info.plist, runs tests, packages the app, and creates a **draft** GitHub release with explicitly labeled non-notarized development assets.
- Manual `Package release draft` runs: builds artifacts without creating a release.

For a public notarized release, build with the signing environment above, upload those artifacts to the draft, and update the release notes to reflect the actual signature and notarization status before publishing. The automated workflow intentionally contains no signing keys.

## Release checks

1. Run the automated tests and inspect `.build/previews/`.
2. Build packages, verify checksums, and mount the DMG to check its contents.
3. Install a copy outside the build directory and confirm menu bar startup and phone pairing.
4. Exercise a real phone photo, multi-display apply, Keep, timeout revert, and Quit.
5. Check Launch at Login on the installed build if enabling it.

Synthetic tests do not replace the physical-device checks. A universal binary contains both architectures; Intel execution is separately exercised by CI.
