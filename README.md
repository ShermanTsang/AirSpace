# AirSpace

AirSpace is an i3-inspired tiling window manager for macOS, based on [AeroSpace](https://github.com/nikitabobko/AeroSpace). It provides workspaces, keyboard-driven window management, a menu bar and a graphical settings editor.

## Configuration compatibility

AirSpace reads AeroSpace-compatible configuration files. Unless a configuration file is explicitly specified, it looks for `~/.aerospace.toml` and `${XDG_CONFIG_HOME:-~/.config}/aerospace/aerospace.toml`. When no custom configuration exists, the settings editor can create one at `~/.aerospace.toml`. These paths and AeroSpace-compatible configuration keys and environment variables retain their original names.

AirSpace and AeroSpace can therefore use the same configuration file; changes made by either application affect that shared file. AirSpace uses its own application identifier (`com.github.shermantsang.airspace`) and the `airspace` command.

## Running alongside AeroSpace

Because AirSpace has its own application identifier, macOS treats it as a separate application: it needs its own Accessibility permission, its own login item, and its own runtime files (`/tmp/com.github.shermantsang.airspace-$USER.sock`). Permissions and login items granted to AeroSpace are not inherited.

Only one tiling window manager should manage windows at a time. Quit AeroSpace before starting AirSpace (and vice versa); both running at once means both apps rearrange the same windows. AirSpace detects a running AeroSpace at startup and shows a warning instead of silently fighting over your windows.

## Releases

Each `v`-prefixed version tag, such as `v1.2.3` or `v1.2.3-rc.1`, builds and publishes a GitHub Release. The ZIP contains a universal application and CLI for both Apple Silicon and Intel Macs, plus shell completions, manual pages, and licenses. A SHA-256 checksum is published alongside it. Tags with a prerelease suffix are marked as prereleases.

When the repository secrets below are configured, tag releases are signed with a Developer ID Application certificate and notarized by Apple. The application is stapled, so it opens without a Gatekeeper warning. Manual workflow runs build an ad-hoc signed artifact for verification and never publish.

### Signing and notarization secrets

Notarization requires a paid Apple Developer Program membership and a `Developer ID Application` certificate. A free Apple ID cannot obtain one. Use a `Developer ID Application` certificate, not an `Apple Distribution` or `Developer ID Installer` certificate. If the certificate is not in your keychain, create it in the developer portal or in Xcode under Settings → Accounts → Manage Certificates.

Add these repository secrets in Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application certificate and private key, exported as `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | Apple ID of the developer account |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password created at [appleid.apple.com](https://appleid.apple.com) |
| `APPLE_TEAM_ID` | Team ID from the developer account's Membership page |

To export the certificate, open Keychain Access, select the `Developer ID Application: ...` certificate together with its private key, choose Export, and save a `.p12`. Then:

```sh
base64 -i DeveloperID.p12 -o DeveloperID.p12.b64
gh secret set MACOS_CERTIFICATE < DeveloperID.p12.b64
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
gh secret set APPLE_TEAM_ID
```

Delete the `.p12` and `.b64` files after uploading. The workflow imports the certificate into a temporary keychain and deletes the keychain at the end of the job.

Publishing starts with a draft release. If uploading fails, inspect the draft and delete it before rerunning the failed workflow; an existing release is never overwritten.

To verify a build without publishing, run the Release workflow manually and supply a version; download its artifact from the workflow run. To publish, push a version tag after the release workflow is present in the tagged commit:

```sh
git tag v1.2.3
git push origin v1.2.3
```

## Development

See [development instructions](./dev-docs/development.md) for setup, building and testing. AirSpace runs on macOS 13 or later.

## Upstream references

AirSpace derives from AeroSpace and is an independent, MIT-licensed fork. Releases are published by this repository, not by the upstream AeroSpace project. The upstream [guide](https://nikitabobko.github.io/AeroSpace/guide), [command reference](https://nikitabobko.github.io/AeroSpace/commands), and [goodies](https://nikitabobko.github.io/AeroSpace/goodies) describe AeroSpace and may differ from AirSpace. The upstream project can be supported through [GitHub Sponsors](https://github.com/sponsors/nikitabobko).
