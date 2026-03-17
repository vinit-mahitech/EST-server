
# EST Server Setup Script (libest)

This script automates the setup of a local EST (Enrollment over Secure Transport) server using Cisco `libest`.

It performs:

- Clones libest source code (if not already present)
- Builds and installs libest
- Generates CA certificates
- Creates `cacert.pem` from generated CA
- Configures firewall to allow EST port (8085)
- Displays server details and test commands
- Starts the EST server

---

## Usage

1. Make the script executable:

```bash
chmod +x setup_est_server.sh
````

2. Run the script:

```bash
./setup_est_server.sh
```

The script will execute all setup steps and start the EST server.

---

## Output Information

After execution, the script provides:

### EST Server Endpoint

```
Using IP: <SERVER_IP>
```

### CA Certificate Path

```
✅ CA Certificate Path:
libest/example/server/estCA/cacert.pem
```

### Test Command (run on different pc on same network)

```bash
curl -k https://<SERVER_IP>:8085/.well-known/est/cacerts
```

### Device Configuration Values

```
server_url: <SERVER_IP>
port: 8085
username: estuser
password: estpwd
```
