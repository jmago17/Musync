# Musync Worker

Cron en Cloudflare que lee playlists del catálogo de Apple Music (storefront origen, p. ej. `es`),
resuelve su equivalente oficial en el destino (`us`, `filter[equivalents]`, con ISRC como respaldo) y publica un JSON para un Atajo.

## Endpoints (todos con `Authorization: Bearer <API_TOKEN>`)
- `PUT /v1/config` `{"playlists":["https://music.apple.com/es/playlist/.../pl.xxx", {"url":"...","target":"us"}]}`
- `GET /v1/playlists` índice · `GET /v1/playlists/pl.xxx` JSON completo (songs, added, removed, notFound)
- `POST /v1/run[?id=pl.xxx]` ejecuta ya · `GET /v1/status` última ejecución

## Despliegue
1. `wrangler kv namespace create MUSYNC` y pegar el id en `wrangler.toml`.
2. Secrets: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (contenido del .p8), `API_TOKEN`.
3. `wrangler deploy`.

## Tests
`npm test` (Node ≥ 20, sin dependencias).
