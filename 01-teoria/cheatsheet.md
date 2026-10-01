# Cheatsheet — Rompiendo Apps Android

Referencia rápida de campo. **Protección → síntoma → comando → plan B → techo.**
Destino en el repo: `01-teoria/cheatsheet.md`. Fuente: `parte3_avanzado.md`.

> **Cómo usar:** buscá la protección por el síntoma que ves. Probá el **comando principal**; si no
> cae, bajá al **plan B**. Si aparece el **techo**, dejá de insistir del lado del cliente y pivoteá a
> la API. Reemplazá `com.pkg` por el package real y `app.apk` por tu archivo.

---

## 0. Preparación (una vez)

```bash
adb devices                         # ¿ve el device/emulador?
# frida-server en el device (con root):
adb push frida-server /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/frida-server"
adb shell su -c "/data/local/tmp/frida-server &"
frida-ps -U                         # lista procesos → confirma que Frida conecta
```

Herramientas base: `jadx-gui`, `apktool`, `frida`, `objection`, Burp Suite, `adb`, `scrcpy`.
Ver la **matriz completa de herramientas** al final.

---

## 1. Diagnóstico PRIMERO (siempre, antes de tirar hooks)

```bash
apkid app.apk                       # packer / obfuscator / RASP: ¿contra qué peleás?
apkleaks -f app.apk                 # URLs, endpoints, secrets embebidos
jadx-gui app.apk                    # leer código, buscar los checks
apktool d app.apk -o app_src        # recursos + smali + manifest (para editar/rebuild)
# MobSF (recon automatizado, SAST):
docker run -it --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf
```

> Regla: identificá el RASP/packer **antes** de instrumentar. Pelear a ciegas es perder la tarde.

---

## 2. No instala (empaquetado, no protección)

| Síntoma (error) | Causa | Fix |
|---|---|---|
| `INSTALL_FAILED_OLDER_SDK` | minSdk > API del emulador | editar minSdk → rebuild → re-firmar |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | libs ARM, emulador x86 | imagen **arm64** o device físico |
| `INSTALL_FAILED_INVALID_APK` | app partida (split/AAB) | `adb install-multiple` |
| falla firma en device nuevo | requiere v2/v3 | re-firmar con `apksigner` |

```bash
adb install app.apk
adb install-multiple base.apk split_config.*.apk        # apps partidas
# bajar minSdk:
apktool d app.apk -o src
sed -i 's/^  minSdkVersion:.*/  minSdkVersion: '\''21'\''/' src/apktool.yml
apktool b src -o new.apk
# re-firmar (elegí una):
apksigner sign --ks my.keystore new.apk
java -jar uber-apk-signer.jar -a new.apk                 # más simple, genera keystore
```

**Techo:** el ABI (arm vs x86) no se edita; cambiás de entorno (emulador arm64 o device físico).

---

## 3. Detección de root

**Síntoma:** instala, pero al abrir se cierra / muestra "device rooteado".
```bash
objection -g com.pkg explore
#   dentro de objection:  android root disable
frida -U -f com.pkg -l anti-root.js --no-pause
```
**Plan B — esconder el root sin tocar la app:** Magisk → **DenyList** ON + **Zygisk** ON + módulo **Shamiko**. Ocultar la app de Magisk. Alternativas: `zygisk-assistant`, Hide My Applist.
**Plan C — check nativo (`.so`):** hookear la función nativa con Frida (`Interceptor.attach(Module.findExportByName('librootbeer.so', ...))`) o parchear el `.so`.
**Techo:** si el "root check" es en realidad **Play Integrity server-side** → ver §14.

---

## 4. Detección de emulador

**Síntoma:** anda en device pero se cierra en Genymotion / AVD.
```bash
frida -U -f com.pkg -l anti-emulator.js --no-pause    # hook Build.*, SystemProperties.get, File.exists
```
**Plan B — spoof de props (device con Magisk):** `resetprop` / módulo **MagiskHideProps Config** para poner props "de fábrica".
**Plan A limpio:** **device físico** → mata casi todos los checks de una.
**Techo:** RASP que combina decenas de señales → device físico.

---

## 5. Anti-debugger

**Síntoma:** se cierra al conectar debugger; `TracerPid` ≠ 0.
```bash
frida -U -f com.pkg -l anti-debug.js --no-pause
#   hook Debug.isDebuggerConnected → false
#   falsear TracerPid (/proc/self/status)
#   neutralizar ptrace(PTRACE_TRACEME) en libc
```
**Plan B:** objection (hooking de clases de debug).
**Techo:** ninguno serio; es de los más fáciles (buena rampa antes del pinning).

---

## 6. No confía en tu CA (Network Security Config)

**Síntoma:** prendés Burp y la app da **error de certificado** (distinto del error de red del pinning).
```bash
# Sin root — reescribe NSC + re-firma automático:
apk-mitm app.apk
# Manual:
apktool d app.apk -o src
#   editar src/res/xml/network_security_config.xml → <certificates src="user"/>
apktool b src -o new.apk && apksigner sign --ks my.keystore new.apk
```
**Plan B — con root:** instalar la CA de Burp como **system cert** (módulo Magisk `MagiskTrustUserCerts` / "Move Certificates", o montar en `/system/etc/security/cacerts`).
**Techo:** ninguno; es el paso previo al pinning.

---

## 7. Certificate pinning ⭐ (el gran obstáculo del tráfico)

**Síntoma diagnóstico:** en Burp ves el intento de conexión pero la app da **error de red / "sin conexión"** (NO error HTTP). Eso = pinning.

**Genéricos — probar EN ORDEN (de barato a caro):**
```bash
objection -g com.pkg explore        # dentro:  android sslpinning disable
frida -U -f com.pkg -l frida-multiple-unpinning.js --no-pause
apk-mitm app.apk                    # sin root: reescribe NSC + re-firma
reflutter app.apk                   # apps Flutter
```

**Según dónde vive el pinning:**
| Stack | Cómo detectarlo | Bypass |
|---|---|---|
| OkHttp `CertificatePinner` | strings `sha256/` en JADX | objection / frida-multiple-unpinning |
| `TrustManager` / Conscrypt | `checkServerTrusted` custom | frida-multiple-unpinning (lo cubre) |
| Network Security Config | `<pin-set>` en el XML | editar NSC + re-firmar / apk-mitm |
| **Nativo `.so` (BoringSSL)** | no cae con scripts Java | hook nativo Frida (`SSL_CTX_set_custom_verify`, `SSL_get_verify_result`) / parchear `.so` |
| **Flutter** (`libflutter.so`) | hay `libflutter.so` en `lib/` | **reFlutter** / hook `ssl_verify` por offset |
| Xamarin / .NET | `libmonodroid` | hook stack mono / ServicePointManager |
| React Native | `index.android.bundle` | como OkHttp (objection/frida) |

**5 caminos para el mismo problema:** objection ↔ frida-multiple-unpinning ↔ medusa ↔ house ↔ apk-mitm (sin root).
**Techo:** pinning nativo/Flutter no cae con scripts Java → hook nativo o reFlutter (sube de nivel, pero cae).

---

## 8. mTLS (certificado de cliente)

**Síntoma:** pasaste el pinning, pero el server **rechaza tu conexión** (te pide cert a vos).
```bash
# extraer el client cert del APK:
unzip app.apk -d out
find out \( -name '*.p12' -o -name '*.pfx' -o -name '*.bks' \)
#   buscar la passphrase en el código/strings (JADX)
# cargarlo en Burp:
#   Settings → TLS → Client Certificates → agregar el .p12 + passphrase, para el host objetivo
```
**Plan B — cert en KeyStore:** hookear con Frida `KeyStore.getEntry`, `SSLContext.init`, `KeyManagerFactory`.
**Techo:** clave privada en **StrongBox/TEE** (HW) no sale en claro → no la extraés (§14/§15).

---

## 9. Payload cifrado / firmado

**Síntoma:** capturás la petición pero el **body es ilegible** (AES) o tiene una firma (HMAC) que no reproducís.
```bash
frida -U -f com.pkg -l crypto-hook.js --no-pause
#   hook Cipher.doFinal, Mac.doFinal, Signature, SecretKeySpec
#   → leer plaintext antes de cifrar + descifrar respuestas + volcar la clave
```
**Plan B — Brida** (puente Burp↔Frida): llamás a las funciones de cripto de la app desde Burp → fuzzeás la API con el cifrado correcto.
**Techo:** white-box crypto (clave nunca en claro en memoria) → §15.

---

## 10. Integridad / anti-tamper

**Síntoma:** el repackaging se detecta y la app se cierra ("firma inválida").
```bash
# PREFERIR runtime (no modificás el APK → no hay nada que detectar):
frida -U -f com.pkg -l anti-tamper.js --no-pause
#   hook del check de firma (PackageManager GET_SIGNING_CERTIFICATES) → "intacta"
#   falsear getInstallerPackageName → "com.android.vending"
```
**Regla:** anti-tamper y repackaging son **enemigos**. Con anti-tamper presente → runtime, no repack.
**Techo:** ninguno absoluto; complica el repackaging, no el runtime.

---

## 11. Ofuscación

**Síntoma:** clases `a`, `b`, `c`; strings cifrados; flujo enredado.
```bash
# Packers (DEX cifrado en memoria) → volcar el DEX ya descifrado:
frida-dexdump -U -f com.pkg
fridump -U com.pkg                  # alternativa
# DexGuard (strings cifrados) → ver el descifrado en runtime:
frida-trace -U -f com.pkg -j '*!*decrypt*'
```
**Idea fuerza:** *el runtime no miente.* La ofuscación encarece el estático, no el dinámico → Frida.
**Nativo (OLLVM):** Ghidra/radare + dinámico; angr (symbolic execution) para casos puntuales.

---

## 12. Anti-instrumentación (anti-Frida) 🥊

**Síntoma:** Frida conecta pero la app se cierra apenas enganchás.
```bash
# frida-server en puerto NO default:
adb shell su -c "/data/local/tmp/frida-server -l 0.0.0.0:9999 &"
frida -H 127.0.0.1:9999 -f com.pkg --no-pause
# + renombrar el binario y sacarlo de /data/local/tmp
```
**Plan B:** **gadget embebido** (Frida Gadget dentro del APK) → sin frida-server corriendo.
**Plan C:** Magisk (Zygisk + módulos anti-detección de Frida); parchear cada detección (hook a `open`/`read` de `/proc/self/maps`, a `strstr`, al escaneo de puertos).
**Plan D — cambiar de motor:** si detecta solo Frida → Xposed/LSPosed, o r2frida.
**Realidad:** gato-y-ratón; cada release del RASP rompe bypasses.

---

## 13. RASP comercial (el jefe de nivel)

**Síntoma:** todas las protecciones anteriores juntas, coordinadas, en runtime.
```bash
apkid app.apk        # identificar el producto (clave)
```
| Producto | Se reconoce por |
|---|---|
| Appdome | libs/strings `libappdome*`; **el más estudiado** (no-code → bypasses compartidos) |
| Guardsquare | DexGuard/iXGuard, `libdexguard*` |
| Promon SHIELD | `libshield*`; banca, muy agresivo |
| Digital.ai (Arxan) / Zimperium | libs propias |

**Respuesta escalonada:**
1. Buscar **bypass conocido** del producto (Appdome primero).
2. Anti-anti-Frida (§12) + paciencia.
3. **Pivote:** aunque no rompas el RASP, si proxeás un momento (device stock, cert extraído), **la API está del otro lado y el RASP no la protege**.
4. **Declararlo:** "protección del cliente bien implementada" **es** un hallazgo válido.

**Techo:** costo altísimo; la pregunta correcta es *¿me alcanza el tiempo?* → pivote a la API.

---

## 14. Play Integrity / attestation (barrera dura)

**Síntoma:** ningún hook local cambia el resultado; el veredicto lo valida el server.
```text
NO se hookea desde el cliente: el veredicto lo firma el HW y lo valida el server de Google.
```
**Dónde SÍ hay bugs (atacar la implementación, no el chip):**
- Server que **no valida el nonce** → replay de un veredicto válido.
- Acepta veredictos **vencidos** o de **otro package**.
- Check **local "de respaldo"** además del server → ese sí se hookea.

Spoofers a nivel ROM (Play Integrity Fix + módulos) existen pero son **efímeros** (Google los cierra).
**Techo:** Play Integrity bien implementado (validado en server) no cae desde el cliente.

---

## 15. El techo real — lo que NO cae desde el cliente

```text
· Play Integrity validado en server (veredicto firmado por HW)
· White-box crypto (la clave nunca aparece en claro en memoria)
· mTLS con clave en StrongBox / TEE
· Decisión 100% server-side
```
**El pivote:** "inatacable desde el cliente" ≠ "sin bugs". La lógica se muda al server → fallas de
implementación: **replay de nonce · tokens vencidos · IDOR/BOLA · mass assignment**.
→ **El techo del bypass del cliente es el piso del ataque a la API.**

---

## 16. Matriz de herramientas (nunca una sola opción)

| Necesidad | Principal | Alternativas |
|---|---|---|
| Decompilar/leer DEX | **JADX** | Bytecode Viewer, Procyon, CFR |
| Recursos/manifest + rebuild | **apktool** | APKEditor, APKLab (VSCode) |
| Reversing nativo (`.so`) | **Ghidra** | radare2/Cutter, IDA, Binary Ninja |
| Identificar packer/RASP | **apkid** | detect-it-easy, manual (strings/libs) |
| Extraer URLs/secrets | **apkleaks** | MobSF, trufflehog, grep+regex |
| SAST móvil | **MobSF** | semgrep (reglas mobile), QARK |
| Instrumentación runtime | **Frida** | Xposed/LSPosed, r2frida |
| Frida "enlatado" (comandos) | **objection** | medusa, house, RMS |
| Puente proxy↔instrumentación | **Brida** | scripts propios Frida+mitmproxy |
| Volcar DEX de memoria (packers) | **frida-dexdump** | fridump, dump manual |
| Proxy HTTP(S) | **Burp Suite** | mitmproxy, Caido, ZAP |
| Sin root: pinning + re-sign | **apk-mitm** | objection patchapk, manual apktool |
| Firmar APK | **apksigner** | uber-apk-signer, zipalign+apksigner |
| Esconder root | **Magisk** (DenyList/Zygisk/Shamiko) | KernelSU, APatch |
| Apps Flutter | **reFlutter** | Frida + offsets de libflutter |
| Device/logs/control | **adb** + logcat + **scrcpy** | Android Studio, Genymotion |

---

## 17. Ruta sin root (resumen rápido)

```bash
apk-mitm app.apk                    # NSC + pinning bypass + re-sign en un paso
# o manual:
objection patchapk -s app.apk       # inyecta Frida gadget → instrumentás sin root
apktool d app.apk -o src && ...     # editar NSC / smali → rebuild → apksigner
```
Sin root perdés: esconder root a nivel sistema, hooks que necesitan frida-server, ver StrongBox.
Ganás: reproducibilidad, funciona en device stock.

---

> **Método invariante (para todo):** protección = decisión = valor. Ubicá el check → mirá qué
> devuelve → quién lo consume → observá o modificá. Probá lo barato primero; escalá solo si falla;
> sabé cuándo parar y pivotear a la API.
