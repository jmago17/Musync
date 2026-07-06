# Habilitar MusicKit para MusicSync

Para que la app pueda leer el catálogo y escribir en tu biblioteca de Apple Music,
el **App ID** debe tener el servicio **MusicKit** habilitado. MusicKit no es una
"capability" con entitlement ni fichero: es un **App Service** que se activa en el
portal de Apple Developer, y el token de desarrollador lo emite Apple
automáticamente en tiempo de ejecución (no hay que generar ni firmar ninguna clave,
a diferencia de MusicKit JS para web).

- **Bundle ID:** `com.jmago17.MusicSync`
- **Cuenta:** jmago17 (Apple Developer Program de pago — requerido)
- **Requiere** un dispositivo con **suscripción activa a Apple Music** para probar
  (sobre todo la escritura en biblioteca). El simulador no autoriza MusicKit de
  forma fiable → probar en iPhone/iPad real.

---

## 1. Habilitar MusicKit en el App ID (portal)

1. Entra en <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Si el App ID no existe aún:
   - Pulsa **+** → **App IDs** → **App** → **Continue**.
   - **Description:** MusicSync · **Bundle ID:** *Explicit* → `com.jmago17.MusicSync`.
3. Abre el App ID `com.jmago17.MusicSync` para editarlo.
4. Baja a la sección **App Services** (no "Capabilities") y marca **MusicKit**.
5. **Save**. Confirma el diálogo.

> Nota: MusicKit vive en *App Services*, no en *Capabilities*. Por eso **no**
> aparecerá como fila en la pestaña "Signing & Capabilities" de Xcode ni añade un
> `.entitlements`. Se activa aquí, en el servidor.

### Alternativa por CLI (asc)
Tienes el `asc` CLI y la skill `asc-signing-setup`. Puede registrar el bundle ID y
gestionar capabilities/firmado; usa la skill si prefieres no tocar el portal a mano.
(La activación de MusicKit como App Service puede requerir el portal si `asc` no la
expone.)

---

## 2. Firmar la app en Xcode

El proyecto está generado "pelado" (con el gem `xcodeproj`), sin equipo de firma.

1. Abre `~/Documents/Developer/MusicSync/MusicSync.xcodeproj` en Xcode.
2. Target **MusicSync** → **Signing & Capabilities**:
   - **Team:** tu equipo (jmago17).
   - **Automatically manage signing:** ✔.
3. Xcode regenerará el provisioning profile incluyendo el servicio MusicKit del App
   ID. Si acabas de marcar MusicKit en el paso 1, puede que tengas que:
   - Cambiar el Team a otro y volver, o
   - **Product → Clean Build Folder**, o
   - Xcode → Settings → Accounts → **Download Manual Profiles**,
   para forzar que baje el profile actualizado.

> Para fijarlo sin abrir Xcode: en el `.pbxproj`, `DEVELOPMENT_TEAM = <TEAMID>` y
> `CODE_SIGN_STYLE = Automatic` en las build configurations del target.

---

## 3. Info.plist

Ya está puesto en el proyecto:

- `NSAppleMusicUsageDescription` = "MusicSync sincroniza playlists públicas en tu
  biblioteca de Apple Music." (via `INFOPLIST_KEY_NSAppleMusicUsageDescription`).

No hace falta nada más en el plist.

---

## 4. Ejecutar y probar

1. Conecta el iPhone/iPad (con sesión Apple ID **suscrita a Apple Music**).
2. Selecciona el dispositivo como destino y **Run**.
3. Al primer arranque la app llama a `MusicAuthorization.request()` → concede acceso.
4. Prueba una sincronización de una playlist. Si escribe en tu biblioteca, MusicKit
   está bien configurado.

---

## 5. Troubleshooting

- **401 / 403 en peticiones al catálogo o `/me/library`** → el token de
  desarrollador no se emitió: normalmente el App ID **no** tiene MusicKit habilitado,
  o el provisioning profile está cacheado sin el servicio. Revisa el paso 1 y
  regenera el profile (paso 2).
- **`MusicAuthorization` devuelve `.denied`** → Ajustes → MusicSync → activar Apple
  Music; o el Apple ID no tiene suscripción.
- **Funciona en device pero no en simulador** → esperado; MusicKit en simulador es
  poco fiable. Usa hardware real.
- **La escritura falla pero la lectura va** → casi siempre falta la suscripción
  activa (la biblioteca personal la exige).

---

## 6. Distribución (App Store / TestFlight)

- Crea el registro de la app en **App Store Connect** con el mismo bundle ID
  (tienes el `asc` CLI + skills `asc-*` para esto).
- El App ID ya lleva MusicKit, así que los builds firmados para distribución lo
  incluyen automáticamente.

---

## Contexto

Esta app reemplaza el CLI `~/bin/apple-music-sync` (que hacía hacks del web player:
JWT `AMPWebPlay` scrapeado + `media-user-token` pegado a mano). MusicKit elimina
todo eso: los tokens los gestiona el framework una vez el App ID tiene MusicKit.
Ver el plan de migración en la nota "Servicios 24/7 del Mac mini".
