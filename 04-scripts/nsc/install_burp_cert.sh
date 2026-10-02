#!/bin/bash

# Configuration
BURP_HOST="localhost"
BURP_PORT="8080"
TEMP_DIR=$(mktemp -d)
CERT_DER="$TEMP_DIR/cacert.der"
CERT_PEM="$TEMP_DIR/cacert.pem"

echo "[*] Working in temporary directory: $TEMP_DIR"

# 1. Download Burp Certificate
echo "[*] Downloading Burp Suite certificate from http://$BURP_HOST:$BURP_PORT/cert..."
curl -s -o "$CERT_DER" "http://$BURP_HOST:$BURP_PORT/cert"

if [ ! -f "$CERT_DER" ] || [ ! -s "$CERT_DER" ]; then
    echo "[!] Error: Failed to download certificate from http://$BURP_HOST:$BURP_PORT/cert"
    echo "[!] Make sure Burp Suite is running and the proxy listener is active on port $BURP_PORT."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 2. Convert to PEM and calculate subject hash
echo "[*] Converting certificate to PEM format..."
openssl x509 -inform DER -in "$CERT_DER" -out "$CERT_PEM"

# Get old subject hash (needed by Android's Conscrypt trust manager)
HASH=$(openssl x509 -inform PEM -subject_hash_old -in "$CERT_PEM" | head -1)
CERT_FILENAME="$HASH.0"
CERT_FILE_PATH="$TEMP_DIR/$CERT_FILENAME"

echo "[*] Certificate hash: $HASH"
cp "$CERT_PEM" "$CERT_FILE_PATH"

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "[!] Error: adb command not found. Please install Android Platform Tools."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check if device is connected
DEVICE_STATUS=$(adb get-state 2>/dev/null)
if [ "$DEVICE_STATUS" != "device" ]; then
    echo "[!] Error: No emulator or device connected via adb."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Get Android version / SDK level
SDK_VERSION=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
ANDROID_VERSION=$(adb shell getprop ro.build.version.release | tr -d '\r')
echo "[*] Connected to Android $ANDROID_VERSION (SDK Level: $SDK_VERSION)"

install_system_cert() {
    local method=$1
    echo "[*] Attempting system CA installation method: $method"
    
    # Try to restart adb as root
    adb root >/dev/null 2>&1
    sleep 1
    
    # Check if adb root succeeded
    ADB_ROOT_USER=$(adb shell whoami | tr -d '\r')
    if [ "$ADB_ROOT_USER" != "root" ]; then
        echo "[!] Warning: Failed to gain root access via 'adb root'."
        return 1
    fi

    if [ "$method" = "legacy" ]; then
        # Standard root installation for Android 11 / SDK <= 30
        adb remount >/dev/null 2>&1
        adb shell "mount -o remount,rw /system" >/dev/null 2>&1
        
        adb push "$CERT_FILE_PATH" "/system/etc/security/cacerts/$CERT_FILENAME"
        adb shell "chmod 644 /system/etc/security/cacerts/$CERT_FILENAME"
        adb shell "chown root:root /system/etc/security/cacerts/$CERT_FILENAME"
        
        # Verify the file exists and is correctly placed
        VERIFY=$(adb shell "ls /system/etc/security/cacerts/$CERT_FILENAME" 2>/dev/null)
        if [[ "$VERIFY" == *"$CERT_FILENAME"* ]]; then
            return 0
        fi
    elif [ "$method" = "tmpfs" ]; then
        # Android 12+ / SDK >= 31 tmpfs overlay method to bypass read-only /system partition
        
        # Determine the target cacerts directory (handles both system and APEX Conscrypt paths)
        TARGET_DIR="/system/etc/security/cacerts"
        if adb shell "test -d /apex/com.android.conscrypt/cacerts" 2>/dev/null; then
            TARGET_DIR="/apex/com.android.conscrypt/cacerts"
        fi
        echo "[*] Selected target CA directory: $TARGET_DIR"

        # Create temporary working dir on device
        adb shell "mkdir -p /data/local/tmp/cacerts"
        adb shell "rm -rf /data/local/tmp/cacerts/*"
        
        # Copy existing certs to temp directory
        adb shell "cp $TARGET_DIR/* /data/local/tmp/cacerts/" 2>/dev/null
        
        # Push the new certificate
        adb push "$CERT_FILE_PATH" "/data/local/tmp/cacerts/$CERT_FILENAME"
        adb shell "chmod 644 /data/local/tmp/cacerts/*"
        adb shell "chown root:root /data/local/tmp/cacerts/*"
        
        # Mount tmpfs over target directory
        adb shell "mount -t tmpfs tmpfs $TARGET_DIR"
        
        # Copy original certificates + new certificate back into the mounted directory
        adb shell "cp /data/local/tmp/cacerts/* $TARGET_DIR/"
        
        # Clean up temporary dir on device
        adb shell "rm -rf /data/local/tmp/cacerts"
        
        # Verify
        VERIFY=$(adb shell "ls $TARGET_DIR/$CERT_FILENAME" 2>/dev/null)
        if [[ "$VERIFY" == *"$CERT_FILENAME"* ]]; then
            return 0
        fi
    fi
    
    return 1
}

fallback_manual_install() {
    echo "[!] System-level root installation failed or was not possible."
    echo "[*] Initiating fallback: Copying certificate to user storage..."
    
    # Push to SD card Downloads folder
    adb push "$CERT_PEM" "/sdcard/Download/burp-ca.crt"
    
    echo "[*] Triggering system credential installation intent on the device..."
    # Launch intent to import certificates
    adb shell "am start -a android.credentials.INSTALL -t 'application/x-x509-ca-cert' -d 'file:///sdcard/Download/burp-ca.crt'" >/dev/null 2>&1
    
    echo ""
    echo "========================================================================"
    echo "[!] FALLBACK REQUIRED: Manual Action Needed on Emulator!"
    echo "1. The CA certificate has been pushed to: /sdcard/Download/burp-ca.crt"
    echo "2. The system settings panel has been opened."
    echo "3. Please navigate to: Settings -> Security -> Encryption & credentials"
    echo "   -> Install a certificate -> CA Certificate."
    echo "4. Select 'Install anyway' and choose 'burp-ca.crt' from the Downloads folder."
    echo "========================================================================"
    echo ""
}

# 3, 4, 5. Execute Installation Logic based on Android Version
SUCCESS=false

if [ "$SDK_VERSION" -le 30 ]; then
    # Android 11 or lower
    install_system_cert "legacy" && SUCCESS=true
    if [ "$SUCCESS" = false ]; then
        # Fallback to tmpfs overlay mount if standard remount failed
        install_system_cert "tmpfs" && SUCCESS=true
    fi
else
    # Android 12 or higher (tmpfs overlay method)
    install_system_cert "tmpfs" && SUCCESS=true
fi

if [ "$SUCCESS" = true ]; then
    echo "[+] SUCCESS: Burp Suite CA Certificate installed successfully at system level!"
    echo "[*] Note: You may need to restart your apps (or the emulator) for changes to take effect."
else
    fallback_manual_install
fi

# 6. Clean up temporary local files
echo "[*] Cleaning up local temporary files..."
rm -rf "$TEMP_DIR"
echo "[*] Done."
