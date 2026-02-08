#!/bin/bash

# Configuration
PACKAGE_NAME="com.rephone.security"
LOCAL_DIR="./logs_dump"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting log extraction for $PACKAGE_NAME...${NC}"

# Create local directory
mkdir -p "$LOCAL_DIR"

# Check for devices
DEVICES=$(adb devices | grep -w "device" | cut -f1)
if [ -z "$DEVICES" ]; then
    echo -e "${RED}No Android devices found! Please connect a device and enable USB debugging.${NC}"
    exit 1
fi

echo "Found device(s):"
echo "$DEVICES"

# Function to pull logs from a specific device
pull_logs_from_device() {
    local DEVICE_ID=$1
    echo -e "${GREEN}Processing device: $DEVICE_ID${NC}"

    # timestamp for this pull
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    DEVICE_DIR="$LOCAL_DIR/$DEVICE_ID/$TIMESTAMP"
    mkdir -p "$DEVICE_DIR"

    # 1. Pull Logcat (system logs)
    echo "Pulling logcat..."
    adb -s "$DEVICE_ID" logcat -d > "$DEVICE_DIR/logcat.txt"

    # 2. Pull App Logs (from internal storage)
    # Note: This requires the app to be debuggable (run-as)
    echo "Attempting to pull internal app logs..."
    
    # List files first to see what's there
    LOG_FILES=$(adb -s "$DEVICE_ID" shell run-as $PACKAGE_NAME ls -1 app_flutter/logs/ 2>/dev/null)
    
    if [ -z "$LOG_FILES" ]; then
        echo -e "${RED}Could not list log files (or empty). Is the app debuggable?${NC}"
    else
        echo "Found log files:"
        echo "$LOG_FILES"
        
        for LOG_FILE in $LOG_FILES; do
            # Remove carriage return if present
            LOG_FILE=$(echo "$LOG_FILE" | tr -d '\r')
            if [ -n "$LOG_FILE" ]; then
                echo "Pulling $LOG_FILE..."
                # Use cat and redirection to avoid permission issues with 'adb pull' on internal storage
                adb -s "$DEVICE_ID" exec-out run-as $PACKAGE_NAME cat "app_flutter/logs/$LOG_FILE" > "$DEVICE_DIR/$LOG_FILE"
            fi
        done
    fi

    # 3. Pull ANR traces if available
    echo "Pulling ANR traces..."
    adb -s "$DEVICE_ID" pull /data/anr/traces.txt "$DEVICE_DIR/anr_traces.txt" 2>/dev/null

    echo -e "${GREEN}Logs saved to: $DEVICE_DIR${NC}"
}

# Iterate over all connected devices
for DEVICE in $DEVICES; do
    pull_logs_from_device "$DEVICE"
done

echo -e "${GREEN}Done!${NC}"
