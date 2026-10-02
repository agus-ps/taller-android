#!/usr/bin/env python3
import base64
import os
import sys

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    sys.exit("[!] Necesitás instalar cryptography: pip install cryptography")

def encrypt_payload(plaintext_str, aes_key_str):
    # Convertir a bytes
    plaintext_bytes = plaintext_str.encode('utf-8')
    key_bytes = aes_key_str.encode('utf-8')
    
    # Generar IV aleatorio (12 bytes)
    iv = os.urandom(12)
    
    # Cifrar con AES-GCM
    aesgcm = AESGCM(key_bytes)
    ciphertext_with_tag = aesgcm.encrypt(iv, plaintext_bytes, None)
    
    # Concatenar IV + (Ciphertext + Tag) y pasar a Base64
    final_payload = iv + ciphertext_with_tag
    return base64.b64encode(final_payload).decode('utf-8')

if __name__ == "__main__":
    print("=======================================")
    print("  Taller - Encriptador de Payloads AES-GCM")
    print("=======================================\n")
    
    # Pedir la clave AES
    aes_key = input("[?] Ingresá la clave AES (ej: CordobitecBackendSecretKey123456):\n> ").strip()
    
    # Pedir el body/payload
    payload = input("\n[?] Ingresá el body JSON a encriptar (ej: {\"target\": \"127.0.0.1; whoami\"}):\n> ").strip()
    
    if not aes_key or not payload:
        print("[-] Faltan datos. Saliendo...")
        sys.exit(1)
        
    try:
        resultado = encrypt_payload(payload, aes_key)
        print("\n[+] Payload encriptado (Base64):")
        print("-" * 50)
        print(resultado)
        print("-" * 50)
    except Exception as e:
        print(f"\n[!] Error al encriptar: {e}")
