#!/usr/bin/env bash
set -e

echo "=== 开始编译打包高斯知衡 iOS 应用 (Objective-C++) ==="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/GaoSiLearning.xcarchive"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_PATH="$PROJECT_DIR/GaoSiLearning.ipa"

rm -rf "$BUILD_DIR" "$IPA_PATH"
mkdir -p "$BUILD_DIR"

echo "1. 执行 xcodebuild archive 编译原生代码..."
xcodebuild -project GaoSiLearning.xcodeproj \
           -scheme GaoSiLearning \
           -configuration Release \
           -sdk iphoneos \
           -archivePath "$ARCHIVE_PATH" \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           archive

echo "2. 构建 Payload 目录结构..."
mkdir -p "$PAYLOAD_DIR"
cp -r "$ARCHIVE_PATH/Products/Applications/GaoSiLearning.app" "$PAYLOAD_DIR/"

echo "3. 打包生成 GaoSiLearning.ipa..."
cd "$BUILD_DIR"
zip -qr "$IPA_PATH" Payload

echo "=== IPA 打包成功！产物路径: $IPA_PATH ==="
ls -lh "$IPA_PATH"
