#!/bin/bash

set -e

# ===== CONFIG =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBEST_DIR="$SCRIPT_DIR/libest"
SERVER_DIR="$LIBEST_DIR/example/server"
IP_ADDR=$(hostname -I | awk '{print $1}')
PORT=8085

echo "========================================"
echo " EST SERVER SETUP STARTED"
echo "========================================"

echo "Script directory: $SCRIPT_DIR"
echo "Using IP: $IP_ADDR"
echo ""

# ===== STEP 1: Install dependencies =====
echo "[1/7] Installing dependencies... (ignore)"
#sudo apt update
#sudo apt install -y git build-essential cmake libssl-dev curl

# ===== STEP 2: Clone libest =====
if [ ! -d "$LIBEST_DIR" ]; then
    echo "[2/7] Cloning libest into $SCRIPT_DIR..."
    cd "$SCRIPT_DIR"
    git clone https://github.com/cisco/libest.git
else
    echo "[2/7] libest already exists, skipping clone"
fi

# ===== STEP 3: Build libest =====
echo "[3/7] Building libest..."
cd "$LIBEST_DIR"
./configure --disable-safec
make -j$(nproc)
sudo make install

# ===== STEP 4: Generate CA =====
echo "[4/7] Checking existing CA..."

cd "$SERVER_DIR"

if [ -f "$SERVER_DIR/estCA/cacert.crt" ]; then
    echo "✅ Existing CA found, skipping regeneration"
else
    echo "⚠️ No CA found, generating new CA..."
    ./createCA.sh
fi

# ===== STEP 5: Prepare cacert.pem =====
echo "[5/7] Preparing cacert.pem..."
cd "$SERVER_DIR/estCA"
cp -f cacert.crt cacert.pem

CACERT_PATH="$SERVER_DIR/estCA/cacert.pem"

echo ""
echo "✅ CA Certificate Path:"
echo "$CACERT_PATH"
echo ""

# ===== STEP 5.5: Regenerate server cert with correct IP SAN =====
echo "[5.5/7] Generating server TLS cert with SAN for $IP_ADDR..."

cd "$SERVER_DIR/estCA"

cat > server_san.cnf << EOF
[req]
default_bits       = 2048
prompt             = no
distinguished_name = dn
x509_extensions    = v3_req

[dn]
CN = $IP_ADDR

[v3_req]
subjectAltName = IP:$IP_ADDR
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# Generate new key
openssl genrsa -out private/estserverkey.pem 2048

# Generate CSR
openssl req -new \
    -key private/estserverkey.pem \
    -out estserver.csr \
    -config server_san.cnf

# Sign with the EST CA
openssl x509 -req \
    -in estserver.csr \
    -CA cacert.crt \
    -CAkey private/cakey.pem \
    -CAcreateserial \
    -out estservercert.pem \
    -days 825 \
    -extensions v3_req \
    -extfile server_san.cnf

# Combine cert + key into one file (as runserver.sh expects)
cat estservercert.pem private/estserverkey.pem > private/estservercertandkey.pem

echo "✅ Server cert regenerated with SAN: IP:$IP_ADDR"

cp "$SERVER_DIR/estCA/cacert.crt" "$SERVER_DIR/trustedcerts.crt"
echo "✅ trustedcerts.crt updated"

# Verify
openssl x509 -in private/estservercertandkey.pem -noout -text | grep -A1 "Subject Alternative"

# ===== STEP 6: Allow firewall =====
echo "[6/7] Configuring firewall..."
sudo ufw allow $PORT/tcp || true

# ===== STEP 7: Print test command =====
echo ""
echo "========================================"
echo " TEST COMMAND"
echo "========================================"
echo "curl -k https://$IP_ADDR:$PORT/.well-known/est/cacerts"
echo ""

echo "========================================"
echo " DEVICE CONFIG VALUES"
echo "========================================"
echo "server_url: $IP_ADDR"
echo "port: $PORT"
echo "username: estuser"
echo "password: estpwd"
echo "ca_cert: copy from $CACERT_PATH"
echo ""

# ===== STEP 8: Run server =====
echo "========================================"
echo " STARTING EST SERVER"
echo "========================================"

cd "$SERVER_DIR"
./runserver.sh
