# 802.1X Enterprise Wi-Fi Test Suite (EST + FreeRADIUS)

An all-in-one test setup for automated **Enrollment over Secure Transport (EST)** certificate provisioning and **802.1X Enterprise Wi-Fi authentication**.

This repository provides scripts to spin up a local EST server (using Cisco `libest`) and a **FreeRADIUS** server supporting all 4 major EAP authentication methods (**EAP-TLS**, **EAP-PEAP**, **EAP-TTLS**, **EAP-PWD**) simultaneously.

---

## 🚀 Supported EAP Methods

| EAP Method | EAP ID | Authentication Type | Required Credentials |
| :--- | :--- | :--- | :--- |
| **EAP-TLS** | `method=13` | EST Client & Server Certificates | CA Cert (`test<Serial>_ca`), User Cert (`test<Serial>_user`), Domain |
| **EAP-PEAP** | `method=25` | Inner Tunnel Username & Password | User: `estuser`, Pass: `estpwd` |
| **EAP-TTLS** | `method=21` | Tunneled TLS Username & Password | User: `estuser`, Pass: `estpwd` |
| **EAP-PWD** | `method=52` | Pre-Shared Password (Dragonfly ECC) | User: `estuser`, Pass: `estpwd` |

---

## 🏗️ System Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Linux PC (Server Host)                           │
│                                                                             │
│ 1. Cisco libest EST Server (Port 8085) ──► Issues client/CA certs           │
│ 2. FreeRADIUS Server (Port 1812)     ──► Handles TLS / PEAP / TTLS / PWD    │
└──────────────────────┬──────────────────────────────────────────────────────┘
                       │ RADIUS (UDP Port 1812)
                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Hardware Access Point (Router)                      │
│                                                                             │
│ • SSID: est-test (or custom SSID)                                           │
│ • Security: WPA/WPA2-Enterprise (802.1X)                                    │
│ • Primary RADIUS Server IP: <PC_IP> (Port 1812, Secret: testing123)         │
└──────────────────────┬──────────────────────────────────────────────────────┘
                       │ Wi-Fi (802.1X EAP)
                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Android Test Device                              │
│                                                                             │
│ 1. Test App / SDK ─────► Enrolls client certificate from EST server         │
│ 2. Android Settings ───► Connects using EAP-TLS / PEAP / TTLS / PWD         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Prerequisites

- **Linux PC** (Ubuntu / Debian recommended)
- **Hardware Wi-Fi Router** with **WPA/WPA2-Enterprise** support
- **Android Device** connected to the same local network

---

## 🛠️ Installation & Setup

### Step 1: Clone Repository & Start EST Server

Run `setup_est_server.sh` to clone/build Cisco `libest`, generate the CA certificates, and start the EST server on port `8085`:

```bash
./setup_est_server.sh
```

*Verify EST Server:*
```bash
curl -k https://<YOUR_PC_IP>:8085/.well-known/est/cacerts
```

---

### Step 2: Configure & Start FreeRADIUS

Run `setup_all_eap_freeradius.sh` to configure FreeRADIUS with the EST CA certificates and enable support for all 4 EAP methods. The script automatically launches FreeRADIUS in live debug mode (`-X`) at the end:

```bash
./setup_all_eap_freeradius.sh
```

---

### Step 3: Configure Wireless Router (WPA-Enterprise)

Log into your Wi-Fi router's admin interface (e.g. `http://192.168.0.1`):

1. **SSID**: Set to `est-test`.
2. **Security Mode**: Select **WPA/WPA2-Enterprise** (or 802.1X Enterprise).
3. **Primary RADIUS Server IP**: Set to your PC's IP address.
4. **RADIUS Port**: `1812`
5. **Shared Secret / Password**: `testing123`
6. Save & Apply.

---

## 🔌 Direct Wired Ethernet Testing (No Switch / Router Needed)

If you need to test **Wired 802.1X Ethernet (`eth0`)** directly using an Ethernet cable without an 802.1X hardware switch or router, run `setup_wired_hostapd.sh` on your PC:

```bash
./setup_wired_hostapd.sh
```

### What `setup_wired_hostapd.sh` does:
1. Detects your PC's Ethernet interface and assigns static IP `192.168.100.1/24`.
2. Generates `hostapd_wired.conf` configured for `driver=wired` pointing to FreeRADIUS (`127.0.0.1:1812`).
3. Starts `hostapd` in wired mode to turn your PC's Ethernet port into a **Software 802.1X Port Authenticator**.

### Configure Android Device IP for Direct Link:
Run these commands via ADB to set static IP on your test device:
```bash
adb shell ip addr flush dev eth0
adb shell ip addr add 192.168.100.2/24 dev eth0
adb shell ip link set eth0 up
```

Then go to **Android Settings -> Ethernet -> 802.1X EAP** and select your desired EAP method (**EAP-TLS**, **PEAP**, **TTLS**, or **PWD**).

---

## 📱 Device Connection Guide

**Enroll Certificate**: Use your test app / SDK to enroll a certificate from `https://<YOUR_PC_IP>:8085`.

### A. EAP-TLS (Certificate Authentication)

**Connect Wi-Fi (`est-test`)**:
   - **EAP method**: `TLS`
   - **CA certificate**: `test<Serial>_ca`
   - **User certificate**: `test<Serial>_user`
   - **Online Certificate Status**: `Do not verify`
   - **Domain**: `localhost` *(or `<YOUR_PC_IP>`)*
   - **Identity**: `estuser`
   - Tap **Connect**.

---

### B. EAP-PEAP (Username & Password)

**Connect Wi-Fi (`est-test`)**:
   - **EAP method**: `PEAP`
   - **Phase 2 authentication**: `MSCHAPV2`
   - **CA certificate**: `test<Serial>_ca`
   - **Online Certificate Status**: `Do not verify`
   - **Domain**: `<YOUR_PC_IP>`
   - **User certificate**: `Do not provide`
   - **Identity**: `estuser`
   - **Password**: `estpwd`
   - Tap **Connect**.

---

### C. EAP-TTLS (Tunneled TLS)

**Connect Wi-Fi (`est-test`)**:
   - **EAP method**: `TTLS`
   - **Phase 2 authentication**: `MSCHAPV2`
   - **CA certificate**: `test<Serial>_ca`
   - **Online Certificate Status**: `Do not verify`
   - **Domain**: `<YOUR_PC_IP>`
   - **User certificate**: `Do not provide`
   - **Identity**: `estuser`
   - **Password**: `estpwd`
   - Tap **Connect**.

---

### D. EAP-PWD (Pre-Shared Password)

**Connect Wi-Fi (`est-test`)**:
   - **EAP method**: `PWD`
   - **Identity**: `estuser`
   - **Password**: `estpwd`
   - Tap **Connect**.

---

## 🔍 Debugging & Logs

- **Monitor FreeRADIUS Live Debug Stream**:
  ```bash
  sudo freeradius -X
  ```

- **Monitor Android Wi-Fi & EAP Logs via ADB**:
  ```bash
  adb logcat -c && adb logcat | grep -iE "wpa_supplicant|Wifi|EAP"
  ```
