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

## Teltonika RUTOS Support

This build targets **Teltonika RUTOS** (RUT206 and compatible devices running RUTOS firmware, e.g. `RUTE_R_GPL_00.07.23.6`).

### How authentication works on RUTOS

Standard OpenWrt/LuCI uses a form POST to `/cgi-bin/luci/` that returns a `sysauth` session cookie.  
RUTOS replaces the LuCI web-UI with **VuCI** and exposes a REST API at `/api/`. Authentication is different:

| Step | Method | Endpoint | Body |
|------|--------|----------|------|
| Login | `POST` | `https://<ip>/api/login` | `{"username":"admin","password":"..."}` |
| Response | — | — | `{"success":true,"data":{"token":"<32-hex>","expires":299,"username":"admin","group":"root"}}` |

The returned `token` is the same ubus session token used for all subsequent `POST /ubus` JSON-RPC calls.

### ubus JSON-RPC endpoint

All API calls go to **`/ubus`** (not `/cgi-bin/luci/admin/ubus`).  
Standard format:
```json
{"jsonrpc":"2.0","id":1,"method":"call","params":["<token>","<object>","<method>",{}]}
```

### API mapping: luci-rpc → RUTOS

`luci-rpc` is **not available** on RUTOS. The app translates these calls transparently:

| luci-rpc method | RUTOS equivalent | Notes |
|-----------------|-----------------|-------|
| `getNetworkDevices` | `network.device status {}` | TX/RX stats under `statistics.rx_bytes` / `statistics.tx_bytes` |
| `getDHCPLeases` | `dnsmasq ipv4leases` | Normalized to `{dhcp_leases:[{macaddr,ipaddr,hostname,leasetime}]}` |
| `getWirelessDevices` | `network.wireless status {}` | Same `interfaces[*].ifname` structure |

### Confirmed working ubus objects on RUT206

```
system board         → hostname, model, kernel
system info          → uptime, load, memory
network.interface dump  → interface list with IPs, routes
network.device status   → per-device TX/RX byte counters
network.wireless status → radio config and interface names
dnsmasq ipv4leases   → active DHCP leases
iwinfo devices       → list wireless interfaces
iwinfo assoclist     → associated wireless clients
uci get/set/commit   → UCI config read/write
rpc-sys reboot       → remote reboot
```

### SSH investigation (sshpass)
```bash
# Firmware
sshpass -p 'PASSWORD' ssh root@192.168.1.1 "cat /etc/openwrt_release"

# Confirm no luci-rpc
sshpass -p 'PASSWORD' ssh root@192.168.1.1 "ubus list luci-rpc"

# Test login
curl -sk -X POST https://192.168.1.1/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"PASSWORD"}'

# Test ubus call with token
TOKEN=<token from above>
curl -sk -X POST https://192.168.1.1/ubus \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$TOKEN\",\"system\",\"board\",{}]}"
```

### Code changes made (vs upstream)

| File | Change |
|------|--------|
| `lib/services/api_service.dart` | `_login()` uses `POST /api/login` with JSON body; `callWithContext()` posts to `/ubus`; `luci-rpc` calls transparently translated to RUTOS equivalents; `_callRutosDhcpLeases()` normalises dnsmasq lease format |
| `lib/services/throughput_service.dart` | Added `statistics.rx_bytes/tx_bytes` format (RUTOS `network.device status`) alongside existing `stats.*` and direct `rx_bytes` formats |
| `lib/state/app_state.dart` | `_pingRouter()` uses `/` and `/api/login` instead of LuCI-specific paths |

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
