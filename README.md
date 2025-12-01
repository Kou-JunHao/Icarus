# 伊卡洛斯 (Icarus)

<p align="center">
  <img src="Icarus.png" width="128" height="128" alt="Icarus Logo">
</p>

<p align="center">
  <strong>一款使用 Material 3 Design 设计的校园服务聚合应用</strong>
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#截图预览">截图预览</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#技术栈">技术栈</a> •
  <a href="#许可证">许可证</a>
</p>
[如有其他学校适配请求，请发送邮件至 skkk@skkk.uno](mailto:skkk@skkk.uno?subject=学校适配需求&body=请在此输入内容) 联系。

---

## 功能特性

### 🏠 首页
- **今日课程** - 一目了然查看当天课程安排
- **天气信息** - 实时天气和未来预报
- **快捷操作** - 常用功能一键直达

### 📅 课程表
- **周视图** - 完整周课程表展示
- **课程详情** - 点击查看课程详细信息
- **周次切换** - 快速切换不同周次
- **课程颜色** - Material 3 风格配色区分不同课程

### 📊 成绩单
- **学期成绩** - 按学期查看所有课程成绩
- **成绩统计** - GPA、学分等统计信息
- **成绩详情** - 包含平时分、考试分等详细信息

### 👤 个人中心
- **学籍信息** - 查看个人学籍卡片
- **主题设置** - 支持 Material You 动态取色
- **课程提醒** - 自定义上课通知
- **桌面小组件** - 快速查看今日课程

## 快速开始

### 环境要求

- Flutter SDK >= 3.9.2
- Dart SDK >= 3.9.2
- Android SDK (Android 开发)
- Xcode (iOS 开发，仅 macOS)

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/Kou-JunHao/Icarus.git
   cd Icarus
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **运行应用**
   ```bash
   # Android
   flutter run -d android
   
   # iOS
   flutter run -d ios
   ```

### 构建发布版本

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release
```

## 技术栈

- **框架**: Flutter 3.9+
- **设计**: Material 3 / Material You
- **状态管理**: Provider + ChangeNotifier
- **网络请求**: Dio
- **本地存储**: SharedPreferences
- **OCR**: Google ML Kit
- **动态取色**: dynamic_color
- **本地通知**: flutter_local_notifications
- **桌面小组件**: home_widget

## 项目结构

```
lib/
├── main.dart              # 应用入口
├── models/                # 数据模型
│   ├── course.dart        # 课程模型
│   ├── grade.dart         # 成绩模型
│   ├── user.dart          # 用户模型
│   └── weather.dart       # 天气模型
├── screens/               # 页面
│   ├── home_screen.dart   # 首页
│   ├── schedule_screen.dart # 课程表
│   ├── grades_screen.dart # 成绩单
│   ├── profile_screen.dart # 个人中心
│   └── login_screen.dart  # 登录页
├── services/              # 服务层
│   ├── jwxt_service.dart  # 教务系统服务
│   ├── weather_service.dart # 天气服务
│   ├── data_manager.dart  # 数据管理
│   └── notification_service.dart # 通知服务
└── utils/                 # 工具类
```

## 文档

更多技术文档请查看 [docs](./docs/) 目录：

- [登录逻辑分析](./docs/LOGIN_LOGIC.md) - 强智教务系统登录流程详解

## 反馈与贡献

如果你有任何问题或建议，欢迎：

- 📧 发送邮件至 [skkk@skkk.uno](mailto:skkk@skkk.uno)
- 🐛 提交 [Issue](https://github.com/Kou-JunHao/Icarus/issues)
- 🔀 提交 Pull Request

## 许可证

本项目采用 [MIT License](LICENSE) 许可证开源。

```
MIT License

Copyright (c) 2025 SKKK

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

<p align="center">
  Made with ❤️ by SKKK
</p>
