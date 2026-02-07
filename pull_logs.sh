#!/bin/bash

# 配置信息
PACKAGE="com.rephone.security"
DATE=$(date +%Y-%m-%d)
REMOTE_LOG_DIR="/data/data/$PACKAGE/app_flutter/logs"
LOCAL_DIR="$HOME/Desktop"
FILENAME="log_$DATE.txt"

echo "=== Log Pull Script ==="
echo "Target Package: $PACKAGE"
echo "Date: $DATE"
echo "Remote Dir: $REMOTE_LOG_DIR"
echo "Local Dir: $LOCAL_DIR"
echo "-----------------------"

# 检查设备连接
DEVICE_COUNT=$(adb devices | grep -v "List of devices attached" | grep -v "^$" | wc -l)
if [ $DEVICE_COUNT -eq 0 ]; then
    echo "Error: No Android device connected."
    exit 1
fi

# 列出远程日志文件
echo "Checking remote logs..."
adb shell run-as $PACKAGE ls $REMOTE_LOG_DIR

# 尝试拉取当天的日志
echo "-----------------------"
echo "Attempting to pull today's log: $FILENAME"

# 检查远程文件是否存在
EXISTS=$(adb shell run-as $PACKAGE ls $REMOTE_LOG_DIR/$FILENAME > /dev/null 2>&1 && echo "yes" || echo "no")

if [ "$EXISTS" == "yes" ]; then
    adb exec-out run-as $PACKAGE cat $REMOTE_LOG_DIR/$FILENAME > "$LOCAL_DIR/$FILENAME"
    
    if [ -s "$LOCAL_DIR/$FILENAME" ]; then
        echo "✅ Success! Log saved to: $LOCAL_DIR/$FILENAME"
        open "$LOCAL_DIR/$FILENAME"
    else
        echo "⚠️  Warning: File pulled but appears empty."
    fi
else
    echo "❌ Error: Log file '$FILENAME' not found on device."
    echo "Tip: Make sure the app has run today and generated logs."
fi
