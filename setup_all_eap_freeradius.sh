#!/bin/bash

set -e

# Install FreeRADIUS if not installed

if ! command -v freeradius >/dev/null 2>&1; then
    echo "FreeRADIUS not found. Installing..."

    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y freeradius

    echo "FreeRADIUS installed."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EST_SERVER_DIR="$SCRIPT_DIR/libest/example/server"
CA_CERT="$EST_SERVER_DIR/estCA/cacert.pem"
CA_KEY="$EST_SERVER_DIR/estCA/private/cakey.pem"

RADIUS_DIR="/etc/freeradius/3.0"
RADIUS_CERTS_DIR="$RADIUS_DIR/certs"

IP_ADDR=$(hostname -I | awk '{print $1}')
RADIUS_PORT=1812
RADIUS_SECRET="testing123"

EAP_USER="estuser"
EAP_PASS="estpwd"

echo "========================================"
echo " FREERADIUS ALL-IN-ONE EAP SETUP"
echo " (TLS, PEAP, TTLS, PWD Supported)"
echo "========================================"
echo "IP Address    : $IP_ADDR"
echo "RADIUS secret : $RADIUS_SECRET"
echo "EST CA        : $CA_CERT"
echo "EAP User      : $EAP_USER"
echo "EAP Pass      : $EAP_PASS"
echo ""

# Stop FreeRADIUS service before configuring
sudo systemctl stop freeradius || true

if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
    echo "❌ EST CA cert/key not found at $CA_CERT! Run setup_est_server.sh first."
    exit 1
fi

# Ensure RADIUS server cert is generated and signed by EST CA
sudo openssl genrsa -out "$RADIUS_CERTS_DIR/server.key" 2048
sudo openssl req -new \
    -key "$RADIUS_CERTS_DIR/server.key" \
    -out "$RADIUS_CERTS_DIR/server.csr" \
    -subj "/CN=radius.$IP_ADDR/O=RADIUS Server"

sudo openssl x509 -req \
    -in "$RADIUS_CERTS_DIR/server.csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$RADIUS_CERTS_DIR/server.pem" \
    -days 825

sudo cp "$CA_CERT" "$RADIUS_CERTS_DIR/ca.pem"

sudo chmod 640 "$RADIUS_CERTS_DIR/server.key"
sudo chown freerad:freerad "$RADIUS_CERTS_DIR/server.key"
sudo chown freerad:freerad "$RADIUS_CERTS_DIR/server.pem"
sudo chown freerad:freerad "$RADIUS_CERTS_DIR/ca.pem"

# Generate DH params if missing
if [ ! -f "$RADIUS_CERTS_DIR/dh" ]; then
    echo "[+] Generating DH parameters..."
    sudo openssl dhparam -out "$RADIUS_CERTS_DIR/dh" 2048
    sudo chown freerad:freerad "$RADIUS_CERTS_DIR/dh"
fi

# Configure EAP module supporting TLS, PEAP, TTLS, PWD, and MSCHAPv2
sudo tee "$RADIUS_DIR/mods-available/eap" > /dev/null << 'EOF'
eap {
    default_eap_type = tls

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

    # 1. EAP-TLS (Certificates - EST Enrolled)
    tls {
        tls = tls-common
    }

    # 2. EAP-PEAP (Username & Password - MSCHAPv2)
    peap {
        tls = tls-common
        default_eap_type = mschapv2
        copy_request_to_tunnel = no
        use_tunneled_reply = no
        virtual_server = "inner-tunnel"
    }

    # 3. EAP-TTLS (Tunneled TLS - MSCHAPv2)
    ttls {
        tls = tls-common
        default_eap_type = mschapv2
        copy_request_to_tunnel = no
        use_tunneled_reply = no
        virtual_server = "inner-tunnel"
    }

    # 4. EAP-PWD (Pre-Shared Password)
    pwd {
        group = 19
        server_id = radius.local
        fragment_size = 1020
    }

    mschapv2 {
    }
}
EOF

# Ensure mods-enabled symlink exists
sudo ln -sf "$RADIUS_DIR/mods-available/eap" "$RADIUS_DIR/mods-enabled/eap"

# Add EAP user credentials for PEAP/TTLS/PWD
USERS_FILE="$RADIUS_DIR/mods-config/files/authorize"
sudo sed -i "/^$EAP_USER/d" "$USERS_FILE"
sudo sed -i "1s/^/$(printf '%s\t' "$EAP_USER")Cleartext-Password := \"$EAP_PASS\"\n\n/" "$USERS_FILE"

# Configure client subnet in clients.conf
sudo sed -i '/# === Added by setup_freeradius.sh ===/,/^}/d' "$RADIUS_DIR/clients.conf"
sudo tee -a "$RADIUS_DIR/clients.conf" > /dev/null << EOF

# === Added by setup_freeradius.sh ===
client all_clients {
    ipaddr          = 0.0.0.0/0
    secret          = $RADIUS_SECRET
    shortname       = all_clients
    nas_type        = other
}
EOF

echo "✅ FreeRADIUS All-in-One EAP (TLS, PEAP, TTLS, PWD) setup completed!"
echo ""
echo "========================================"
echo " STARTING FREERADIUS IN DEBUG MODE (-X)"
echo "========================================"
sudo freeradius -X
