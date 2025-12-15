# 包名问题修复说明

## 🐛 问题描述

在安装APK时出现以下错误：
```
java.lang.ClassNotFoundException: Didn't find class "com.rephone.security.MainActivity"
```

## 🔍 问题原因

1. **包名不一致**: 我们在 `build.gradle` 中将包名从 `com.example.rephone_security` 改为 `com.rephone.security`
2. **文件路径未更新**: MainActivity文件仍在旧的包路径 `com/example/rephone_security/` 下
3. **类找不到**: Android系统无法在新包名路径下找到MainActivity类

## ✅ 修复步骤

### 1. 创建新的包目录结构
```bash
mkdir -p android/app/src/main/kotlin/com/rephone/security
```

### 2. 更新MainActivity包名
将文件从：
```
android/app/src/main/kotlin/com/example/rephone_security/MainActivity.kt
```
移动到：
```
android/app/src/main/kotlin/com/rephone/security/MainActivity.kt
```

### 3. 更新MainActivity内容
```kotlin
package com.rephone.security  // 更新包名

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity()
```

### 4. 删除旧的包目录
```bash
rm -rf android/app/src/main/kotlin/com/example
```

### 5. 清理并重新构建
```bash
flutter clean
flutter pub get
flutter build apk
```

## 📋 相关配置文件

### build.gradle
```gradle
android {
    namespace = "com.rephone.security"
    defaultConfig {
        applicationId = "com.rephone.security"
        // ...
    }
}
```

### AndroidManifest.xml
```xml
<application
    android:label="RePhone Security"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
    <activity
        android:name=".MainActivity"
        android:exported="true"
        // ...
    />
</application>
```

## 🎯 修复结果

修复后的文件结构：
```
android/app/src/main/
├── AndroidManifest.xml
└── kotlin/
    └── com/
        └── rephone/
            └── security/
                └── MainActivity.kt
```

## 🚀 重新构建APK

修复完成后，需要重新构建APK：

```bash
# 清理缓存
flutter clean

# 获取依赖
flutter pub get

# 构建APK
flutter build apk

# 复制到项目根目录
cp build/app/outputs/flutter-apk/app-release.apk ./RePhone-Security-release-fixed.apk
```

## 📱 测试安装

重新构建的APK应该可以正常安装和运行，不会再出现ClassNotFoundException错误。

## 💡 经验总结

1. **包名一致性**: 修改包名时，需要同时更新所有相关文件
2. **目录结构**: Android包名必须与文件目录结构完全对应
3. **清理缓存**: 修改包结构后务必清理构建缓存
4. **测试验证**: 每次修改后都要重新测试安装

---

**修复时间**: 2024年12月1日 16:45  
**修复状态**: ✅ 已完成  
**下一步**: 重新构建并测试APK安装
