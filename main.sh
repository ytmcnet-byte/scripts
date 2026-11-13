#!/usr/bin/env bash

# =========================================
#       OG MASTER SCRIPT PANEL
#       Powered by SHIVAMBROOG
# =========================================

SCRIPTS=(
    "CPULIMIT|https://raw.githubusercontent.com/ytmcnet-byte/scripts/refs/heads/main/cpulimit.sh"
    "NON ROOT JAVA|https://raw.githubusercontent.com/ytmcnet-byte/scripts/refs/heads/main/non-root-java.sh"
    "OG FORWARD|https://raw.githubusercontent.com/ytmcnet-byte/scripts/refs/heads/main/og-forward.sh"
    "TAILSCALE INSTALLER|https://raw.githubusercontent.com/ytmcnet-byte/scripts/refs/heads/main/tailscale-install.sh"
)

while true; do
    clear
    echo "======================================"
    echo "       OGHOST MASTER PANEL"
    echo "       Powered by SHIVAMBROOG"
    echo "======================================"

    for i in "${!SCRIPTS[@]}"; do
        echo " $((i+1)). ${SCRIPTS[$i]%%|*}"
    done

    echo "--------------------------------------"
    echo " 5. RUN ALL SCRIPTS"
    echo " 0. EXIT"
    echo "======================================"

    read -rp "Select Option: " CHOICE

    if [[ "$CHOICE" == "0" ]]; then
        exit 0
    fi

    run_script() {
        local ENTRY="$1"
        local NAME="${ENTRY%%|*}"
        local URL="${ENTRY#*|}"
        local TMP

        TMP=$(mktemp) || return 1

        echo
        echo "[$NAME] Downloading..."

        if ! curl -fLsS --retry 3 "$URL" -o "$TMP"; then
            echo "Download failed!"
            rm -f "$TMP"
            return 1
        fi

        if ! bash -n "$TMP"; then
            echo "Syntax check failed!"
            rm -f "$TMP"
            return 1
        fi

        echo "Download successful."
        echo "Review the script before execution:"
        read -rp "Execute $NAME? (yes/no): " CONFIRM

        if [[ "$CONFIRM" == "yes" ]]; then
            bash "$TMP"
            RESULT=$?
        else
            echo "Skipped."
            RESULT=0
        fi

        rm -f "$TMP"
        return "$RESULT"
    }

    if [[ "$CHOICE" == "5" ]]; then
        for ENTRY in "${SCRIPTS[@]}"; do
            run_script "$ENTRY" || echo "Script failed: ${ENTRY%%|*}"
            echo
            read -rp "Press Enter for next script..."
        done

    elif [[ "$CHOICE" =~ ^[1-4]$ ]]; then
        run_script "${SCRIPTS[$((CHOICE-1))]}"
        echo
        read -rp "Press Enter to continue..."
    else
        echo "Invalid option!"
        sleep 2
    fi
done
