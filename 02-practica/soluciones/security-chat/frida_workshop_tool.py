#!/usr/bin/env python3
import sys
import argparse
import subprocess
import os

def run_frida_cli(script_code):
    temp_file = "temp_frida_script.js"
    with open(temp_file, "w") as f:
        f.write(script_code)
    
    print(f"[*] Inyectando código en la app (presioná Ctrl+C para salir)...\n")
    try:
        # Conectamos via TCP al Frida Gadget embebido (requiere: adb forward tcp:27042 tcp:27042)
        subprocess.run(["frida", "-H", "127.0.0.1:27042", "-n", "Gadget", "-l", temp_file])
    except KeyboardInterrupt:
        pass
    except FileNotFoundError:
        print("[!] No se encontró el comando 'frida'. Instalalo con: pip install frida-tools")
    finally:
        if os.path.exists(temp_file):
            os.remove(temp_file)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Herramienta genérica de Frida para el Taller")
    subparsers = parser.add_subparsers(dest="action", help="Acción a realizar")
    
    # 1. Enumerar clases de un paquete
    parser_classes = subparsers.add_parser("enum_classes", help="Lista las clases de un paquete")
    parser_classes.add_argument("--package", required=True, help="Ejemplo: com.securechat")

    # 2. Enumerar métodos de una clase
    parser_methods = subparsers.add_parser("enum_methods", help="Lista los métodos de una clase")
    parser_methods.add_argument("--class-name", required=True, help="Ejemplo: com.securechat.CryptoModule")

    # 3. Hook genérico a un método
    parser_hook = subparsers.add_parser("hook_method", help="Hookea un método para ver sus argumentos")
    parser_hook.add_argument("--class-name", required=True, help="Ejemplo: com.securechat.CryptoModule")
    parser_hook.add_argument("--method", required=True, help="Ejemplo: encryptPayload")

    args = parser.parse_args()

    if args.action == "enum_classes":
        js_code = f"""
        setTimeout(function() {{
            Java.performNow(function() {{
                console.log("[*] Buscando clases que empiecen con: {args.package}");
                try {{
                    var classes = Java.enumerateLoadedClassesSync();
                    var count = 0;
                    classes.forEach(function(className) {{
                        if (className.startsWith("{args.package}")) {{
                            console.log("[Clase] " + className);
                            count++;
                        }}
                    }});
                    console.log("[*] Búsqueda finalizada. " + count + " clases encontradas.");
                }} catch(e) {{
                    console.log("[!] Error: " + e);
                }}
            }});
        }}, 3000);
        """
        run_frida_cli(js_code)

    elif args.action == "enum_methods":
        js_code = f"""
        Java.perform(function() {{
            try {{
                var targetClass = Java.use("{args.class_name}");
                var methods = targetClass.class.getDeclaredMethods();
                console.log("[*] Métodos encontrados en {args.class_name}:");
                methods.forEach(function(method) {{
                    console.log(" -> " + method.toString());
                }});
            }} catch (e) {{
                console.log("[!] Error: No se encontró la clase o no está cargada en memoria.");
            }}
        }});
        """
        run_frida_cli(js_code)

    elif args.action == "hook_method":
        js_code = f"""
        Java.perform(function() {{
            try {{
                var targetClass = Java.use("{args.class_name}");
                
                // Sobrescribimos todas las sobrecargas (overloads) del método
                var overloads = targetClass["{args.method}"].overloads;
                
                console.log("[*] Hookeando " + overloads.length + " variantes de {args.method}() en {args.class_name}");
                
                overloads.forEach(function(overload) {{
                    overload.implementation = function() {{
                        var argsList = [];
                        for (var i = 0; i < arguments.length; i++) {{
                            argsList.push(arguments[i]);
                        }}
                        console.log("\\n[HOOK] {args.method}() llamado!");
                        console.log("  -> Argumentos: " + JSON.stringify(argsList));
                        
                        var result = this["{args.method}"].apply(this, arguments);
                        
                        console.log("  <- Retorno: " + result);
                        return result;
                    }};
                }});
            }} catch (e) {{
                console.log("[!] Error al hookear: " + e);
            }}
        }});
        """
        run_frida_cli(js_code)
    
    else:
        parser.print_help()

