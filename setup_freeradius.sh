#!/bin/bash

set -e

# ===== CONFIG =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EST_SERVER_DIR="$SCRIPT_DIR/libest/example/server"
CA_CERT="$EST_SERVER_DIR/estCA/cacert.pem"
CA_KEY="$EST_SERVER_DIR/estCA/private/cakey.pem"
ETH_IFACE=$(ip link show | awk '/^[0-9]+:/{iface=$2} /link\/ether/{print iface; exit}' | tr -d ':')

RADIUS_DIR="/etc/freeradius/3.0"
RADIUS_CERTS_DIR="$RADIUS_DIR/certs"

IP_ADDR=$(hostname -I | awk '{print $1}')
RADIUS_PORT=1812
RADIUS_SECRET="testing123"

EAP_USER="estuser"
EAP_PASS="estpwd"

if [ -z "$ETH_IFACE" ]; then
    echo "❌ No ethernet interface found!"
    exit 1
fi

echo "✅ Detected ethernet interface: $ETH_IFACE"

echo "========================================"
echo " FREERADIUS SETUP STARTED"
echo "========================================"
echo "Script directory : $SCRIPT_DIR"
echo "Using IP         : $IP_ADDR"
echo "RADIUS secret    : $RADIUS_SECRET"
echo "EAP user         : $EAP_USER"
echo ""

# ===== STEP 1: Install FreeRADIUS =====
echo "[1/7] Installing FreeRADIUS..."

if dpkg -s freeradius freeradius-utils &>/dev/null 2>&1; then
    echo "✅ FreeRADIUS already installed, skipping"
else
    sudo apt update -qq
    sudo apt install -y freeradius freeradius-utils
    echo "✅ FreeRADIUS installed"
fi

echo "✅ FreeRADIUS installed"

# ===== STEP 2: Stop service before editing =====
echo "[2/7] Stopping FreeRADIUS service..."
sudo systemctl stop freeradius || true

# ===== STEP 3: Generate RADIUS server cert from existing EST CA =====
echo "[3/7] Generating RADIUS server cert signed by EST CA..."

if [ ! -f "$CA_CERT" ]; then
    echo "❌ EST CA cert not found at: $CA_CERT"
    echo "   Please run setup_est_server.sh first!"
    exit 1
fi

if [ ! -f "$CA_KEY" ]; then
    echo "❌ EST CA key not found at: $CA_KEY"
    echo "   Please run setup_est_server.sh first!"
    exit 1
fi

echo "✅ Found EST CA at: $CA_CERT"

# Generate RADIUS server key
sudo openssl genrsa -out "$RADIUS_CERTS_DIR/server.key" 2048

# Generate CSR for RADIUS server
sudo openssl req -new \
    -key "$RADIUS_CERTS_DIR/server.key" \
    -out "$RADIUS_CERTS_DIR/server.csr" \
    -subj "/CN=radius.$IP_ADDR/O=ELO RADIUS"

# Sign RADIUS server cert with the EST CA
sudo openssl x509 -req \
    -in "$RADIUS_CERTS_DIR/server.csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$RADIUS_CERTS_DIR/server.pem" \
    -days 825

# Copy EST CA cert as trusted CA for RADIUS
sudo cp "$CA_CERT" "$RADIUS_CERTS_DIR/ca.pem"

# Set correct permissions
sudo chmod 640 "$RADIUS_CERTS_DIR/server.key"
sudo chown freerad:freerad "$RADIUS_CERTS_DIR/server.key"
sudo chown freerad:freerad "$RADIUS_CERTS_DIR/server.pem"
sudo chown freerad:freerad "$RADIUS_CERTS_DIR/ca.pem"

echo "✅ RADIUS server cert generated and signed by EST CA"

# ===== STEP 4: Configure EAP (PEAP + MSCHAPV2) =====
echo "[4/7] Configuring EAP module (PEAP/MSCHAPv2)..."

sudo tee "$RADIUS_DIR/mods-available/eap" > /dev/null << 'EOF'
eap {
    default_eap_type = peap

    timer_expire = 60
    ignore_unknown_eap_types = no
    cisco_accounting_username_bug = no
    max_sessions = ${max_requests}

    tls-config tls-common {
        private_key_file     = ${certdir}/server.key
        certificate_file     = ${certdir}/server.pem
        ca_file              = ${certdir}/ca.pem
        dh_file              = ${certdir}/dh
        random_file          = /dev/urandom
        ca_path              = ${cadir}
        cipher_list          = "DEFAULT"
        cipher_server_preference = no
        tls_min_version      = "1.0"
        tls_max_version      = "1.2"
        ecdh_curve           = "prime256v1"
        cache {
            enable = no
        }
        verify {
        }
        ocsp {
            enable = no
        }
    }

    peap {
        tls = tls-common
        default_eap_type = mschapv2
        copy_request_to_tunnel = no
        use_tunneled_reply = no
        virtual_server = "inner-tunnel"
    }

    mschapv2 {
    }
}
EOF

echo "✅ EAP module configured"

# ===== STEP 5: Configure users (estuser/estpwd) =====
echo "[5/7] Adding EAP user credentials..."

# Add user to the correct authorize file (prepend so it takes priority)
USERS_FILE="$RADIUS_DIR/mods-config/files/authorize"

# Remove existing estuser entry if present
sudo sed -i "/^$EAP_USER/d" "$USERS_FILE"

# Add fresh entry at the top with correct tab delimiter
sudo sed -i "1s/^/$(printf '%s\t' "$EAP_USER")Cleartext-Password := \"$EAP_PASS\"\n\n/" "$USERS_FILE"

# Verify
sudo cat -A "$USERS_FILE" | head -3

echo "✅ User '$EAP_USER' added with password '$EAP_PASS'"

# ===== STEP 6: Configure clients.conf (allow device subnet) =====
echo "[6/7] Configuring RADIUS clients..."

SUBNET=$(echo "$IP_ADDR" | cut -d. -f1-3).0/24

# Remove existing elo_device_subnet entry if present
sudo sed -i '/# === Added by setup_freeradius.sh ===/,/^}/d' "$RADIUS_DIR/clients.conf"

# Add fresh entry
sudo tee -a "$RADIUS_DIR/clients.conf" > /dev/null << EOF

# === Added by setup_freeradius.sh ===
client elo_device_subnet {
    ipaddr          = $SUBNET
    secret          = $RADIUS_SECRET
    shortname       = elo_devices
    nas_type        = other
}
EOF

echo "✅ Client subnet $SUBNET added with secret '$RADIUS_SECRET'"

# ===== STEP 7: Generate DH params if missing =====
if [ ! -f "$RADIUS_CERTS_DIR/dh" ]; then
    echo "[7/7] Generating DH parameters (this may take a minute)..."
    sudo openssl dhparam -out "$RADIUS_CERTS_DIR/dh" 2048
    sudo chown freerad:freerad "$RADIUS_CERTS_DIR/dh"
else
    echo "[7/7] DH parameters already exist, skipping"
fi

# ===== Start FreeRADIUS =====
echo ""
echo "========================================"
echo " STARTING FREERADIUS"
echo "========================================"

sudo systemctl enable freeradius
sudo systemctl start freeradius

sleep 2

if systemctl is-active --quiet freeradius; then
    echo "✅ FreeRADIUS is running!"
else
    echo "❌ FreeRADIUS failed to start. Running in debug mode for diagnosis..."
    echo ""
    sudo freeradius -X 2>&1 | head -60
    exit 1
fi

# ===== Firewall =====
echo ""
echo "[+] Configuring firewall..."
sudo ufw allow $RADIUS_PORT/udp || true
sudo ufw allow 1813/udp || true   # RADIUS accounting

# ===== Test =====
echo ""
echo "========================================"
echo " TEST COMMAND"
echo "========================================"
echo "radtest $EAP_USER $EAP_PASS $IP_ADDR 0 $RADIUS_SECRET"
echo ""
echo "Run the above to verify RADIUS auth works."
echo ""

echo "========================================"
echo " SWITCH / HOSTAPD CONFIG VALUES"
echo "========================================"
echo "RADIUS server IP  : $IP_ADDR"
echo "RADIUS port       : $RADIUS_PORT"
echo "RADIUS secret     : $RADIUS_SECRET"
echo "EAP user          : $EAP_USER"
echo "EAP password      : $EAP_PASS"
echo "CA cert (for NAS) : $CA_CERT"
echo ""

# ===== Install hostapd if not installed =====
if ! dpkg -s hostapd &>/dev/null 2>&1; then
    echo "[+] Installing hostapd..."
    sudo apt install -y hostapd
else
    echo "✅ hostapd already installed, skipping"
fi

# Generate hostapd wired config
HOSTAPD_CONF="$SCRIPT_DIR/hostapd_wired.conf"
cat > "$HOSTAPD_CONF" << EOF
# hostapd wired 802.1X authenticator config
# Generated by setup_freeradius.sh
# Usage: sudo hostapd $HOSTAPD_CONF

interface=$ETH_IFACE
driver=wired
logger_syslog=-1
logger_stdout=-1
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

ieee8021x=1
eap_reauth_period=3600

# RADIUS server
auth_server_addr=$IP_ADDR
auth_server_port=$RADIUS_PORT
auth_server_shared_secret=$RADIUS_SECRET

# EAP
eapol_version=2
EOF

echo ""
echo "✅ hostapd_wired.conf written to: $HOSTAPD_CONF"
echo ""
echo "========================================"
echo " STARTING hostpd"
echo "========================================"
sudo hostapd $HOSTAPD_CONF

