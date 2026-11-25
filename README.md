# Needle — Lock Screen Synced Lyrics (*Stars*)

Minimalista y 100% privada para **macOS** y **Windows 10/11**: muestra las letras sincronizadas de **Spotify** como constelaciones orgánicas palabra por palabra (*Stars*) sobre la **portada del álbum a pantalla completa**, directamente al bloquear tu computadora.

## Privacidad

- **Sin telemetría, sin cuentas, sin cámara, sin ubicación y sin captura de audio/pantalla.**
- **Sin login ni app de Spotify Developer:** lee Spotify localmente (Apple Events en macOS, SMTC nativo en Windows).
- **Tráfico de red estrictamente limitado a:**
  1. `https://lrclib.net/api/get` y `/api/search` (solo título, artista, álbum y duración).
  2. La URL pública de la portada del álbum provista por Spotify (en macOS; en Windows SMTC entrega la portada localmente).

---

## Instalación rápida desde GitHub Releases

Al subir un tag (por ejemplo `git tag v1.0.0 && git push --tags`) o ejecutar el workflow **Build & Release Needle** en *Actions*, GitHub compila y publica ambos ejecutables listos para usar:

### macOS (`Needle-macOS.zip` — Apple Silicon, macOS 14+)
1. Descomprime `Needle-macOS.zip` y arrastra `Needle.app` a **Aplicaciones**.
2. Ábrela (si macOS avisa por no estar firmada con Apple Developer, haz clic derecho → **Abrir** o ejecuta `xattr -cr /Applications/Needle.app`).
3. Corre silenciosa en la barra de menú (`✨`): acepta el permiso de Automatización para Spotify y bloquea con **`Ctrl + Cmd + Q`** mientras suena música.
4. En el menú `✨` puedes ajustar cuánto tiempo mantener la pantalla encendida al bloquear (*5 min* por defecto; cerrar la tapa siempre suspende el Mac normalmente).

### Windows 10 / 11 (`Needle.scr` — 64-bit, autocontenido)
1. Descarga `Needle.scr` (no requiere instalar .NET).
2. Haz clic derecho sobre `Needle.scr` → **Instalar** (si SmartScreen pregunta la primera vez, elige *Más información → Ejecutar de todas formas*).
3. En la ventana de **Configuración del protector de pantalla** que abre Windows, marca **"Mostrar la pantalla de inicio de sesión al reanudar"** y elige el tiempo de espera.

---

## Compilar localmente

### macOS
```bash
# Pruebas unitarias (27 tests)
swift run NeedleCoreTests

# Compilar y empaquetar build/Needle.app
./scripts/build-app.sh
open build/Needle.app
```

> **Opcional (macOS):** para mantener el permiso de Automatización de Spotify entre recompilaciones, crea un certificado local autofirmado `Needle Local` de *Firma de código* en Acceso a Llaveros y compila con:
> `CODESIGN_IDENTITY="Needle Local" ./scripts/build-app.sh`

### Windows (PowerShell + .NET 8 SDK)
```powershell
# Ejecuta xUnit tests y genera windows\dist\Needle.scr (autocontenido)
.\windows\build-windows.ps1
```
