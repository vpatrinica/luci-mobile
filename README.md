# LuCI Mobile

<div align="center">
  <a href="https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile">
    <img src="store-badges/google.webp" alt="Get it on Google Play" style="height:56px;"/>
  </a>
  <a href="https://apps.apple.com/app/luci-mobile/id6749455847">
    <img src="store-badges/apple.webp" alt="Download on the App Store" style="height:56px;"/>
  </a>
  <a href="https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile">
    <img src="store-badges/izzyondroid.webp" alt="Get it on IzzyOnDroid" style="height:56px;"/>
  </a>
  <br><br>

![Latest Release](https://shields.rbtlog.dev/simple/com.cogwheel.LuCIMobile)
![GitHub all downloads](https://img.shields.io/github/downloads/cogwheel0/luci-mobile/total?style=flat-square&label=Downloads&logo=github&color=0A84FF)

<img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_01.png" width="300"/>
</div>

<br>

**LuCI Mobile** is a modern Flutter app for managing and monitoring multiple OpenWrt/LuCI routers. It features a beautiful Material 3 UI, secure authentication, real-time stats, and seamless multi-router support.

---

## Features

- **Multiple Router Management:** Add, switch, and manage any number of OpenWrt routers. Each router’s data is kept separate and secure.
- **Secure Login:** HTTP/HTTPS support, self-signed certificate handling, and secure credential storage.
- **Dashboard Overview:** Real-time system stats, interface status, connected clients, and interactive charts.
- **Network Interface Management:** View and monitor all wired and wireless interfaces, bandwidth, IPs, and DNS.
- **Client Management:** See all connected devices, connection type, MAC/IP, vendor, DHCP lease, and more.
- **System Control:** Remote reboot, settings, and theme customization (light/dark mode).
- **Modern UI/UX:** Material Design 3, responsive layout, and intuitive navigation.
- **Open Source:** GPLv3 licensed and available on [Google Play](https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile) and [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile).

---

## Multiple Router Functionality

- **Add Unlimited Routers:** Each with its own credentials and settings.
- **Quick Switch:** Instantly switch routers from the dashboard dropdown or "Manage Routers" screen.
- **Isolated Data:** Each router’s dashboard, clients, and settings are kept separate.
- **Edit & Remove:** Update credentials, rename, or remove routers at any time.
- **Auto-Connect:** Remembers your last selected router and auto-connects on launch.
- **Secure Storage:** All credentials are stored securely on your device.

---

## Screenshots

| Login | Dashboard | Clients | Interfaces |
|-------|-----------|---------|------------|
| <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_02.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_01.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_03.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_05.png" width="200"/> |

---

## Installation

**Get it on [Google Play](https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile)**, **[Apple App Store](https://apps.apple.com/app/luci-mobile/id6749455847)**, or **[IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile)**, or build from source:

```bash
git clone https://github.com/cogwheel0/luci-mobile.git
cd luci-mobile
flutter pub get
flutter run
```

- Requires Flutter 3.32.5+ and Dart 3.8+
- Android: `flutter build apk`  
- iOS: `flutter build ios`

---

## Project Structure

```
lib/
├── config/                 # App configuration
├── models/                 # Data models (client, interface, router)
├── screens/                # UI screens (dashboard, clients, interfaces, login, more, etc.)
├── services/               # Business logic (API, secure storage)
├── state/                  # State management (app_state.dart)
├── widgets/                # Reusable UI components (luci_app_bar.dart)
└── main.dart               # App entry point
```

---

## Teltonika RUTOS walkthrough

This project now has first-class support for Teltonika RUTOS devices such as the RUT206. The app uses the router’s native REST API under `/api/` instead of the older LuCI-style RPC flow.

For a detailed summary of findings, fixes, reproduction steps, and troubleshooting commands, see the RUTOS & Debugging Walkthrough: [docs/RUTOS_and_Debugging_Walkthrough.md](docs/RUTOS_and_Debugging_Walkthrough.md)

### What the app now does

- Logs in through `POST /api/login`
- Uses the returned bearer token for subsequent requests
- Reads system, network, DHCP, and wireless data from RUTOS endpoints
- Accepts the router certificate warning once and continues using the connection

### Step-by-step: connect and log in

1. Connect the phone and the router to the same LAN.
2. Open the router web UI at `https://192.168.1.1` and confirm that the login page works.
3. In the app, enter the router IP (for example `192.168.1.1`), the username (usually `admin`), and the router password.
4. If a certificate warning appears, accept it once so the app can continue.
5. After login, the app fetches data from the following RUTOS endpoints:
   - `/api/system/device/status`
   - `/api/system/device/usage/status`
   - `/api/interfaces/basic/status`
   - `/api/dhcp/leases/ipv4/status`
   - `/api/wireless/interfaces/status`
   - `/api/wireless/interfaces/config`

### Quick live checks from the shell

```bash
ROUTER_IP=192.168.1.1
USER=admin
PASS='your-router-password'

# 1) Login and extract the token
LOGIN_JSON=$(curl -sk -X POST "https://${ROUTER_IP}/api/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${USER}\",\"password\":\"${PASS}\"}")

echo "$LOGIN_JSON"
TOKEN=$(python3 - <<'PY'
import json, os
payload = json.loads(os.environ['LOGIN_JSON'])
print(payload['data']['token'])
PY
)

# 2) Read board/system info
curl -sk "https://${ROUTER_IP}/api/system/device/status" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Accept-Encoding: identity'

# 3) Read interfaces and DHCP leases
curl -sk "https://${ROUTER_IP}/api/interfaces/basic/status" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Accept-Encoding: identity'

curl -sk "https://${ROUTER_IP}/api/dhcp/leases/ipv4/status" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Accept-Encoding: identity'
```

### Build and install the Android APK

The commands below were used successfully for sideloading the app onto the Samsung device:

```bash
cd /home/duser/prj/luci-mobile
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"
flutter pub get
flutter build apk --debug
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If `adb` is not found, use the full path directly:

```bash
$HOME/Android/Sdk/platform-tools/adb devices
```

If the phone shows `unauthorized`, disconnect/reconnect USB debugging and approve the prompt on the device before retrying.

### Troubleshooting

- If the app says “Login failed”, verify that `/api/login` responds successfully from the router.
- If the app connects but shows no data, confirm that the certificate warning was accepted and that the bearer token is being sent.
- If `adb install` fails, prefer the debug APK for sideloading, as that was the path that succeeded during testing.

### Files involved in the RUTOS integration

- [lib/services/api_service.dart](lib/services/api_service.dart): login flow and RUTOS endpoint mapping
- [lib/services/auth_service.dart](lib/services/auth_service.dart): stores the authenticated token
- [lib/services/throughput_service.dart](lib/services/throughput_service.dart): handles RUTOS byte-counter payloads
- [lib/utils/http_client_manager.dart](lib/utils/http_client_manager.dart): handles HTTPS certificate acceptance

---

## Development & Contribution

- Run in dev mode: `flutter run`
- Build for release: `flutter build apk --release` or `flutter build ios --release`
- Analyze code: `flutter analyze`

**Contributions welcome!** Please fork, branch, and submit a pull request.

---

## Security & Privacy
- All credentials are stored securely on-device
- HTTPS and self-signed certificate support
- No analytics or tracking

---

## Troubleshooting

- **Connection Failed:** Check router IP, LuCI web interface, firewall, and try both HTTP/HTTPS.
- **Authentication Failed:** Verify credentials and admin privileges.
- **No Data Displayed:** Ensure the router has LuCI RPC support: `opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status`, restart `rpcd` (or reboot), then verify with `ubus list luci-rpc` and `ubus call luci-rpc getNetworkDevices '{}'`.

---

## License

GPL v3.0. See [LICENSE](LICENSE).

---

## Acknowledgments
- OpenWrt community for LuCI
- Flutter team
- [OpenWrtManager](https://github.com/hagaygo/OpenWrtManager) inspiration
- Contributors and testers

---

**Note:** This app requires an OpenWrt router with LuCI web interface enabled. Make sure your router is properly configured before use.
