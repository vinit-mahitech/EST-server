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
echo "[1/7] Installing dependencies..."
sudo apt update
sudo apt install -y git build-essential cmake libssl-dev curl

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
echo "[4/7] Generating CA certificates..."
cd "$SERVER_DIR"
./createCA.sh

# ===== STEP 5: Prepare cacert.pem =====
echo "[5/7] Preparing cacert.pem..."
cd "$SERVER_DIR/estCA"
cp -f cacert.crt cacert.pem

CACERT_PATH="$SERVER_DIR/estCA/cacert.pem"

echo ""
echo "✅ CA Certificate Path:"
echo "$CACERT_PATH"
echo ""

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
echo "server_url: https://$IP_ADDR/.well-known/est"
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