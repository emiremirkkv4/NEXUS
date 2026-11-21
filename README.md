# NEXUS Mission Control

Monitor your Windows gaming PC from a browser or the native NEXUS iPhone app. One read-only Windows service samples the machine about every two seconds. The PC, laptop and iPhone can use the same trusted home network. The PC can use Ethernet if it connects to the same LAN as the phone.

## 1 · Start on Windows

1. Extract the entire project ZIP to a folder you own, such as Documents. Open the folder containing this README and `run.bat`.
2. Install 64-bit Python 3.14 or 3.15 from [Python for Windows](https://www.python.org/downloads/windows/). Open a new PowerShell window and type `py -3 --version` to confirm the launcher works.
3. Double-click **run.bat**. The first launch creates a project-local Python environment and downloads FastAPI, Uvicorn and psutil. Keep this console open while monitoring. You can also open PowerShell in the project folder and run `.\run.bat`.
4. For a first check on this PC, press Enter to select **127.0.0.1**. For the iPhone or laptop, choose the listed address belonging to your home Wi-Fi or Ethernet adapter. Use `ipconfig` in PowerShell to match its **IPv4 Address** to the menu. Skip VPN and virtual adapters. Press Enter for port **8765**.
5. Open the exact HTTP address printed in the console. On the gaming PC, press **Win+R**, enter `notepad "%LOCALAPPDATA%\NEXUS\pairing.token"`, and press Enter. Copy the whole token privately into the dashboard and click **Connect**. The first reading takes about two seconds. Network rates need two samples.
6. To use the laptop, visit the same LAN URL in its browser. Each new dashboard tab needs the token. **Disconnect** clears the live readings and the tab's in-memory credential. Stop the server with **Ctrl+C**. Restart to change the interface or port.

### Let your iPhone reach the PC

Set your trusted home network to **Private** in Windows Settings → Network & internet → Wi-Fi or Ethernet → your connected network. Keep Windows Defender Firewall enabled. For a limited inbound rule, open **Windows Defender Firewall with Advanced Security** → Inbound Rules → New Rule → Custom. Select the program at `.venv\Scripts\python.exe` inside your project (if Windows identifies the base Python executable as the listener, use that executable). Choose TCP and your local port, set **remote IP addresses** to **Local subnet**, choose **Allow the connection**, check **Private** only, and name it **NEXUS home telemetry**. Remove the rule if you retire the server. A broad inbound Python exception is unnecessary.

On iPhone Safari, open the printed LAN URL followed by `/api/v1/status`. You should see `{"online":true}`. This tests reachability before app installation. A guest Wi-Fi network with client isolation can prevent devices from reaching each other. Leave your router's port forwarding off.


## 3 · Build the unsigned IPA from Windows

1. Open your repository on GitHub. Confirm the workflow is present on the default branch. Open **Actions**, enable workflows if prompted, and select **Build unsigned NEXUS IPA**.
2. Select **Run workflow**, choose **main** and click the green **Run workflow** button. Open the new run to follow its logs. Hosted macOS runner use is subject to the repository's Actions allowance and billing settings. [GitHub runner images](https://github.com/actions/runner-images)
3. GitHub provisions a macOS machine, installs XcodeGen if needed, generates the Xcode project from `ios/project.yml`, and runs Xcode's Release device build with signing disabled. The deployment target is **iOS 17.0**. The workflow packages the executable and resources under `Payload/NEXUS.app`, checks the ZIP and uploads `NEXUS.ipa`. The runner needs no Apple account, team, password or signing certificate.
4. After a **successful** run, open the run summary and download **NEXUS-unsigned** under **Artifacts** while signed in. Extract GitHub's outer ZIP on Windows. Keep the inner **NEXUS.ipa** intact. Artifacts are retained for 14 days or the shorter limit set by your repository. If the build fails, expand the first failed step and read the first Xcode or package error. [Downloading workflow artifacts](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/downloading-workflow-artifacts)

## 4 · Sign and install on your iPhone.

1. Check Settings → General → About for iOS 17 or later. Download **Sideloadly for Windows** from its official site. Follow its Windows prerequisites for Apple's desktop iTunes and iCloud installers. The official download page provides links and guidance for Microsoft Store installations. [Sideloadly downloads and FAQ](https://sideloadly.io/)
2. Connect and unlock the iPhone using a data-capable USB cable. Tap **Trust This Computer** and enter the device passcode if prompted. Select your iPhone in Sideloadly and drag **NEXUS.ipa** into its window.
3. Choose Apple ID sideloading, enter your free Apple ID in Sideloadly, click **Start**, and complete Apple's authentication prompts there. Sideloadly is a third-party tool that uses the account to sign the app for your device. Keep credentials out of source files, GitHub settings and build logs.
4. Follow the device prompts. If requested, trust your developer identity under **Settings → General → VPN & Device Management**. Enable **Developer Mode** under **Settings → Privacy & Security**, restart and confirm when prompted. The setting may appear after the first install attempt. [Apple's Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
5. Launch NEXUS → **Settings**. Enter the PC's LAN IPv4 address without a scheme or slash, enter the port, then paste the pairing token and tap **Connect**. Allow **Local Network** access. The app saves the accepted token in this iPhone's Keychain for that address and port. On a later launch leave the field blank and tap **Connect**. Disconnect before editing the settings.
6. Open **Dashboard** to see live readings and **Devices** to see the paired PC. The other devices are labeled as future integrations.

**Free signing lasts seven days.** Re-sign the same IPA with Sideloadly and the same Apple ID and bundle identity before expiry. An expired app can stop launching until you refresh it. You can reuse the downloaded IPA for this. Optional automatic refresh depends on Sideloadly being able to reach your phone and Apple's signing services. Free provisioning limits active apps and app identifiers. It is for personal device testing. App Store and TestFlight distribution require program membership. [Sideloadly FAQ](https://sideloadly.io/) · [Apple developer account capabilities](https://developer.apple.com/help/account/basics/about-your-developer-account)

## 5 · What the numbers mean

| Read-only route | Authentication | Response |
| --- | --- | --- |
| GET /api/v1/status | Public | Minimal reachability check |
| GET /api/v1/stats | Authorization header with Bearer followed by the pairing token | One coherent snapshot shared by both clients |

The snapshot includes a Unix timestamp, hostname, OS, CPU usage and OS-reported MHz, RAM percentage and total/available bytes, system-drive percentage and total/free bytes, uptime in seconds, aggregate network byte counters and upload/download rates in **bytes per second**. Adapters include local and virtual traffic. A missing frequency or unmeasurable rate is null. Charts start empty and accumulate actual samples while connected. An unreachable PC cannot report its own offline state, so clients detect request failures. A 503 means the service is reachable and awaiting a fresh sample. There is no historical database.

## 6 · Troubleshooting

| Symptom | What to check |
| --- | --- |
| Launcher closes or installation fails | Run it from PowerShell to keep the error visible. Verify `py -3 --version` and internet access for initial package installation. |
| Address already in use | Stop the other server with Ctrl+C or restart NEXUS and choose another port. Use the same port on the phone. |
| Works on PC only | Select the LAN interface at startup. Check the Private firewall rule, same LAN, guest isolation and VPN. Try the status URL from Safari. |
| Safari works, app times out | Enable NEXUS in Settings → Privacy & Security → Local Network. Recheck the address and port in NEXUS. |
| Token rejected | Reopen the PC's token file, paste its current contents and reconnect. A different PC or port has its own Keychain entry. |
| Counters disappear | Check that the PC is awake and read the console error. The sampler and connected clients retry. |
| Device absent in Sideloadly | Unlock, trust the computer, verify the USB data cable and confirm desktop iTunes can see the iPhone. |
| Signing limit or identifier error | Read Sideloadly's exact error. Use an available free app slot or wait for the identifier limit to reset. For a bundle identifier collision, set a unique reverse-DNS identifier in project.yml and rebuild, or use Sideloadly's bundle ID option. Keep that identity for future refreshes. |

## 7 · Security and future development

The server creates a random 256-bit bearer token in the signed-in Windows user's Local AppData folder. Anyone who can read that file can access telemetry. To rotate it, stop the server, move the token file out of that folder, restart, and pair your clients with the newly generated value. Store the old file securely or discard it. The browser keeps the token in memory. The iPhone uses a device-only, when-unlocked Keychain item. The iOS client accepts private IPv4 addresses, declines HTTP redirects and declares local network usage and scoped ATS exceptions. [Apple's ATS exception domains](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains)

HTTP sends both the token and readings without encryption or server authentication. A hostile network participant could intercept or modify traffic, steal a token or impersonate the PC. Use this version only on a trusted private LAN. For HTTPS, give the PC a stable local DNS name, issue a certificate for that name from a trusted CA, serve TLS through a LAN-only reverse proxy, and bind Uvicorn to loopback. Configure the iPhone to trust your verified CA if using a private one. Update the app's host validation and URL scheme to allow that HTTPS hostname, remove the HTTP exceptions, and rotate the token after migration. Keep normal certificate validation enabled.

The API exposes monitoring only. A future provider can add its own read-only route to `backend/` and device view to `ios/Sources/` without changing the PC snapshot contract. Multiple PCs can use separate address/port profiles. ESP32 control, ESP32-CAM video, printer telemetry, notifications, application launching and Xbox status are future work. Check Xbox API availability before designing that integration. Give any future control actions separate, explicit authorization.

## Acceptance checks

- **Windows:** Start with the launcher, open the dashboard, try an incorrect token, then pair. Compare memory and disk to Task Manager or File Explorer. Create normal activity and watch the plot update. Disconnect and confirm that readings clear. Stop the server during polling to test connection loss.
- **GitHub macOS runner:** Generate the Xcode project, compile and link SwiftUI, Charts and Security against the device SDK, then verify and download the unsigned IPA. The Windows tests cannot verify Apple's build tools.
- **Physical iPhone:** Verify Sideloadly signing, trust, first launch, Local Network permission, Keychain reuse after relaunch, charts, and disconnect/reconnect. Put the PC to sleep or disable Wi-Fi to test connection errors. Re-sign before the seven-day deadline.

## Mobile address picker (v1.0.1)

Choose the same interface in the Windows launcher and mobile Settings. Both apps offer these presets:

- **192.168.0.12** — the gaming PC's home Ethernet address when this build was made. Use this first on home Wi-Fi.
- **192.168.56.1** — another PC interface. The phone needs a route to that network.
- **127.0.0.1** — loopback on the device running the client. On a phone this requires a separately configured local forward to reach Windows.

On Android, open Settings and tap the server address. On iPhone, open Settings and tap Choose server address, or enter a private IPv4 address manually. Pairing tokens are saved separately per address and port. See [Android setup and build instructions](android/README.md).
