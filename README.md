# Needle (macOS Lock Screen Lyrics)

Minimalista y 100% privada: muestra las letras sincronizadas de **Spotify** como constelaciones palabra por palabra (*Stars*) con la paleta de colores de la portada del álbum directamente en la pantalla de bloqueo de macOS.

## Privacidad

- **Sin telemetría, sin cuentas, sin cámara, sin ubicación y sin captura de audio/pantalla.**
- **Tráfico de red estrictamente limitado a:**
  1. `https://lrclib.net/api/get` y `/api/search` (solo título, artista, álbum y duración).
  2. La URL pública de la portada del álbum provista por Spotify.
- **Permiso único:** Automatización de macOS para leer el estado local de Spotify (sin OAuth ni app en Spotify Developer).

## Compilar y ejecutar

```bash
# Ejecutar pruebas unitarias
swift run NeedleCoreTests

# Compilar y empaquetar build/Needle.app
./scripts/build-app.sh

# Abrir la app (aparece un ícono de destello en la barra de menú)
open build/Needle.app
```

## Opcional: mantener el permiso de Spotify entre compilaciones

Por defecto `./scripts/build-app.sh` firma con firma ad-hoc (`-`), lo que hace que macOS vuelva a pedir el permiso de Automatización de Spotify al recompilar. Si quieres evitarlo:

1. Abre **Acceso a Llaveros (Keychain Access)** → *Acceso a Llaveros → Asistente para Certificados → Crear un certificado…*
2. Nombre: `Needle Local`, Tipo de identidad: *Raíz autofirmada*, Tipo de certificado: **Firma de código (Code Signing)**.
3. Compila usando:
   ```bash
   CODESIGN_IDENTITY="Needle Local" ./scripts/build-app.sh
   ```
