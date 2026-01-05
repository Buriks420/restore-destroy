#!/bin/bash

RCLONE_REMOTE="gdrive:BackupanPtero"
PTERO_VOLUMES_PATH="/var/lib/pterodactyl/volumes"
TEMP_RESTORE_PATH="/root/temp_restore"
LOG_FILE="/var/log/pterorestore.log"

export NEWT_COLORS='
root=,blue
window=,lightgray
border=black,lightgray
shadow=,black
title=black,lightgray
button=white,blue
actbutton=white,red
compactbutton=white,blue
checkbox=black,lightgray
actcheckbox=white,blue
entry=black,white
listbox=black,lightgray
actlistbox=white,blue
textbox=black,lightgray
acttextbox=black,lightgray
emptyscale=,gray
fullscale=,blue
disentry=gray,lightgray
'

for cmd in whiptail rclone tar pigz jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "Installing missing dependency: $cmd..."
        apt-get update -qq && apt-get install -y $cmd > /dev/null 2>&1
    fi
done

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_node_name() {
    NODE_NAME=$(whiptail --title "Step 1: Identity" --inputbox "Enter the NODE NAME to restore from (e.g., basic-3):" 10 60 3>&1 1>&2 2>&3)
    
    exitstatus=$?
    if [ $exitstatus != 0 ]; then echo "Cancelled."; exit 1; fi
    
    if [ -z "$NODE_NAME" ]; then
        whiptail --msgbox "Node name cannot be empty." 10 60
        get_node_name
    fi
}

select_date() {
    whiptail --infobox "Connecting to Google Drive...\nSearching for backups in '$NODE_NAME'..." 10 60
    
    RAW_DATES=$(rclone lsf "$RCLONE_REMOTE/$NODE_NAME/" --dirs-only)
    
    if [ -z "$RAW_DATES" ]; then
        whiptail --msgbox "ERROR: No backups found for node: $NODE_NAME\n\nCheck the name and try again." 10 60
        exit 1
    fi

    DATE_OPTIONS=()
    while read -r line; do
        clean_date=${line%/}
        DATE_OPTIONS+=("$clean_date" "Backup Folder")
    done <<< "$RAW_DATES"

    SELECTED_DATE=$(whiptail --title "Step 2: Time Travel" --menu "Choose a date to restore from:" 20 60 10 "${DATE_OPTIONS[@]}" 3>&1 1>&2 2>&3)
    
    exitstatus=$?
    if [ $exitstatus != 0 ]; then exit 1; fi
}

select_servers() {
    whiptail --infobox "Scanning backup files inside '$SELECTED_DATE'...\nThis might take a few seconds..." 10 60
    
    RAW_FILES=$(rclone lsf -R "$RCLONE_REMOTE/$NODE_NAME/$SELECTED_DATE/" --files-only)
    
    if [ -z "$RAW_FILES" ]; then
        whiptail --msgbox "ERROR: No files found in this backup date." 10 60
        exit 1
    fi

    SERVER_OPTIONS=()
    while read -r filepath; do
        filename=$(basename "$filepath")
        uuid=$(echo "$filename" | grep -oP '\([a-f0-9-]{36}\)' | tr -d '()')
        
        server_display=$(echo "$filename" | sed -E 's/_\([a-f0-9-]{36}\)\.tar\.gz//g')
        
        SERVER_OPTIONS+=("$filepath" "$server_display" "OFF")
        
    done <<< "$RAW_FILES"

    SELECTED_FILES=$(whiptail --title "Step 3: Select Servers" --checklist \
    "Press SPACE to select servers.\nPress ENTER to start restoration.\n\nTarget: $NODE_NAME / $SELECTED_DATE" \
    25 100 15 "${SERVER_OPTIONS[@]}" 3>&1 1>&2 2>&3)
    
    exitstatus=$?
    if [ $exitstatus != 0 ]; then exit 1; fi
    
    if [ -z "$SELECTED_FILES" ]; then
        whiptail --msgbox "No servers selected. Exiting." 10 60
        exit 1
    fi
}

perform_restore() {
    CLEAN_SELECTION=$(echo "$SELECTED_FILES" | tr -d '"')
    
    TOTAL_COUNT=$(echo "$CLEAN_SELECTION" | wc -w)
    CURRENT=0
    
    mkdir -p "$TEMP_RESTORE_PATH"

    for filepath in $CLEAN_SELECTION; do
        CURRENT=$((CURRENT+1))
        
        filename=$(basename "$filepath")
        uuid=$(echo "$filename" | grep -oP '\([a-f0-9-]{36}\)' | tr -d '()')
        
        TARGET_DIR="$PTERO_VOLUMES_PATH/$uuid"
        
        if [ ! -d "$TARGET_DIR" ]; then
            log_message "SKIP: Target directory $TARGET_DIR does not exist. (Server not created in Panel yet?)"
            continue
        fi

        whiptail --gauge "Restoring Server [$CURRENT/$TOTAL_COUNT]\nUUID: $uuid\n\nPhase: Downloading..." 10 70 30 &
        GAUGE_PID=$!
        
        rclone copy "$RCLONE_REMOTE/$NODE_NAME/$SELECTED_DATE/$filepath" "$TEMP_RESTORE_PATH/" --transfers=4
        
        if [ ! -f "$TEMP_RESTORE_PATH/$filename" ]; then
            kill $GAUGE_PID 2>/dev/null
            log_message "ERROR: Failed to download $filename"
            continue
        fi
        
        kill $GAUGE_PID 2>/dev/null
        whiptail --gauge "Restoring Server [$CURRENT/$TOTAL_COUNT]\nUUID: $uuid\n\nPhase: Extracting..." 10 70 60 &
        GAUGE_PID=$!
        
        rm -rf "${TARGET_DIR:?}"/*
        tar --use-compress-program="pigz" -xf "$TEMP_RESTORE_PATH/$filename" -C "$TARGET_DIR"
        
        kill $GAUGE_PID 2>/dev/null
        whiptail --gauge "Restoring Server [$CURRENT/$TOTAL_COUNT]\nUUID: $uuid\n\nPhase: Fixing Permissions..." 10 70 90 &
        GAUGE_PID=$!
        
        chown -R pterodactyl:pterodactyl "$TARGET_DIR"
        chmod -R 755 "$TARGET_DIR"
        
        rm "$TEMP_RESTORE_PATH/$filename"
        kill $GAUGE_PID 2>/dev/null
        
        log_message "SUCCESS: Restored $uuid"
    done
    
    whiptail --msgbox "Restoration Complete!\n\nProcessed: $TOTAL_COUNT servers.\nCheck your Panel and start the servers." 12 60
}

get_node_name
select_date
select_servers
perform_restore
