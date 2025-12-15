#!/bin/bash

echo "🚀 RePhone Security Flutter应用启动脚本"
echo "=================================="

# 检查Flutter是否安装
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter未安装，请先安装Flutter SDK"
    exit 1
fi

echo "✅ Flutter版本信息:"
flutter --version

echo ""
echo "📦 安装依赖包..."
flutter pub get

echo ""
echo "🔍 代码分析..."
flutter analyze

echo ""
echo "🧪 运行测试..."
flutter test

echo ""
echo "📱 启动应用..."
echo "请选择运行平台:"
echo "1) Android模拟器/设备"
echo "2) iOS模拟器/设备"
echo "3) Chrome浏览器"
echo "4) 查看可用设备"

read -p "请输入选择 (1-4): " choice

case $choice in
    1)
        echo "🤖 在Android设备上运行..."
        flutter run -d android
        ;;
    2)
        echo "🍎 在iOS设备上运行..."
        flutter run -d ios
        ;;
    3)
        echo "🌐 在Chrome浏览器中运行..."
        flutter run -d chrome
        ;;
    4)
        echo "📱 可用设备列表:"
        flutter devices
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac
