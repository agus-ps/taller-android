# Rompiendo Apps Android

Análisis estático, dinámico y **bypass de protecciones** en aplicaciones Android.
Material del taller de **Hacking Day 2026** (GISSIC · UTN) — y punto de partida para
seguir aprendiendo Android hacking por tu cuenta.

Ponentes: Agustín María Paz Stefanini · Matías Jesús Galanti.

> ⚠️ **Solo para aprender.** Todo esto se practica sobre **apps propias, labs
> intencionalmente vulnerables o testing autorizado**. Ver [`99-datos/legal-y-etica.md`](99-datos/).

---

## Por dónde empezar

**Si venís al taller:**
1. `00-setup/` — instalá las herramientas **antes** del evento y corré `verify.sh`.
2. `01-teoria/` — la presentación y los apuntes.
3. `02-practica/` — los retos guiados.

**Si caés al repo después / querés aprender solo:**
1. `01-teoria/apuntes.md` + `01-teoria/cheatsheet.md` — la teoría y la referencia rápida.
2. `05-labs/` — apps vulnerables públicas para practicar sin fin.
3. `04-scripts/` — el kit de scripts de bypass listos para usar.

---

## El mapa del repo

| Carpeta | Qué hay |
|---|---|
| [`00-setup/`](00-setup/) | Scripts de instalación (Linux/macOS/Windows) + `verify.sh` + emulador |
| [`01-teoria/`](01-teoria/) | La `.pptx`, `apuntes.md` (teoría escrita), `cheatsheet.md`, `enlaces.md` |
| [`02-practica/`](02-practica/) | APKs guiadas del taller y soluciones |
| [`03-agent-driven/`](03-agent-driven/) | MCPs, skills y prompts para hacer bypass con agentes de IA |
| [`04-scripts/`](04-scripts/) | El kit ejecutable: una carpeta por protección (anti-root, pinning, anti-frida…) |
| [`05-labs/`](05-labs/) | Apps vulnerables públicas (submódulos) para seguir practicando |
| [`99-datos/`](99-datos/) | Lo que se consulta: offsets, firmas RASP, props de emulador, listas, glosario, encuadre legal |

---

## La idea que ordena todo

Tenés una APK y todo se te interpone: root detection, pinning, anti-debug, RASP…
El recorrido es siempre el mismo:

> **static genera hipótesis → dynamic las valida → solo se bypassea lo que decide el cliente.**

Y el techo: **el cliente no es confiable, pero el techo del bypass del cliente es el
piso del ataque a la API.** Cada herramienta responde una pregunta concreta; el
`cheatsheet.md` es el mapa herramienta ↔ pregunta.

---

## Clonar (con los labs)

```bash
git clone --recurse-submodules https://github.com/TU_USUARIO/rompiendo-apps-android
# si ya lo clonaste sin submódulos:
git submodule update --init --recursive
```
