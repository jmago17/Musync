# Sincronización e integridad

MusicSync mantiene iOS 18 como mínimo. La resolución entre regiones usa equivalencias oficiales antes de ISRC, ID directo y coincidencia estricta de título/artista. En iOS 27 usa `findEquivalents` con `item(for:)`; en versiones anteriores usa REST `filter[equivalents]` y el mapa `meta.filters.equivalents`. El orden de una respuesta no establece correspondencia con el orden solicitado. Las peticiones de equivalencias se agrupan en lotes de 100.

- [Equivalencias REST](https://developer.apple.com/documentation/applemusicapi/get-equivalent-ids-for-the-albums-3ce20)
- [findEquivalents, iOS 26.4](https://developer.apple.com/documentation/musickit/musiccatalogresourcerequestoption/findequivalents)
- [item(for:), iOS 27](https://developer.apple.com/documentation/musickit/musiccatalogresourceresponse/item(for:))

Reemplazar conserva orden y repeticiones, y exige que todas las canciones estén resueltas y disponibles antes de editar. Añadir deduplica por ID de catálogo. Una lectura parcial, un destino ambiguo o una preparación cuyo origen/región ha cambiado bloquea la escritura. Los errores de autorización o red no se interpretan como ausencia de canción. Solo GET reintenta 429/5xx, hasta tres intentos.

## Persistencia y recuperación

`state-v1.json` agrupa fuentes, historial, preparaciones, propiedad de playlists y recibos pendientes. Migra los ficheros anteriores al escribir por primera vez, sin borrarlos. Un fichero corrupto produce error visible en vez de restablecer valores por defecto. Un bloqueo de archivo serializa las transacciones y otro impide solapar operaciones UI/App Intents entre procesos.

La creación guarda intención antes del POST y después guarda el ID obtenido hasta que el consumidor lo incorpora a su estado. El primer sync crea vacío y guarda el destino antes de llenarlo. Si ese destino devuelve 404, se espera o se pide elegir otro explícitamente: no se crea una copia ante posible visibilidad tardía. La adopción conserva también su destino y canciones pendientes para reanudar sobre la misma playlist.

Append registra cada lote antes del POST. Un rechazo definitivo libera ese lote; una respuesta perdida mantiene el recibo. Antes de reintentar, una lectura completa debe confirmar que todos los IDs pendientes ya están presentes. Esto también protege frente a visibilidad tardía tras un POST reconocido. No se promete entrega exactamente una vez: si la creación pierde su respuesta, el usuario debe comprobar la biblioteca y seleccionar el destino existente; no se repite automáticamente una creación ambigua. Si un append incierto no llega a confirmarse, se bloquea de forma conservadora en lugar de duplicar canciones.

`MusicLibrary.edit` sigue limitado por Apple a playlists creadas por la app. El registro local es una pista de procedencia; la autorización efectiva la decide MusicKit. Una playlist ajena sigue usando append y muestra sobrantes para limpieza manual.

## Validación sin biblioteca real

Desde la raíz:

```sh
swift test --jobs 2
xcodebuild -project MusicSync.xcodeproj -scheme MusicSync -configuration Debug \
  -destination 'generic/platform=iOS' -jobs 2 CODE_SIGNING_ALLOWED=NO build
```

El paquete de pruebas compila únicamente el núcleo e inyecta clientes simulados. Cubre equivalencias, orden/repeticiones, catálogo parcial, duplicados en append, errores y cancelación, retry GET, recibos tras reinicio, persistencia atómica, preparación obsoleta y un editor abierto mientras un atajo guarda nuevos datos. No autoriza ni escribe en Apple Music.

Queda QA en dispositivo con datos desechables y autorización específica: ramas REST/nativa, biblioteca con más de 100 playlists, visibilidad tardía, pérdida de conexión tras POST y UI/Atajos concurrentes. La compilación sin firma no valida provisioning, servicio MusicKit del App ID ni suscripción.
