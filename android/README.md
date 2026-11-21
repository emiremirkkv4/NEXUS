# NEXUS for Android

The Android app connects to the same read-only Windows server as the iPhone app. It includes Dashboard, Devices and Settings, live CPU and RAM history, disk, uptime and network rates. It supports Android 8.0 and later.

## Install and pair

1. Copy the supplied **NEXUS.apk** to your Android phone. Tap it in Files or Downloads. If Android prompts for permission to install from that source, grant it for the installation. You can turn that permission off afterward.
2. On the gaming PC, launch **run.bat**, select the private network interface that matches the PC address in the app, and use the same port (default **8765**). Keep the console open.
3. Put the phone on the same home network. Open NEXUS → **Settings**, enter the pairing token from the Windows server, then tap **Connect**. Switch to **Dashboard**. The first reading may take a few seconds.
4. The token is saved after successful pairing. Its encryption key is held in Android Keystore. Leave the token field blank to reuse it. Monitoring pauses when the app leaves the foreground. Open Settings and tap Connect to resume.

Version 1.0.1 offers three address presets: **192.168.0.12** (home LAN), **192.168.56.1** (requires a route to that adapter), and **127.0.0.1** (this phone, requires a local port forward to reach the PC). The address is visible in Settings. If your router later changes the PC's address, reserve the original address for the PC on your router or rebuild the APK for the new address. The Android network security configuration denies other cleartext destinations. Use your trusted private LAN because HTTP carries the bearer token without encryption.

If connection fails, open the server's LAN URL followed by `/api/v1/status` in the Android browser. If this fails too, check the selected Windows interface, port, firewall and Wi-Fi. If NEXUS reports **Pairing failed**, reenter the current token. The device placeholders show future integrations.

## Rebuild on Windows

Install JDK 17, Android SDK Platform 35, and Android SDK Build Tools 35.0.0. Point JAVA_HOME at the JDK folder and ANDROID_HOME at the SDK folder. Open PowerShell in the android folder and run the following with your own private PC address.

```powershell
.\build.ps1 -PcAddress 192.168.0.12,192.168.56.1,127.0.0.1
```

The script compiles native Java and Android resources, generates the device-specific HTTP allowlist, creates Dalvik bytecode, aligns and signs the APK, and verifies it before writing `build\NEXUS.apk`. You can pass explicit `-Jdk`, `-PlatformJar`, `-BuildTools` and `-OutputFile` paths. The app uses Android platform APIs and has no third-party runtime dependencies.

Signing material is kept under `%LOCALAPPDATA%\NEXUS\AndroidSigning`. The password file is protected using Windows DPAPI for this Windows user. Keep the same signing key for in-place updates. Keep these files out of Git. The Android app and its signing key are independent of the iPhone build.
