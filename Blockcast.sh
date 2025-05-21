#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

curl -s https://raw.githubusercontent.com/godevid/godevid.github.io/a28914cdb7405768908765f349547ba7ac294a40/logo.sh | bash
echo -e "${CYAN}Node Setup Blockcast${NC}"
sleep 5

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local border="-----------------------------------------------------"
    echo -e "${border}"
    case $level in
        "INFO") echo -e "${CYAN}[INFO] ${timestamp} - ${message}${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS] ${timestamp} - ${message}${NC}" ;;
        "ERROR") echo -e "${RED}[ERROR] ${timestamp} - ${message}${NC}" ;;
        *) echo -e "${YELLOW}[UNKNOWN] ${timestamp} - ${message}${NC}" ;;
    esac
    echo -e "${border}\n"
}

log "INFO" "System update & upgrade"
sudo apt update && sudo apt upgrade -y || {
    log "ERROR" "Failed to update system"
    exit 1
}

if ! command -v docker &> /dev/null; then
    log "INFO" "Installing Docker"
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    log "SUCCESS" "Docker installed"
else
    log "INFO" "Docker already installed"
fi

log "INFO" "Preparing Blockcast-Node folder"
rm -rf $HOME/Blockcast-Node
mkdir -p $HOME/Blockcast-Node
cd $HOME/Blockcast-Node

log "INFO" "Writing Docker Compose file"
cat > docker-compose.yml <<EOF
x-service: &service
  image: blockcast/cdn_gateway_go:\${IMAGE_VERSION:-stable}
  restart: always
  network_mode: "service:blockcastd"
  volumes:
    - \${HOME}/.blockcast/certs:/var/opt/magma/certs
    - \${HOME}/.blockcast/snowflake:/etc/snowflake
    - /var/run/docker.sock:/var/run/docker.sock
  labels:
    - "com.centurylinklabs.watchtower.enable=true"

services:
  control_proxy:
    <<: *service
    container_name: control_proxy
    command: /usr/bin/control_proxy

  blockcastd:
    <<: *service
    container_name: blockcastd
    command: /usr/bin/blockcastd -logtostderr=true -v=0
    network_mode: bridge

  beacond:
    <<: *service
    container_name: beacond
    command: /usr/bin/beacond -logtostderr=true -v=0

  watchtower:
    image: containrrr/watchtower
    environment:
      WATCHTOWER_LABEL_ENABLE: "true"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
EOF

log "INFO" "Starting Blockcast Node (1st run)"
docker compose up -d || {
    log "ERROR" "Gagal menjalankan docker compose"
    exit 1
}

sleep 5

log "INFO" "Stopping containers (simulasi down)"
docker compose down || {
    log "ERROR" "Gagal menghentikan container"
    exit 1
}

sleep 2

log "INFO" "Starting Blockcast Node again (final run)"
docker compose up -d || {
    log "ERROR" "Failed to re run docker compose"
    exit 1
}

log "INFO" "Initializing Blockcast Node and capturing output"
INIT_OUTPUT=$(docker compose exec blockcastd blockcastd init) || {
    log "ERROR" "Failed to ini blockcastd"
    exit 1
}

echo "$INIT_OUTPUT" | tee /tmp/blockcast-init.txt

HWID=$(echo "$INIT_OUTPUT" | grep -A1 "Hardware ID:" | tail -n1 | xargs)
KEY=$(echo "$INIT_OUTPUT" | grep -A1 "Challenge Key:" | tail -n1 | xargs)
ENCODED_KEY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$KEY'''))")

REGISTER_URL="https://app.blockcast.network/register?hwid=${HWID}&challenge-key=${ENCODED_KEY}"

log "SUCCESS" "Blockcast Node Setup Complete!"
echo -e "${YELLOW}Please open this URL to register your node:${NC}"
echo -e "${CYAN}$REGISTER_URL${NC}"

