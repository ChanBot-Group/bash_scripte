#!/bin/bash

set -e

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

if [ -z "$PANEL_HOST" ]; then
    echo -e "${RED}Fehler: PANEL_HOST ist nicht gesetzt! Bitte im Panel Environment Variables eintragen.${NC}"
    exit 1
fi

if [ -z "$PTERODACTYL_API_KEY" ]; then
    echo -e "${RED}Fehler: PTERODACTYL_API_KEY ist nicht gesetzt! Bitte im Panel Environment Variables eintragen.${NC}"
    exit 1
fi

if [ -z "$SERVER_ID" ]; then
    echo -e "${RED}Fehler: SERVER_ID ist nicht gesetzt! Bitte im Panel Environment Variables eintragen.${NC}"
    exit 1
fi

if [ -z "$PRIVATE_SERVER" ]; then
    echo -e "${YELLOW}PRIVATE_SERVER ist nicht gesetzt, Standard: false (öffentlich)${NC}"
    PRIVATE_SERVER="false"
fi

TARGET_DIR="/home/container"
PTERODACTYL_API_URL="$PANEL_HOST/api/client/servers/$SERVER_ID/power"
UPDATE_VARIABLE_URL="$PANEL_HOST/api/client/servers/$SERVER_ID/startup/variable"

WAIT="ask"
SKIP_WAIT=false

while getopts "yn" opt; do
  case $opt in
    y) SKIP_WAIT=true ;;
    n) SKIP_WAIT=false ;;
    *) echo -e "${RED}Ungültige Option: -$OPTARG${NC}" >&2; exit 1 ;;
  esac
done

wait_timer() {
    local sec=${1:-5}
    if [ "$SKIP_WAIT" = false ]; then
        echo -e "${YELLOW}Warte $sec Sekunden...${NC}"
        for i in $(seq $sec -1 1); do
            # echo -e "${YELLOW}$i...${NC}"
            sleep 1
        done
    fi
}

set_private_server() {
    CFG="$TARGET_DIR/txData/server/server.cfg"

    sed -i '/^sv_master1 /d' "$CFG"
    sed -i '/^# sv_master1 /d' "$CFG"

    VALUE=$(echo "$PRIVATE_SERVER" | tr '[:upper:]' '[:lower:]' | xargs)

    if grep -q '^sets tags' "$CFG"; then
        if [ "$VALUE" = "true" ] || [ "$VALUE" = "1" ]; then
            sed -i '/^sets tags/ a sv_master1 ""' "$CFG"
            echo -e "${RED}Server auf PRIVAT gesetzt.${NC}"
        else
            sed -i '/^sets tags/ a # sv_master1 ""' "$CFG"
            echo -e "${GREEN}Server auf ÖFFENTLICH gesetzt.${NC}"
        fi
    else
        if [ "$VALUE" = "true" ] || [ "$VALUE" = "1" ]; then
            echo 'sv_master1 ""' >> "$CFG"
            echo -e "${RED}Server auf PRIVAT gesetzt.${NC}"
        else
            echo '# sv_master1 ""' >> "$CFG"
            echo -e "${GREEN}Server auf ÖFFENTLICH gesetzt.${NC}"
        fi
    fi
}

update_fivem() {
    echo -e "${BLUE}=== FiveM Update ===${NC}"
    mkdir -p "$TARGET_DIR"
    ARTIFACTS_URL="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/"

    HTML_CONTENT=$(curl -s "$ARTIFACTS_URL")
    LATEST_VERSION=$(echo "$HTML_CONTENT" | grep -oP 'href="\./\K[0-9]+-[a-z0-9]+(?=/fx.tar.xz)' | sort -n | tail -1)
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}Fehler: Konnte die neueste Version nicht ermitteln.${NC}"
        exit 1
    fi

    URL="${ARTIFACTS_URL}${LATEST_VERSION}/fx.tar.xz"
    curl -L "$URL" -o "$TARGET_DIR/fx.tar.xz"

    if tar -tf "$TARGET_DIR/fx.tar.xz" > /dev/null 2>&1; then
        tar -xvf "$TARGET_DIR/fx.tar.xz" -C "$TARGET_DIR" > /dev/null 2>&1
        chmod +x "$TARGET_DIR/run.sh"
        TRIMMED_VERSION=$(echo "$LATEST_VERSION" | cut -d'-' -f1)
        echo -e "${GREEN}FiveM Version $TRIMMED_VERSION erfolgreich installiert.${NC}"
        rm "$TARGET_DIR/fx.tar.xz"

        if [ -d "$TARGET_DIR/alpine" ]; then
            chown -R "$(id -u):$(id -g)" "$TARGET_DIR/alpine"
        fi

        if [ -f "$TARGET_DIR/run.sh" ]; then
            rm "$TARGET_DIR/run.sh"
        fi

        RESPONSE=$(curl -s -X PUT "$UPDATE_VARIABLE_URL" \
            -H "Authorization: Bearer $PTERODACTYL_API_KEY" \
            -H "Content-Type: application/json" \
            -H "Accept: Application/vnd.pterodactyl.v1+json" \
            -d '{
                "key": "FIVEM_VERSION_UPDATE",
                "value": "0"
            }')

        if echo "$RESPONSE" | grep -q '"server_value":"0"'; then
            echo -e "${GREEN}UPDATE-Variable wurde wieder Deaktiviert.${NC}"
        else
            echo -e "${RED}Fehler beim Setzen der UPDATE-Variable.${NC}"
        fi

        wait_timer

        curl -s -X POST "$PTERODACTYL_API_URL" \
            -H "Authorization: Bearer $PTERODACTYL_API_KEY" \
            -H "Content-Type: application/json" \
            -H "Accept: application/vnd.pterodactyl.v1+json" \
            -d '{"signal":"restart"}'
        echo -e "${GREEN}Server wurde neu gestartet.${NC}"
    else
        echo -e "${RED}Fehler: fx.tar.xz ist ungültig.${NC}"
        exit 1
    fi
}

clear_cache() {
    echo -e "${BLUE}=== Cache löschen ===${NC}"
    if [ -d "$TARGET_DIR/txData/server/cache" ]; then
        rm -rf "${TARGET_DIR}/txData/server/cache/"*
        echo -e "${GREEN}Cache gelöscht.${NC}"
    fi

    RESPONSE=$(curl -k -s -X PUT "$UPDATE_VARIABLE_URL" \
        -H "Authorization: Bearer $PTERODACTYL_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "key": "SERVER_CACHE",
            "value": "0"
        }')

    if echo "$RESPONSE" | grep -q '"server_value":"0"'; then
        echo -e "${GREEN}CACHE-Variable wurde wieder Deaktiviert.${NC}"
    else
        echo -e "${RED}Fehler beim Setzen der CACHE-Variable.${NC}"
    fi

    wait_timer
}

chatfix_chown_cleanup() {
    DATEI="$TARGET_DIR/alpine/opt/cfx-server/citizen/system_resources/chat/sv_chat.lua"

    if [ -f "$DATEI" ]; then
        sed -i "/AddEventHandler('playerJoining',/,/end)/ s/^/--/" "$DATEI"
        sed -i "/AddEventHandler('playerDropped',/,/end)/ s/^/--/" "$DATEI"
    fi

    find . -type f ! -name 'utilities.sh' ! -name '.pteroignore' -exec chown "$(id -u):$(id -g)" {} +

    [ -f "$TARGET_DIR/utilities.sh" ] && chown "$(id -u):$(id -g)" "$TARGET_DIR/utilities.sh"

    rm -f core \
        "$TARGET_DIR/txData/server/core" \
        "$TARGET_DIR/txData/server/.replxx_history"
}

chatfix_chown_cleanup
set_private_server

case "$1" in
    update)
        update_fivem
        ;;
    cache)
        clear_cache
        ;;
    updatecache|cacheupdate)
        clear_cache
        update_fivem
        ;;
    *)
    #     echo -e "${BLUE}Usage: $0 {update|cache|updatecache} [-y|-n]${NC}"
        ;;
esac
