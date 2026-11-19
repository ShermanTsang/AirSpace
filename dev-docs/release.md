# Release Process

This document describes how AirSpace release artifacts are built, signed, notarized, and published.

AirSpace publishes a **single Universal artifact** that runs on both Apple Silicon and Intel Macs. The CLI is always built with `--arch arm64 --arch x86_64`, and the Xcode Release build uses `ARCHS_STANDARD`, so both the app and the CLI contain `arm64` and `x86_64` slices.

## Artifact layout

A release produces `AirSpace-v<version>.zip` with this layout:

```text
AirSpace-v<version>/
├── AirSpace.app
├── bin/airspace
├── legal/
├── manpage/
└── shell-completion/
```

The GitHub Release also contains `AirSpace-v<version>.zip.sha256`.

The workflow is defined in [`.github/workflows/release.yml`](../.github/workflows/release.yml).

## Versioning

Versions use semantic versioning:

- `v1.2.3` — stable release.
- `v1.2.3-rc.1` — prerelease. Any tag containing `-` is published as a GitHub prerelease.

The tag must match:

```text
^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$
```

The version without the leading `v` is passed to the build as `MARKETING_VERSION` and embedded in the app.

## Prerequisites

### Apple Developer account

Notarization requires:

- A **paid Apple Developer Program membership**.
- A **Developer ID Application** certificate. `Apple Distribution` and `Developer ID Installer` certificates cannot be used for this workflow.
- The certificate and its **private key**, exported together as a `.p12`.
- The Team ID from the developer account's Membership page (also the `OU` field of the certificate subject).
- An **app-specific password** created at <https://appleid.apple.com>. This is not the Apple ID login password.

If the certificate is not installed on any Mac, create it in the developer portal or in Xcode under **Settings → Accounts → Manage Certificates**, then export it from Keychain Access.

### Local release builds

A full local release build additionally needs the dependencies described in [development.md](./development.md):

- Xcode and the Swift toolchain installed by `script/setup.sh`.
- `brew install bash fish` for shell completion.
- Rust and `complgen` for shell completion.
- Ruby, Bundler, and Asciidoctor for man pages.

`build-release.sh` requires a clean working tree because it runs `script/check-uncommitted-files.sh` after regenerating files.

## GitHub secrets

Tag builds require these repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded `.p12` containing the Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | Apple ID of the developer account |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password created at <https://appleid.apple.com> |
| `APPLE_TEAM_ID` | Team ID of the developer account |

Export and upload the certificate:

```sh
# In Keychain Access, select the "Developer ID Application: ..." certificate
# together with its private key, then export a .p12.
base64 -i DeveloperID.p12 -o DeveloperID.p12.b64
gh secret set MACOS_CERTIFICATE < DeveloperID.p12.b64
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
gh secret set APPLE_TEAM_ID
rm DeveloperID.p12 DeveloperID.p12.b64
```

`gh secret set` without a value prompts for it, so the password does not end up in shell history.

The workflow imports the certificate into a temporary keychain and deletes the keychain in an `if: always()` cleanup step. Tag builds fail early when a secret is missing; they never silently publish an unsigned build.

Manual workflow runs do not need any of these secrets: they build an ad-hoc signed artifact for verification and never publish.

## Automated release

### 1. Prepare the commit

```sh
git switch main
git pull
./script/check-uncommitted-files.sh   # must pass
./lint.sh
./test.sh
```

If you want to exercise the release build locally before tagging:

```sh
./build-release.sh --build-version 0.0.0-test --codesign-identity -
```

This produces an ad-hoc signed, non-notarized Universal build in `.release/`. It is useful for validating the app layout and the build scripts, but it does not validate the Developer ID or notarization path.

### 2. Verify the workflow without publishing

After the workflow is present on `main`, run it manually:

```sh
gh workflow run release.yml --ref main -f version=0.0.1-test
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
```

Download the artifact and inspect it:

```sh
gh run download <run-id> -n AirSpace-v0.0.1-test-universal -D /tmp/airspace-artifact
cd /tmp/airspace-artifact
shasum -a 256 -c AirSpace-v0.0.1-test.zip.sha256
unzip -l AirSpace-v0.0.1-test.zip
unzip AirSpace-v0.0.1-test.zip
lipo -archs AirSpace-v0.0.1-test/AirSpace.app/Contents/MacOS/AirSpace
lipo -archs AirSpace-v0.0.1-test/bin/airspace
```

Both `lipo` commands must list both `x86_64` and `arm64`. The manual run is ad-hoc signed and not notarized; that is expected.

### 3. Push a tag

```sh
git tag v1.2.3
git push origin v1.2.3
```

For a prerelease:

```sh
git tag v1.2.3-rc.1
git push origin v1.2.3-rc.1
```

Monitor the run:

```sh
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
```

### What the workflow does

Build job (`macos-26`, arm64):

1. Checks out the tagged commit and validates the version.
2. Selects Xcode with `.github/gh-actions-runner-xcode-select.sh`.
3. Installs `bash`, `fish`, `swiftly`, and the pinned Swift toolchain.
4. Imports the Developer ID certificate into a temporary keychain and resolves the identity with `security find-identity`.
5. Runs `./build-release.sh --build-version "$VERSION" --codesign-identity "$IDENTITY" --notarize`:
   - Builds docs and shell completion.
   - Runs `generate.sh` and `check-uncommitted-files.sh`.
   - Writes `.build-info.txt` with the version and git hashes.
   - Builds the CLI and app in parallel:
     - CLI: `swift build -c release --arch arm64 --arch x86_64`.
     - App: Xcode Release build with manual signing, hardened runtime, and secure timestamp.
   - Re-signs embedded dylibs and the app with hardened runtime, secure timestamp, and the app's entitlements.
   - Runs `script/validate-release-binaries.sh` (exact layout, Universal slices, embedded git hash, rpaths, dylibs, deployment target, code signature).
   - Packs the app, CLI, man pages, completion, and licenses into a ZIP.
   - Submits the ZIP to Apple's notary service, waits for `Accepted`, staples the ticket to `AirSpace.app`, validates it with `stapler`, and checks it with `spctl`.
   - Recreates the ZIP with `ditto` so the stapled ticket is included, then generates the Homebrew casks.
6. Writes `AirSpace-v<version>.zip.sha256`.
7. Uploads the ZIP and checksum as the `AirSpace-v<version>-universal` artifact.

Publish job (`ubuntu-latest`, tag pushes only):

1. Downloads the `AirSpace-v<version>-universal` artifact.
2. Creates a **draft** GitHub Release with generated notes.
3. Uploads the ZIP and checksum.
4. Un-drafts the release.

An existing release is never overwritten. The draft-then-publish order means a failed upload leaves a draft that can be inspected instead of a half-published release.

### Signing and notarization details

- Xcode signs with `CODE_SIGN_STYLE=Manual`, `ENABLE_HARDENED_RUNTIME=YES`, `OTHER_CODE_SIGN_FLAGS=--timestamp`, and the identity's Team ID.
- `script/build-release-app.sh` re-signs every `Contents/Frameworks/*.dylib` and then the app bundle with `codesign --options runtime --timestamp`, passing `resources/AirSpace.entitlements` explicitly so the app does not lose its entitlements.
- `script/build-release-cli.sh` signs the CLI with `codesign --options runtime --timestamp`.
- `script/notarize-release.sh` refuses to submit unless both the app and the staged CLI have a `Developer ID Application` authority and the hardened runtime flag.
- The notarization ticket is stored as a regular file at `AirSpace.app/Contents/CodeResources` (not `Contents/_CodeSignature/CodeResources`). Packaging after stapling with `ditto -c -k --keepParent` preserves it.
- The CLI is included in the notarized ZIP but cannot be stapled itself; Gatekeeper validates it online on first use.

### Verify the published release

```sh
gh release view v1.2.3
gh release download v1.2.3 -D /tmp/airspace-release
cd /tmp/airspace-release
shasum -a 256 -c AirSpace-v1.2.3.zip.sha256
unzip AirSpace-v1.2.3.zip
xcrun stapler validate AirSpace-v1.2.3/AirSpace.app
spctl --assess --type execute --verbose=4 AirSpace-v1.2.3/AirSpace.app
codesign -dv --verbose=4 AirSpace-v1.2.3/AirSpace.app
```

Expected output includes:

- `stapler validate` exits 0.
- `spctl` reports `source=Notarized Developer ID`.
- `codesign` reports `Authority=Developer ID Application: ...`, a team identifier, and `flags=...runtime)`.

## Local signed and notarized build

> This path is implemented but has not yet been exercised end to end with a real Developer ID certificate. Treat the commands below as the intended procedure, not as a previously verified run.

Store notary credentials once (the command prompts for the app-specific password):

```sh
xcrun notarytool store-credentials airspace-notary \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID"
```

Then build and notarize locally:

```sh
./build-release.sh \
  --build-version 1.2.3 \
  --codesign-identity "Developer ID Application: Your Name (TEAMID)" \
  --notarize \
  --notarytool-profile airspace-notary
```

Alternatively, pass credentials through the environment without putting the password in shell history:

```sh
read -r -s APPLE_APP_SPECIFIC_PASSWORD
export APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD
./build-release.sh \
  --build-version 1.2.3 \
  --codesign-identity "Developer ID Application: Your Name (TEAMID)" \
  --notarize
```

The result is in `.release/`:

```text
.release/AirSpace-v1.2.3/
.release/AirSpace-v1.2.3.zip
.release/airspace.rb
.release/airspace-dev.rb
```

`--notarize` requires a Developer ID identity; it rejects `--codesign-identity -`.

## Failure recovery

### Build failure

Build logs are written to:

- `.release/build-cli.log`
- `.release/build-app.log`

The workflow prints both on failure. Fix the code, commit, and retry.

### Notarization failure

The notary service log is printed by `script/notarize-release.sh`. Common causes:

- The app or CLI is not signed with a Developer ID Application certificate.
- Hardened runtime or secure timestamp is missing on a Mach-O file.
- The Apple ID, app-specific password, or Team ID is wrong.
- A nested executable is unsigned.

Fix the cause and rerun. If the failing build was triggered by a tag and no release was published yet, move the tag:

```sh
git tag -d v1.2.3
git push origin :refs/tags/v1.2.3
git tag v1.2.3 <fixed-commit>
git push origin v1.2.3
```

Never move a tag after a release has been published.

### Publish failure

If the publish job fails after creating the draft:

```sh
gh release view v1.2.3          # confirm it is still a draft
gh release delete v1.2.3 --yes  # delete only the draft release, not the tag
gh run rerun <run-id> --failed  # retry the publish job with the existing artifact
```

Do not add `--cleanup-tag`: keeping the tag lets the same commit be retried. Deleting the tag would also make it possible for a later push to create a second release for the same version.

If the artifact has expired, rerun the whole workflow or move the tag as described above. `gh release create` fails when the release already exists, so a rerun cannot overwrite a published release.

## Security notes

- Never commit the `.p12`, its password, the app-specific password, or a notarytool keychain profile.
- Do not paste these values into chat, issues, or pull requests.
- Use `read -s` or `gh secret set` prompts to avoid shell history.
- The notarization script disables shell tracing after sourcing the setup script so credentials are not printed.
- The workflow deletes the temporary keychain and any temporary `.p12` even when the job fails.
- Revoke and replace the app-specific password if it is exposed. Revoke the certificate if its private key is exposed.
- Limit who can push `v*` tags: a tag push can publish a release and consume notarization requests. The `publish` job runs with `contents: write`, granted only to that job; the build job keeps `contents: read`.
- Limit who can change repository secrets and workflow files.

## Known gaps and future improvements

- The Developer ID signing, notarization, and stapling path has not yet been exercised end to end with a real certificate. The first tagged release is its real validation.
- A full local `build-release.sh` run requires Asciidoctor, fish, and complgen; when they are missing, CI performs the first full docs/completion build.
- The app icon currently in `main` replaced the upstream icon (commit `30bc81f9`; the per-size variants were added later) and the old CC BY 4.0 wallpaper attribution was removed. Confirm the current icon is original or properly licensed; restore the attribution if it still derives from the wallpaper.
- If upstream documentation text (not just links) is copied into this project, add the upstream CC BY 4.0 attribution.
- The generated Homebrew casks point at the local ZIP and are not uploaded by the workflow. Publishing them to a tap is out of scope.
- Authentication currently uses an Apple ID and an app-specific password. An App Store Connect API key is an alternative if the account requires it.
- The current design publishes one Universal artifact. Separate per-architecture artifacts would require an `ARCHS` matrix and changes to the validation script; the Universal artifact already covers both architectures.

## Related files

- [`.github/workflows/release.yml`](../.github/workflows/release.yml)
- [`build-release.sh`](../build-release.sh)
- [`script/build-release-app.sh`](../script/build-release-app.sh)
- [`script/build-release-cli.sh`](../script/build-release-cli.sh)
- [`script/notarize-release.sh`](../script/notarize-release.sh)
- [`script/validate-release-binaries.sh`](../script/validate-release-binaries.sh)
- [`script/build-brew-cask.sh`](../script/build-brew-cask.sh)
- [`.github/gh-actions-runner-xcode-select.sh`](../.github/gh-actions-runner-xcode-select.sh)
