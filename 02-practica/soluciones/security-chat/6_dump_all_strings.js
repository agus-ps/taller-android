// Archivo: 6_dump_all_strings.js
// Propósito: Escanea TODOS los Strings en la memoria Heap. 
// Útil cuando no sabemos qué clase maneja el secreto y queremos buscarlo "a lo bruto".
Java.perform(function() {
    console.log("[*] Iniciando volcado masivo de Strings en RAM...");
    console.log("[!] ADVERTENCIA: Esto puede tardar varios minutos y escupir miles de resultados.");
    
    var count = 0;
    // Buscamos cualquier instancia de String en la memoria de la máquina virtual (Heap)
    Java.choose("java.lang.String", {
        onMatch: function(instance) {
            try {
                var str = instance.toString();
                
                // Filtro básico: evitamos imprimir basura (strings muy cortos o gigantescos)
                // Idealmente, las claves AES suelen tener entre 16 y 64 caracteres.
                if (str !== null && str.length >= 16 && str.length <= 64) {
                    
                    // Si la consola se satura mucho, los jugadores pueden descomentar la línea de abajo 
                    // para buscar palabras clave específicas:
                    // if (str.toLowerCase().includes("key") || str.includes("Cordobitec")) {
                        
                    console.log("[String] " + str);
                    count++;
                    
                    // }
                }
            } catch (e) {
                // Ignoramos fragmentos de memoria corruptos o strings mal formados (Error: invalid string)
            }
        },
        onComplete: function() {
            console.log("\n[*] Volcado finalizado. Total de Strings potenciales: " + count);
        }
    });
});
