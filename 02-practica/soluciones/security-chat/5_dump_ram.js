// Archivo: 5_dump_ram.js
// Propósito: Escanea el heap de la JVM para encontrar claves que ya fueron instanciadas antes de abrir Frida.
Java.perform(function() {
    console.log("[*] Escaneando la memoria RAM (Heap) buscando claves AES (SecretKeySpec)...");
    
    var count = 0;
    Java.choose("javax.crypto.spec.SecretKeySpec", {
        onMatch: function(instance) {
            count++;
            console.log("\n[+] Clave #" + count + " encontrada en RAM:");
            
            try {
                var keyBytes = instance.getEncoded();
                if (keyBytes !== null) {
                    try {
                        var StringClass = Java.use("java.lang.String");
                        var keyStr = StringClass.$new(keyBytes, "UTF-8");
                        console.log("  -> String: " + keyStr);
                    } catch(e) {}
                    
                    var hexKey = "";
                    for (var i = 0; i < keyBytes.length; i++) {
                        var b = keyBytes[i] & 0xFF;
                        hexKey += (b < 16 ? "0" : "") + b.toString(16);
                    }
                    console.log("  -> Hex:    " + hexKey);
                }
            } catch (e) {
                console.log("  -> [Error leyendo bytes]");
            }
        },
        onComplete: function() {
            console.log("\n[*] Escaneo finalizado. Total encontrados: " + count);
        }
    });
});
