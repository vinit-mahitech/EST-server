# ELO 802.1X Test Environment Setup

This repository contains two scripts to set up a complete local 802.1X enterprise authentication environment for testing ELO devices:

| Script | Purpose |
|---|---|
| `setup_est_server.sh` | Sets up the EST (Enrollment over Secure Transport) server using Cisco `libest` |
| `setup_freeradius.sh` | Sets up FreeRADIUS + hostapd for 802.1X PEAP/MSCHAPv2 authentication |

---

## Prerequisites

- Ubuntu/Debian Linux PC
- Run `setup_est_server.sh` **before** `setup_freeradius.sh` (RADIUS cert is signed by the EST CA)
- Direct ethernet cable between PC and ELO device (EAPOL is Layer 2 — does not pass through a router)

---

## setup_est_server.sh

Automates the setup of a local EST server using Cisco `libest`.

### What it does

- Clones libest source (if not already present)
- Builds and installs libest
- Generates CA certificates
- Creates `cacert.pem` from the generated CA
- Generates a server TLS cert with correct IP SAN
- Configures firewall to allow EST port (8085)
- Starts the EST server

### Usage

```bash
chmod +x setup_est_server.sh
./setup_est_server.sh
```

### Output

```
server_url : <SERVER_IP>
port       : 8085
username   : estuser
password   : estpwd
ca_cert    : libest/example/server/estCA/cacert.pem
```

### Test command (run from another PC on the same network)

```bash
curl -k https://<SERVER_IP>:8085/.well-known/est/cacerts
```

---

## setup_freeradius.sh

Automates FreeRADIUS setup for PEAP/MSCHAPv2 and generates a `hostapd_wired.conf` to use the PC as a wired 802.1X authenticator.

### What it does

1. Detects the ethernet interface automatically (`enp3s0`, `eth0`, etc.)
2. Installs FreeRADIUS and hostapd (skips if already installed)
3. Generates a RADIUS server TLS cert signed by the EST CA
4. Configures EAP module for PEAP/MSCHAPv2
5. Adds EAP user credentials to the correct authorize file
6. Configures RADIUS client subnet in `clients.conf`
7. Generates DH parameters (if missing)
8. Starts FreeRADIUS
9. Generates `hostapd_wired.conf` and starts hostapd

### Usage

```bash
chmod +x setup_freeradius.sh
./setup_freeradius.sh
```

### Output

```
RADIUS server IP  : <SERVER_IP>
RADIUS port       : 1812
RADIUS secret     : testing123
EAP user          : estuser
EAP password      : estpwd
```

### Test RADIUS auth

```bash
radtest estuser estpwd <SERVER_IP> 0 testing123
```

Expected: `Received Access-Accept`

---

## Full Stack Architecture

```
ELO Device (eth0)
      |
      | EAPOL (Layer 2 — direct cable only, no router)
      ↓
PC running hostapd (enp3s0)
      |
      | RADIUS/UDP (Layer 3)
      ↓
FreeRADIUS (port 1812)
      |
      | PEAP/MSCHAPv2 inner tunnel
      ↓
EST CA (cacert.pem) — used to verify RADIUS server cert
```

---

## Testing & Debug
---

### Step 1 — Static IP setup (direct cable mode, no router)

**On PC:**
```bash
sudo ip addr flush dev enp3s0
sudo ip addr add 192.168.100.1/24 dev enp3s0
sudo ip link set enp3s0 up
```

**On ELO device (via ADB):**
```bash
adb shell ip addr flush dev eth0
adb shell ip addr add 192.168.100.2/24 dev eth0
adb shell ip link set eth0 up
```

---

### Step 2 — Start the FreeRADIUS logs in debug mode

```bash
sudo systemctl stop freeradius
sudo freeradius -X
```

---

### Step 3 — Verify RADIUS auth independently

Before connecting the device, confirm FreeRADIUS is working:
```bash
radtest estuser estpwd 192.168.100.1 0 testing123
```
Expected output:
```
Received Access-Accept
```

---

### Step 4 — Expected success sequence

**FreeRADIUS should show:**
```
files: users: Matched entry estuser at line 1
mschap: Found Cleartext-Password, hashing to create NT-Password
eap_peap: Tunneled authentication was successful
Sent Access-Accept
```

**hostapd should show:**
```
CTRL-EVENT-EAP-STARTED
IEEE 802.1X: authenticated - EAP type: 25 (PEAP)
AP-STA-CONNECTED 1c:ee:c9:40:00:13
```

**Device logs should show:**
```
EAPOL: SUPP_PAE entering state AUTHENTICATED
EAP: Authentication completed successfully
```

---

### Teardown — Restore DHCP after testing

```bash
# Remove static IP
sudo ip addr del 192.168.100.1/24 dev enp3s0

# Re-request DHCP from router
sudo dhclient enp3s0

# Verify IP restored
ip addr show enp3s0
```

---

### Common failures and fixes

| Symptom | Cause | Fix |
|---|---|---|
| `[files] = noop` in FreeRADIUS | User entry in wrong file | Add to `/etc/freeradius/3.0/mods-config/files/authorize` not `/users` |
| `No Cleartext-Password` | Spaces instead of tab in user entry | Use `printf '%s\t'` — verify with `cat -A` shows `^I` |
| `No Auth-Type found` | User not found at all | Check `sudo cat -A /etc/freeradius/3.0/mods-config/files/authorize \| head -3` |
| hostapd: `authentication failed - EAP type: 25` | RADIUS rejecting | Fix FreeRADIUS first, confirm `radtest` returns `Access-Accept` |
| Device keeps retrying EAPOL | Auth loop | Check FreeRADIUS -X output for root cause |
| `[files] = noop` after correct file | `mods-enabled/files` not symlinked | `sudo ln -s ../mods-available/files /etc/freeradius/3.0/mods-enabled/` |

---

## Notes

- **Direct cable required** — EAPOL frames are Layer 2 and do not pass through a router or switch unless it supports 802.1X (managed switch)
- The RADIUS server cert is signed by the EST CA — both scripts must share the same `libest` directory
- The ethernet interface is detected automatically — no hardcoded `eth0`
- The user credentials file is written to `/etc/freeradius/3.0/mods-config/files/authorize` (not `/etc/freeradius/3.0/users`)
- For production/customer environments, replace hostapd with a managed 802.1X switch (Cisco, HP/Aruba, TP-Link managed series)
