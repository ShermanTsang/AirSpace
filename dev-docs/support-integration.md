# Support Integration

AirSpace uses the iChaseU walnut portal for in-app help, announcements, agreements, contact channels, and update checks. The integration is read-only and anonymous; it does not use user accounts, JWT, or device sessions.

## Client

`Sources/AppBundle/network/WalnutClient.swift` calls the public portal API:

| Feature | Endpoint |
| --- | --- |
| Help documents | `GET /portal/docs`, `GET /portal/doc/:slug` |
| Announcements | `GET /portal/activities`, `GET /portal/activity/:slug` |
| Agreements | `GET /portal/agreements`, `GET /portal/agreement/:slug` |
| Contact channels | `GET /portal/contacts` |
| Update check | `GET /portal/releases/check` |

Every request sends:

- `X-App-Code: air-space`
- `X-Platform: macos`
- `X-Locale` and `Accept-Language`: `zh-CN` or `en`

The default base URL is `https://walnut.ichaseu.com`. Set `WALNUT_BASE_URL` in the environment to point a development build at another gateway.

The gateway serialises portal responses in snake_case. `WalnutClient` uses `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`; do not remove it.

## Update check

The client sends its current integer version code. The update endpoint returns `available: false` until a release has been registered with the portal. Release registration is separate from publishing the GitHub Release and requires a signed manifest; see [release.md](./release.md#portal-version-code).

## UI

`Sources/AppBundle/ui/support/SupportWindow.swift` contains the Support window. The menu bar panel exposes it through **Help & Support** and **Check for Updates**. The window is opened by the `supportView` scene declared in `Sources/AirSpaceApp/AirSpaceApp.swift`.

## Platform data

The portal identifies the app by `app_code = air-space` under `org_code = ichaseu`. The current registration has:

- an active `app` row with login and registration disabled;
- zh-CN and en `app_profile` rows;
- a `getting-started` document in both locales;
- a GitHub Issues contact channel in both locales.

Agreements are platform content. Templates that are not bound to any app are visible to every app, so AirSpace currently sees the generic iChaseU agreement templates. To show only AirSpace-specific terms, publish and bind separate templates in the portal admin instead of filtering them in the client.

The portal admin has an `app.air-space` permission node under `app-scope`. Assign it to non-super-admin roles and refresh the admin permission cache before those roles can manage AirSpace data.

## Current decisions

- **Agreements:** keep the platform default for now. The Agreements tab shows the unbound iChaseU templates until AirSpace-specific templates are published and bound.
- **Release source:** not registered yet. Update checks therefore return `available: false`; register `app_release_source` and publish signed manifests when the release pipeline is ready.
