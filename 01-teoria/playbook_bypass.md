# Playbook de bypasses — de instalar la APK al proxeo final

**Taller:** Rompiendo apps Android · **Destino en el repo:** `01-teoria/playbook-bypass.md`
**Qué es:** un recorrido **lineal**, de principio a fin, para llevar una APK desde "la quiero instalar" hasta "veo y modifico su tráfico en Burp" — o hasta la conclusión honesta de que **no proxea desde el cliente** y hay que pivotear a la API. En el medio están **todas las instancias donde vive o puede vivir una protección** y las alternativas para pasarla (estáticas, dinámicas, con herramientas), con comandos.
**Cómo se lee:** es un camino con **compuertas (GATE)**. Avanzás de etapa en etapa; en cada obstáculo tenés el diagnóstico, las alternativas ordenadas de barato a caro, y a dónde saltar si algo falla. Complementa al `cheatsheet.md` (que es lookup por protección); esto es el **viaje**.

> Encuadre: testing autorizado (apps propias, labs del taller, bug bounty con alcance). Herramientas y comandos públicos estándar (MASTG/Frida/objection). Reemplazá `com.pkg` por el package real y `app.apk` por tu archivo.

---

## Mapa del recorrido (el viaje completo de un vistazo)

```text
ETAPA 0  Preparar el entorno         → emulador/device + root + frida-server + Burp CA + proxy
   │
ETAPA 1  Instalar la APK             → ¿instala?  no → [empaquetado: minSdk/ABI/splits/firma]
   │                                              sí ↓
ETAPA 2  Abrir la app                → ¿arranca?  se cierra → [root · emulador · debugger · anti-tamper]
   │                                              abre ↓
ETAPA 3  Hacerla hablar (proxy ON)   → ¿veo tráfico? error cert → [user CA / NSC]
   │                                                error red   → [certificate pinning]
   │                                                veo ↓
ETAPA 4  Entender/tocar el tráfico   → ¿puedo leer/modificar? no → [pinning nativo/Flutter · mTLS · payload cifrado]
   │                                                          sí ↓
ETAPA 5  Si TODO se defiende junto   → RASP / anti-Frida coordinado → [anti-anti-Frida o pivote]
   │
ETAPA 6  Estado final                → PROXEO OK → atacás la API
                                        NO PROXEA (server-side/HW) → pivote a la API (el techo del cliente
                                                                      es el piso del ataque a la API)
```

Cada etapa abajo tiene: **objetivo · cómo saber si pasaste la compuerta · las protecciones que pueden aparecer · alternativas + comandos · a dónde saltar.**

---

# ETAPA 0 — Preparar el entorno de ataque

**Objetivo:** tener un device donde puedas instrumentar (root + Frida) y ver el tráfico (Burp con CA confiable). Esto se hace **una vez**; sin esto, nada de lo demás funciona.

## 0.1 Elegir device

| Opción | Root | Cuándo |
|---|---|---|
| **AVD (Android Studio) imagen "Google APIs"** | rooteable (`adb root`) | por defecto para labs; NO uses "Google Play" (no deja root) |
| **AVD + rootAVD** (parchea ramdisk con Magisk) | Magisk completo | cuando necesitás Zygisk/Shamiko/módulos |
| **Genymotion** | root fácil | rápido, cómodo, pero muchos RASP detectan emulador |
| **Device físico rooteado (Magisk)** | Magisk completo | apps con anti-emulador fuerte o RASP |

```bash
# crear/arrancar un AVD por línea de comando (SDK instalado):
sdkmanager "system-images;android-33;google_apis;arm64-v8a"
avdmanager create avd -n lab -k "system-images;android-33;google_apis;arm64-v8a"
emulator -avd lab -writable-system      # -writable-system = clave para instalar la CA en /system
adb devices                             # confirmá que lo ve
```
> **arm64-v8a** de entrada te evita el problema de ABI de la Etapa 1 (apps con libs nativas ARM).

## 0.2 Root + frida-server

```bash
# rootear un AVD estándar (Magisk) con rootAVD:
./rootAVD.sh ListAllAVDs        # y luego el comando que te devuelve para tu AVD
# frida-server (bajá la versión que matchee tu frida y la ABI del device):
adb push frida-server /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/frida-server"
adb shell su -c "/data/local/tmp/frida-server &"
frida-ps -U                     # ✔ si lista procesos, Frida conecta
```

## 0.3 Pushear la CA de Burp (para ver HTTPS)

Android moderno (targetSdk ≥ 24) **ignora las CA de usuario**, así que la CA de Burp tiene que ir como **CA de sistema**.

```bash
# 1) Exportar la CA de Burp:  Burp → Proxy → Options → Import/Export CA cert → DER (cacert.der)
# 2) Convertir a PEM y calcular el nombre hasheado que Android espera:
openssl x509 -inform DER -in cacert.der -out cacert.pem
hash=$(openssl x509 -inform PEM -subject_hash_old -in cacert.pem | head -1)
mv cacert.pem "$hash.0"
# 3) Montar /system escribible y empujarla:
adb root && adb remount                       # AVD Google APIs / -writable-system
adb push "$hash.0" /system/etc/security/cacerts/
adb shell chmod 644 /system/etc/security/cacerts/"$hash.0"
adb reboot
```
**Si /system es de solo-lectura (API 29+):** usá el **módulo Magisk `MagiskTrustUserCerts`** (instalás la CA como user cert desde Ajustes y el módulo la "asciende" a system al bootear), o el truco de remount por tmpfs de la carpeta `cacerts`. Alternativa sin root: **apk-mitm** reescribe la app para que confíe en tu CA (Etapa 3).

## 0.4 Apuntar el tráfico a Burp

```bash
# Proxy global del device hacia tu PC (IP de tu máquina):
adb shell settings put global http_proxy 192.168.1.50:8080
# limpiar cuando termines:
adb shell settings put global http_proxy :0
```
Alternativa: configurar el proxy en la WiFi del emulador (Settings → WiFi → editar → Proxy manual → IP:8080). En Burp: Proxy → Listener en `*:8080` (all interfaces).

**✅ GATE 0 superada cuando:** `frida-ps -U` lista procesos **y** al navegar en el browser del device ves el tráfico HTTPS en Burp sin error de certificado.

---

# ETAPA 1 — Instalar la APK

**Objetivo:** que la app quede instalada. Acá los obstáculos **no son protecciones**, son incompatibilidades de empaquetado. (Distinguir esto de "se cierra al abrir" es medio diagnóstico.)

```bash
adb install app.apk
```

**Si falla, según el error:**

| Error | Causa | Alternativa (comando) |
|---|---|---|
| `INSTALL_FAILED_OLDER_SDK` | minSdk > API del emulador | **estática:** bajar minSdk y rebuild (abajo) |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | libs ARM, emulador x86 | **entorno:** imagen **arm64** o device físico (no se edita) |
| `INSTALL_FAILED_INVALID_APK` / faltan splits | app partida (split/AAB) | `adb install-multiple base.apk split_config.*.apk` |
| falla de firma en device nuevo | requiere esquema v2/v3 | re-firmar con `apksigner` (abajo) |

```bash
# Bajar minSdk (estática):
apktool d app.apk -o src
sed -i "s/^  minSdkVersion:.*/  minSdkVersion: '21'/" src/apktool.yml
apktool b src -o new.apk
# Re-firmar (cualquiera de las dos):
apksigner sign --ks my.keystore new.apk
java -jar uber-apk-signer.jar -a new.apk        # genera keystore solo, más simple
adb install new.apk
```

**Techo de esta etapa:** el **ABI** (arm vs x86) no se edita — cambiás de entorno (emulador arm64 o device físico). Por eso la Etapa 0 recomienda arm64 de entrada.

**✅ GATE 1:** la app aparece instalada (`adb shell pm list packages | grep pkg`). → Etapa 2.

---

# ETAPA 2 — Abrir la app (detección de entorno + integridad)

**Objetivo:** que la app arranque y se quede abierta. Si se **cierra sola** al abrir, hay una protección de entorno. Diagnosticá **primero** contra qué peleás:

```bash
apkid app.apk                 # ¿packer / RASP / obfuscator?  (clave: no pelees a ciegas)
jadx-gui app.apk              # buscar en el código: "root", "emulator", "debug", "signature", "tamper"
```

Ahora, según qué check dispara (pueden ser varios a la vez):

## 2.A Detección de root
**Síntoma:** "dispositivo rooteado" / cierre inmediato.
- **Dinámica (rápida):** `objection -g com.pkg explore` → `android root disable`
- **Dinámica a medida:** `frida -U -f com.pkg -l anti-root.js --no-pause` (hook `File.exists`, `Runtime.exec`, `PackageManager.getPackageInfo`, métodos de RootBeer)
- **Esconder el root (sin tocar la app):** Magisk → **DenyList** + **Zygisk** + **Shamiko**; ocultar la app de Magisk
- **Estática (sin root):** editar el smali del check → retornar "no rooteado" → rebuild + re-firmar (⚠ choca con anti-tamper, ver 2.D)
- **Check nativo (`librootbeer.so` / propio):** `Interceptor.attach(Module.findExportByName('lib...so', ...))` o parchear el `.so`
- **Techo:** si es **Play Integrity server-side** → Etapa 6.

## 2.B Detección de emulador
**Síntoma:** anda en físico, se cierra en AVD/Genymotion.
- **Limpia:** **device físico** (mata casi todo de una)
- **Dinámica:** `frida -U -f com.pkg -l anti-emulator.js --no-pause` (hook `Build.*`, `SystemProperties.get`, `File.exists`)
- **Spoof de props (Magisk):** `resetprop` / módulo **MagiskHideProps Config** → props "de fábrica"

## 2.C Anti-debugger
**Síntoma:** `TracerPid` ≠ 0 / se cierra con debugger.
- **Dinámica:** `frida -U -f com.pkg -l anti-debug.js --no-pause` (hook `Debug.isDebuggerConnected`, falsear `/proc/self/status`, neutralizar `ptrace`)
- De los más fáciles; buena rampa antes del pinning.

## 2.D Integridad / anti-tamper
**Síntoma:** si **repackageaste**, se cierra con "firma inválida".
- **Regla:** con anti-tamper presente, **usá runtime (Frida), no repackaging** — si no modificás el APK, no hay firma que detectar.
- **Dinámica:** `frida -U -f com.pkg -l anti-tamper.js --no-pause` (hook del check de firma `PackageManager GET_SIGNING_CERTIFICATES`; falsear `getInstallerPackageName` → `com.android.vending`)

**✅ GATE 2:** la app abre y se queda abierta con Frida enganchado. → Etapa 3.
**Si se cierra apenas enganchás Frida** (no por root/emu): es **anti-instrumentación** → saltá a **Etapa 5**.

---

# ETAPA 3 — Hacerla hablar (proxy ON, primer tráfico)

**Objetivo:** ver las peticiones de la app en Burp. Con el proxy apuntado (Etapa 0.4), abrí la app y mirá Burp. El **síntoma diferencia la protección**:

```text
¿Qué ves en Burp al usar la app?
├─ Nada, ni intento           → el proxy no está aplicado (revisar 0.4 / WiFi proxy / firewall)
├─ Intento + ERROR DE CERT    → no confía en tu CA           → 3.A (user CA / NSC)
├─ Intento + ERROR DE RED     → certificate pinning          → 3.B
└─ Peticiones visibles ✅      → pasaste; ¿las entendés?      → Etapa 4
```

## 3.A No confía en tu CA (user CA / Network Security Config)
**Síntoma:** error de **certificado** (no de red).
- **Con root:** ya lo resolviste en Etapa 0.3 (CA como system cert). Si igual falla, la app tiene un **NSC restrictivo** (`src="system"` explícito o `<pin-set>`).
- **Estática (editar NSC):**
```bash
apktool d app.apk -o src
#   editar src/res/xml/network_security_config.xml → agregar <certificates src="user"/>
apktool b src -o new.apk && apksigner sign --ks my.keystore new.apk && adb install -r new.apk
```
- **Sin root, automatizado:** `apk-mitm app.apk` (reescribe el NSC + re-firma en un paso)

## 3.B Certificate pinning ⭐ (el gran obstáculo)
**Síntoma diagnóstico:** la app **intenta** conectarse pero da **error de red / "sin conexión"** — NO error HTTP, NO error de cert. Eso es pinning.

**Genéricos — probar EN ORDEN (barato → caro):**
```bash
objection -g com.pkg explore              # dentro:  android sslpinning disable
frida -U -f com.pkg -l frida-multiple-unpinning.js --no-pause
apk-mitm app.apk                          # sin root: reescribe NSC + re-firma
reflutter app.apk                         # si es Flutter (ver Etapa 4)
```
Si cae con alguno → **pasaste, andá a Etapa 4.** Si **no cae**, el pinning vive en un lugar "difícil" → **Etapa 4** (nativo/Flutter).

**5 caminos para lo mismo:** objection ↔ frida-multiple-unpinning ↔ **medusa** ↔ **house** ↔ apk-mitm (sin root).

**✅ GATE 3:** ves peticiones HTTP legibles de la app en Burp. → Etapa 4.

---

# ETAPA 4 — Entender y tocar el tráfico (los casos difíciles)

**Objetivo:** no solo *ver* sino *leer y modificar* las peticiones para atacar la API. Si en la Etapa 3 el pinning no cayó, o ves tráfico pero es ilegible, es uno de estos:

## 4.A Pinning nativo (`.so`)
**Síntoma:** ningún script Java lo pasa; el pinning está en C (BoringSSL).
```bash
# ubicar el símbolo (Ghidra/radare) y hookearlo:
frida -U -f com.pkg -l native-ssl.js --no-pause
#   Interceptor.attach a SSL_CTX_set_custom_verify / SSL_get_verify_result / ssl_verify_result
```
Alternativa: parchear el `.so` con Ghidra/radare y rebuild.

## 4.B Flutter (`libflutter.so`)
**Síntoma:** hay `libflutter.so` en `lib/`; la CA no sirve y los unpinning genéricos tampoco (Flutter trae su propio BoringSSL y **no** usa el trust store del SO).
```bash
reflutter app.apk        # parchea el engine → luego instalás la app parcheada
# o hook a ssl_verify en libflutter.so por offset (scripts de la comunidad por versión)
```

## 4.C mTLS (certificado de cliente)
**Síntoma:** pasaste el pinning pero el server **te rechaza a vos** (te pide cert de cliente).
```bash
unzip app.apk -d out
find out \( -name '*.p12' -o -name '*.pfx' -o -name '*.bks' \)   # cert embebido
#   buscar la passphrase en JADX/strings
#   Burp → Settings → TLS → Client Certificates → agregar el .p12 + passphrase, por host
```
- **Cert en KeyStore:** hook Frida a `KeyStore.getEntry`, `SSLContext.init`, `KeyManagerFactory`.
- **Techo:** clave en **StrongBox/TEE** no sale en claro → no la extraés (Etapa 6).

## 4.D Payload cifrado / firmado
**Síntoma:** capturás la request pero el **body es ilegible** (AES) o lleva una firma (HMAC) que no reproducís.
```bash
frida -U -f com.pkg -l crypto-hook.js --no-pause
#   hook Cipher.doFinal, Mac.doFinal, Signature, SecretKeySpec → plaintext + clave
```
- **Brida** (puente Burp↔Frida): llamás a la cripto de la app desde Burp → fuzzeás la API con el cifrado correcto.
- **Ofuscación de por medio:** `frida-dexdump`/`fridump` (volcar DEX descifrado), `frida-trace -j '*!*decrypt*'`. *El runtime no miente.*

**✅ GATE 4:** leés y podés **modificar** las requests → ya estás atacando la API (Etapa 6, camino "proxeo OK").

---

# ETAPA 5 — Cuando todo se defiende junto (RASP / anti-Frida)

**Objetivo:** que la instrumentación sobreviva. Si la app se cierra **apenas enganchás Frida** (no por root/emu), es **anti-instrumentación**, probablemente un **RASP comercial**.

```bash
apkid app.apk        # identificar el producto es lo primero
```
| Producto | Se reconoce por |
|---|---|
| **Appdome** | `libappdome*`; **el más estudiado** (no-code → bypasses compartidos, buscá primero) |
| **Guardsquare** | DexGuard / `libdexguard*` |
| **Promon SHIELD** | `libshield*`; banca, agresivo |
| Digital.ai (Arxan) / Zimperium | libs propias |

**Anti-anti-Frida (esconder Frida del RASP):**
```bash
adb shell su -c "/data/local/tmp/frida-server -l 0.0.0.0:9999 &"   # puerto NO default
frida -H 127.0.0.1:9999 -f com.pkg --no-pause
# + renombrar el binario y sacarlo de /data/local/tmp
```
- **Gadget embebido:** `objection patchapk -s app.apk` (Frida dentro del APK, sin server)
- **Magisk (Zygisk + módulos anti-detección)**; parchear cada check (hook a `open`/`read` de `/proc/self/maps`, `strstr`, escaneo de puertos)
- **Cambiar de motor:** si detecta solo Frida → Xposed/LSPosed o r2frida
- **Realidad:** gato-y-ratón; cada release del RASP rompe bypasses.

**Decisión honesta:** la pregunta no es "¿se puede?" sino **"¿me alcanza el tiempo?"**. Si el RASP aguanta tras esfuerzo razonable → **pivote a la API** (Etapa 6). El RASP **no protege el backend**.

---

# ETAPA 6 — Estado final: proxeo sí, o proxeo no

Todo el camino desemboca en uno de dos finales, y **los dos son un resultado válido del pentest.**

### 🟢 Final A — Proxeo OK
Ves y modificás el tráfico. **El bypass fue un medio; el fin es la API.** Ahora:
- Enumerar endpoints, entender los tokens (JWT/sesión).
- **Autorización: IDOR / BOLA** (pedir el recurso de otro usuario), lógica de negocio, mass assignment, rate limiting.
- Herramientas: Burp (Autorize para IDOR, Intruder/Turbo Intruder), mitmproxy + scripts.

### 🔴 Final B — No proxea desde el cliente (el techo)
Hay una barrera que **no cae** porque la decisión no vive en el cliente:
```text
· Play Integrity validado en server (veredicto firmado por HW)
· White-box crypto (clave nunca en claro en memoria)
· mTLS con clave en StrongBox / TEE
· Decisión 100% server-side
```
**Pero "inatacable desde el cliente" ≠ "sin bugs".** La lógica se muda al server → buscás fallas de *implementación*:
- Play Integrity **sin validar el nonce** → replay; veredicto **vencido** o de **otro package** aceptado; check **local de respaldo** (ese sí se hookea).
- Y las mismas de siempre en la API: **IDOR/BOLA, tokens, lógica**.

→ **El techo del bypass del cliente es el piso del ataque a la API.** Si de verdad no hay vector, el hallazgo es *"la defensa del cliente está bien implementada"* — y eso también es un resultado.

---

## Método invariante (vale para toda la ruta)

> Toda protección = una **decisión** = un **valor**. Ubicá el check → mirá qué devuelve → quién lo consume → **observá o modificá**. Probá lo barato primero (objection/scripts genéricos), escalá solo si falla (Frida a medida → nativo → repackaging), y **sabé cuándo parar** y pivotear a la API. Diagnosticá siempre con `apkid` **antes** de instrumentar.

## Scripts referenciados (van en `04-scripts/` del repo)
`anti-root.js` · `anti-emulator.js` · `anti-debug.js` · `anti-tamper.js` · `frida-multiple-unpinning.js` · `native-ssl.js` · `crypto-hook.js` — son los hooks que este playbook invoca. El `cheatsheet.md` tiene la versión lookup (protección→comando) de todo esto.
