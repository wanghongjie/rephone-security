# RePhone Security

智能家庭安防监控应用 - 基于 Flutter 和 WebRTC 的远程视频监控系统

## 功能特点

### 🎥 视频监控
- **相机端**：将设备作为摄像头，提供实时视频流
- **监控端**：远程查看相机端的实时画面
- **自动连接**：监控端自动发起连接，相机端自动接受

### 🔐 安全认证
- **邮箱登录**：支持邮箱注册和登录
- **权限验证**：只有相同邮箱账户的设备才能建立连接
- **第三方登录**：支持 Google 和 Apple 账号登录（演示）

### 🌐 网络通信
- **WebRTC**：基于 WebRTC 的 P2P 视频通信
- **信令服务器**：通过 WebSocket 进行设备发现和连接协商
- **TURN 服务器**：支持 NAT 穿透，确保连接稳定性

### 📱 用户体验
- **Material Design 3**：现代化的 UI 设计
- **深色模式**：自动适配系统主题
- **息屏保持**：相机端支持息屏后继续工作
- **状态提示**：实时显示连接状态和设备信息

## 技术架构

### 前端技术
- **Flutter 3.x**：跨平台移动应用开发框架
- **flutter_webrtc**：WebRTC 视频通信
- **shared_preferences**：本地数据存储
- **http**：网络请求

### 后端服务
- **WebRTC 信令服务器**：设备发现和连接协商
- **认证服务器**：用户注册、登录和权限验证
- **TURN 服务器**：NAT 穿透和媒体中继

### 网络协议
- **WebSocket**：实时信令通信
- **WebRTC**：P2P 视频传输
- **HTTPS**：安全的 API 通信

## 快速开始

### 环境要求
- Flutter 3.5.3 或更高版本
- Dart 3.0 或更高版本
- Android SDK 23 或更高版本
- JDK 17（推荐）

### 安装步骤

1. **克隆项目**
   ```bash
   git clone https://github.com/yourusername/rephone_security.git
   cd rephone_security
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **配置服务器地址**
   
   编辑 `lib/config/server_config.dart`：
   ```dart
   const String defaultAuthHost = '47.86.29.177';  // 你的服务器IP
   const int defaultAuthPort = 8086;
   ```

4. **构建应用**
   ```bash
   # Android Debug
   flutter build apk --debug
   
   # Android Release
   flutter build apk --release
   ```

### 权限配置

应用需要以下权限：
- `CAMERA`：访问摄像头
- `RECORD_AUDIO`：录制音频
- `INTERNET`：网络访问
- `ACCESS_NETWORK_STATE`：网络状态检测
- `WAKE_LOCK`：保持设备唤醒

## 使用说明

### 1. 注册登录
- 首次使用需要注册账户
- 支持邮箱验证码注册
- 登录后自动保存会话状态

### 2. 相机端设置
- 切换到"相机端"模式
- 授予摄像头权限
- 保持应用在前台运行

### 3. 监控端连接
- 在"监控端"模式下查看设备列表
- 点击设备项目进入监控页面
- 自动连接到相机端

### 4. 权限验证
- 只有使用相同邮箱登录的设备才能连接
- 相机端会自动验证来电者身份
- 验证失败会拒绝连接

## 项目结构

```
lib/
├── config/           # 配置文件
├── models/           # 数据模型
├── pages/            # 页面组件
│   ├── auth_page.dart
│   ├── camera_endpoint_page.dart
│   ├── monitor_viewer_page.dart
│   └── ...
├── services/         # 业务服务
│   ├── signaling.dart
│   ├── auth_api.dart
│   └── session_manager.dart
├── utils/            # 工具类
└── main.dart         # 应用入口
```

## 开发指南

### 添加新功能
1. 在 `lib/pages/` 下创建新页面
2. 在 `lib/services/` 下添加业务逻辑
3. 更新路由配置

### 调试技巧
- 使用 `flutter logs` 查看实时日志
- 检查 WebRTC 连接状态
- 验证服务器连通性

### 常见问题
- **连接失败**：检查服务器地址和网络连接
- **权限被拒绝**：确保摄像头权限已授予
- **邮箱验证失败**：确保两端使用相同邮箱登录

## 贡献指南

1. Fork 本项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 联系方式

- 项目主页：https://github.com/yourusername/rephone_security
- 问题反馈：https://github.com/yourusername/rephone_security/issues

---

**RePhone Security** - 让科技守护每一刻的安心 🏠📱