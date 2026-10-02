// Archivo: 3_hook_key.js
Java.perform(function() {
    console.log("[*] Esperando a que se genere la clave AES...");
    
    var SecretKeySpec = Java.use("javax.crypto.spec.SecretKeySpec");
    SecretKeySpec.$init.overload('[B', 'java.lang.String').implementation = function(keyBytes, algo) {
        if (algo === "AES") {
            try {
                var StringClass = Java.use("java.lang.String");
                var keyStr = StringClass.$new(keyBytes, "UTF-8");
                console.log("\n[🔑 CLAVE AES CAPTURADA] -> " + keyStr);
            } catch(e) {
                console.log("\n[🔑 CLAVE AES CAPTURADA] -> [Bytes no representables en UTF-8]");
            }
        }
        return this.$init(keyBytes, algo);
    };
});
