# AirSpace

AirSpace is an i3-inspired tiling window manager for macOS, based on [AeroSpace](https://github.com/nikitabobko/AeroSpace). It provides workspaces, keyboard-driven window management, a menu bar and a graphical settings editor.

## Configuration compatibility

AirSpace reads AeroSpace-compatible configuration files. Unless a configuration file is explicitly specified, it looks for `~/.aerospace.toml` and `${XDG_CONFIG_HOME:-~/.config}/aerospace/aerospace.toml`. When no custom configuration exists, the settings editor can create one at `~/.aerospace.toml`. These paths and AeroSpace-compatible configuration keys and environment variables retain their original names.

AirSpace and AeroSpace can therefore use the same configuration file; changes made by either application affect that shared file. AirSpace uses its own application identifier (`com.github.shermantsang.airspace`) and the `airspace` command.

## Running alongside AeroSpace

Because AirSpace has its own application identifier, macOS treats it as a separate application: it needs its own Accessibility permission, its own login item, and its own runtime files (`/tmp/com.github.shermantsang.airspace-$USER.sock`). Permissions and login items granted to AeroSpace are not inherited.

Only one tiling window manager should manage windows at a time. Quit AeroSpace before starting AirSpace (and vice versa); both running at once means both apps rearrange the same windows. AirSpace detects a running AeroSpace at startup and shows a warning instead of silently fighting over your windows.

## Development

See [development instructions](./dev-docs/development.md) for setup, building and testing. AirSpace runs on macOS 13 or later.

## Upstream references

AirSpace derives from AeroSpace. The upstream [guide](https://nikitabobko.github.io/AeroSpace/guide), [command reference](https://nikitabobko.github.io/AeroSpace/commands), and [goodies](https://nikitabobko.github.io/AeroSpace/goodies) describe AeroSpace and may differ from AirSpace. The upstream project can be supported through [GitHub Sponsors](https://github.com/sponsors/nikitabobko).
