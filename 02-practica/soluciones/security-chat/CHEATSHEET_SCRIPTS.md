# 📜 Cheatsheet — Uso de Scripts Frida (Security Chat / Cordobitec)

Guía rápida de ejecución para los scripts de instrumentación dinámica incluidos en `02-practica/soluciones/security-chat/`.

---

## ⚡ Comandos Rápidos de Diagnóstico

Antes de lanzar scripts, verifica la conexión con el dispositivo y el estado del proceso:

```bash
# 1. Verificar dispositivo conectado vía ADB
adb devices

# 2. Listar procesos y confirmar que Frida ve la app activa
frida-ps -Ua | grep -i securechat

# 3. Ver PID exacto del proceso en Android
adb shell "ps -A | grep -E 'securechat|frida'"
```

---

## 🎯 Regla de Oro: ¿Attach o Spawn?

| Situación | Modo | Sintaxis | Cuándo usar |
| :--- | :--- | :--- | :--- |
| **La app YA está abierta** | **Attach (`-n` o `-p`)** | `frida -U -n com.securechat -l script.js`<br>`frida -U -p <PID> -l script.js` | Cuando ya estás en la pantalla del chat y no quieres reiniciar el estado. |
| **La app está cerrada** | **Spawn (`-f`)** | `frida -U -f com.securechat -l script.js --no-pause` | Cuando necesitas capturar cosas tempranas en el arranque (`onCreate`, inicialización de claves estáticas). |
| **App con Gadget embebido (TCP)** | **Remote (`-H`)** | `adb forward tcp:27042 tcp:27042`<br>`frida -H 127.0.0.1:27042 -n Gadget -l script.js` | Si el dispositivo no tiene root y el APK fue parcheado con `objection patchapk`. |

---

## 🛠️ Catálogo de Scripts y Cómo Usarlos

Ubicación de trabajo:
```bash
cd taller-android/02-practica/soluciones/security-chat/
```

### 1. `3_hook_key.js` — Captura de clave AES en vivo
* **Propósito:** Intercepta `SecretKeySpec.$init` cuando el algoritmo es `"AES"`.
* **Ejecución (con app abierta):**
  ```bash
  frida -U -n com.securechat -l 3_hook_key.js
  ```
  *(Alternativa con nombre de Gadget):* `frida -U -n Gadget -l 3_hook_key.js`
* **Acción en la app:** Escribe y envía cualquier mensaje en el chat.
* **Salida esperada:**
  ```text
  [*] Esperando a que se genere la clave AES...
  [🔑 CLAVE AES CAPTURADA] -> CordobitecBackendSecretKey123456
  ```

---

### 2. `4_dump_keys_gen.js` — Hook universal a cualquier clave
* **Propósito:** Intercepta cualquier llamada a `SecretKeySpec`, detecta el algoritmo (AES, DES, HMAC, etc.) y genera la clave tanto en String legible como en Hexadecimal puro.
* **Ejecución:**
  ```bash
  frida -U -n com.securechat -l 4_dump_keys_gen.js
  ```
* **Acción en la app:** Interactúa con el chat o navega por la app.
* **Salida esperada:**
  ```text
  [🔑 KEY INTERCEPTADA] Tipo: AES
    -> String: CordobitecBackendSecretKey123456
    -> Hex:    436f72646f62697465634261636b656e645365637265744b6579313233343536
    -> Tamaño: 32 bytes (256 bits)
  ```

---

### 3. `5_dump_ram.js` — Escaneo de Heap en RAM viva
* **Propósito:** No espera eventos futuros; usa `Java.choose` para barrer la memoria de la JVM buscando instancias de `SecretKeySpec` que ya hayan sido instanciadas antes de iniciar Frida.
* **Ejecución:**
  ```bash
  frida -U -n com.securechat -l 5_dump_ram.js
  ```
* **Acción en la app:** Ninguna (el escaneo ocurre al iniciar el script).
* **Salida esperada:**
  ```text
  [*] Escaneando la memoria RAM (Heap) buscando claves AES (SecretKeySpec)...
  [+] Clave #1 encontrada en RAM:
    -> String: CordobitecBackendSecretKey123456
    -> Hex:    ...
  [*] Escaneo finalizado. Total encontrados: 1
  ```

---

### 4. `6_dump_all_strings.js` — Volcado masivo de Strings en Heap
* **Propósito:** Busca todos los objetos `java.lang.String` con longitud entre 16 y 64 caracteres alojados en la memoria. Útil cuando no se conoce la clase o cuando el secreto está ofuscado.
* **Ejecución:**
  ```bash
  frida -U -n com.securechat -l 6_dump_all_strings.js
  ```

---

### 5. `frida_workshop_tool.py` — Explorador interactivo CLI
* **Propósito:** Enumerar clases cargadas y métodos de una clase específica a través del socket de Frida.
* **Preparación previa:**
  ```bash
  adb forward tcp:27042 tcp:27042
  ```
* **Comandos:**
  ```bash
  # Listar clases de la app:
  python3 frida_workshop_tool.py enum_classes --package com.securechat

  # Listar métodos de una clase específica:
  python3 frida_workshop_tool.py enum_methods --class-name com.securechat.MainActivity
  ```

---

### 6. `encrypt_payload.py` — Encriptador AES-GCM (Fase Explotación)
* **Propósito:** Con la clave obtenida en los pasos anteriores, generar un payload cifrado válido para atacar el endpoint del backend.
* **Ejecución:**
  ```bash
  python3 encrypt_payload.py
  ```
* **Uso interactivo:**
  1. Ingresa la clave AES capturada.
  2. Ingresa el comando o JSON a inyectar (ej: `{"target": "127.0.0.1; id"}`).
  3. Copia el Base64 generado y envíalo en la petición interceptada en Burp Suite.

---

## 💡 Troubleshooting Rápido

* **Error: `Process not found` al hacer `-n com.securechat`:**
  * La app puede estar pausada o renombrada por el Gadget. Prueba conectarte al proceso por PID (`frida -U -p <PID> -l script.js`) o usando `-n Gadget`.
* **Error: `Device disconnected` o timeout:**
  * Si usas emulador o puerto forwardeado: `adb reconnect` y verifica con `adb devices`.
* **Cerrar Frida:**
  * Presiona `Ctrl + C` en cualquier momento para desacoplar el hook sin matar la aplicación.
