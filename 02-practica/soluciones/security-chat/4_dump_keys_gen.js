// Archivo: 4_dump_keys_gen.js
// Propósito: Intercepta el constructor base de Android para todas las claves.
Java.perform(function() {
    console.log("[*] Hook genérico activado sobre javax.crypto.spec.SecretKeySpec");
    console.log("[*] Esperando a que cualquier app cargue una clave en memoria...");
    
    try {
        var SecretKeySpec = Java.use("javax.crypto.spec.SecretKeySpec");
        
        SecretKeySpec.$init.overload('[B', 'java.lang.String').implementation = function(keyBytes, algo) {
            console.log("\n[🔑 KEY INTERCEPTADA] Tipo: " + algo);
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
            console.log("  -> Tamaño: " + keyBytes.length + " bytes (" + (keyBytes.length * 8) + " bits)");
            
            return this.$init(keyBytes, algo);
        };
    } catch (e) {
        console.log("[!] Error: " + e);
    }
});
