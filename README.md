# Needle — Lock Screen Synced Lyrics (*Stars*)

Minimalista y 100% privada para **macOS** y **Windows 10/11**: muestra las letras sincronizadas de **Spotify** como constelaciones orgánicas palabra por palabra (*Stars*) sobre la **portada del álbum a pantalla completa**, directamente al bloquear tu computadora.

## Privacidad

- **Sin telemetría, sin cuentas, sin cámara, sin ubicación y sin captura de audio/pantalla.**
- **Sin login ni app de Spotify Developer:** lee Spotify localmente (Apple Events en macOS, SMTC nativo en Windows).
- **Tráfico de red estrictamente limitado a:**
  1. `https://lrclib.net/api/get` y `/api/search` (solo título, artista, álbum y duración).
  2. La URL pública de la portada del álbum provista por Spotify (en macOS; en Windows SMTC entrega la portada localmente).

---

## Compilar e instalar

### macOS (Apple Silicon, macOS 14+)
```bash
# Pruebas unitarias (27 tests)
swift run NeedleCoreTests

# Compilar y empaquetar build/Needle.app
./scripts/build-app.sh

# Instalar en Aplicaciones y abrir en segundo plano
cp -R build/Needle.app /Applications/Needle.app
open /Applications/Needle.app
```

- Corre silenciosa en la barra de menú (`✨`): acepta el permiso de Automatización para Spotify y bloquea con **`Ctrl + Cmd + Q`** mientras suena música.
- En el menú `✨` puedes abrir **Vista previa** o ajustar cuánto tiempo mantener la pantalla encendida al bloquear (*5 min* por defecto; cerrar la tapa siempre suspende el Mac normalmente).
- **Opcional:** para mantener el permiso de Automatización de Spotify entre recompilaciones, crea un certificado local autofirmado `Needle Local` de *Firma de código* en Acceso a Llaveros y compila con:
  `CODESIGN_IDENTITY="Needle Local" ./scripts/build-app.sh`

### Windows 10 / 11 (PowerShell + .NET 8 SDK)
```powershell
# Ejecuta tests xUnit y genera windows\dist\Needle.scr (autocontenido, 64-bit)
.\windows\build-windows.ps1
```

1. Haz clic derecho sobre `windows\dist\Needle.scr` → **Instalar**.
2. En la ventana de **Configuración del protector de pantalla** que abre Windows, marca **"Mostrar la pantalla de inicio de sesión al reanudar"** y elige el tiempo de espera.
