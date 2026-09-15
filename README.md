# 高斯知衡智能训考 iOS 客户端 (Objective-C++)

本项目为高斯知衡智能训考与错题本系统的原生 iOS 客户端工程，采用 **Objective-C++ (`.mm`) + UIKit + C++ 图像处理算法** 混合架构开发，完美适配从 iPhone SE 到 iPhone 16 Pro Max 及 iPad 等所有 iOS 移动设备屏幕。

---

## 一、核心功能特性（与 Android 端完全对齐）

1. **用户认证与多角色登录 (`GSLoginViewController`)**
   - 响应式垂直居中 Material 质感卡片布局，自动处理 iOS 虚拟键盘升降遮挡。
   - 支持「学生身份」与「教师身份」切换。
   - 支持与服务端 (`http://112.46.82.154:4174`) 连通并持久化用户 Token。

2. **错题本与艾宾浩斯复习管理 (`GSWrongBookViewController`)**
   - 顶部横向滚动学科胶囊栏（全部、数学、物理、化学、语文、英语、生物等）。
   - 快速题干、知识点、错因模糊搜索栏。
   - 艾宾浩斯 6 阶段遗忘曲线复习进度徽章（阶段 1~6、已掌握）。
   - 错题卡片自适应列表与下拉刷新。
   - 底部全宽主按钮「📷 拍照 / 选取试卷录错题」。

3. **试卷图像题目自动检测与多选框交互 (`GSQuestionSelectViewController` + `GSCropOverlayView`)**
   - 纯 C++ 算法引擎 (`ImageProcessorCore::sauvolaBinarize`)：基于积分图的 Sauvola 局部自适应二值化算法，毫秒级检测试卷候选题目区域。
   - 交互式选框图层：绿色高亮已选题框（带「题 1 已选」标签），蓝色虚线未选题框，支持点击切换、拖拽调整选框、全选与清空。

4. **端云协同多模态视觉 OCR + LaTeX 数学公式识别 (`GSVisionOCRService`)**
   - **首选通道**：调用服务端 `/api/ai/ocr-question`，由 `openbmb/minicpm-o2.6:latest` 视觉大模型执行高精转写，输出标准 LaTeX 公式（`$...$` 与 `$$...$$`），分式、根号、向量箭头均精准保留。
   - **离线兜底**：若处于离线环境或网络超时，无缝回退至 Apple 原生 `VNRecognizeTextRequest` 离线文字识别。

5. **Qwen 27B 旗舰模型深度归因 (`GSOllamaClient`)**
   - 题干提取完成后，自动触发 `qwen3.8:27b-bf16`（超时配置 180s）进行深度归因。
   - 自动提炼核心学科、精确考点与学生思维盲区。
   - 预生成针对该考点的**举一反三变式练习题**。

6. **变式题举一反三与 LaTeX 公式排版渲染 (`GSSimilarQuestionsViewController` + `GSLaTeXView`)**
   - 内置 WebKit + KaTeX 渲染引擎，题干、选项与解析中的数学公式与科学符号毫秒级矢量排版。
   - 支持 ABCD 选项选择、折叠展开「名师精析与参考答案」。
   - 支持「✨ AI 换一批」实时重生成新题。

7. **离线缓存与批量幂等同步 (`GSCacheManager` + `GSAPIClient`)**
   - 支持无网环境下本地浏览错题与切图。
   - 离线录入的错题自动加入本地待同步队列，网络恢复时支持一键批量同步并生成艾宾浩斯复习计划。

---

## 二、工程目录结构

```
ios/GaoSiLearning/
├── GaoSiLearning.xcodeproj/          # 标准 Xcode 工程配置
│   └── project.pbxproj
├── GaoSiLearning/                    # 源码主目录
│   ├── main.m                        # 应用入口
│   ├── AppDelegate.h / .mm           # 应用程序代理
│   ├── SceneDelegate.h / .mm         # 场景代理 (iOS 13+)
│   ├── GaoSiLearning-Prefix.pch      # 预编译头文件
│   ├── Info.plist                    # 权限 (相机/相册/HTTP) 与系统配置
│   ├── LaunchScreen.storyboard       # 启动图界面
│   ├── Assets.xcassets/              # 图标与主题颜色资产
│   └── Classes/
│       ├── Core/                     # C++ 算法核心
│       │   ├── ImageProcessor.hpp
│       │   └── ImageProcessor.mm
│       ├── Models/                   # 数据模型
│       │   ├── GSModels.h
│       │   └── GSModels.mm
│       ├── Storage/                  # 本地持久化与会话
│       │   ├── GSCacheManager.h / .mm
│       │   └── GSCaptureSession.h / .mm
│       ├── Network/                  # 接口与大模型通信
│       │   ├── GSAPIClient.h / .mm
│       │   ├── GSOllamaClient.h / .mm
│       │   └── GSVisionOCRService.h / .mm
│       └── UI/                       # 移动端界面视图控制器
│           ├── GSLaTeXView.h / .mm
│           ├── GSCropOverlayView.h / .mm
│           ├── GSLoginViewController.h / .mm
│           ├── GSWrongBookViewController.h / .mm
│           ├── GSQuestionSelectViewController.h / .mm
│           ├── GSRecordDialogViewController.h / .mm
│           └── GSSimilarQuestionsViewController.h / .mm
├── build_ipa.sh                      # 一键打包 .ipa 脚本
└── README.md                         # 工程说明
```

---

## 三、编译与安装文件 (.ipa) 生成方式

### 方式 1：使用 Mac 电脑本地 Xcode（最直接）
1. 在 Mac 电脑上使用 Xcode 打开 `ios/GaoSiLearning/GaoSiLearning.xcodeproj`。
2. 连接 iPhone 真机或选择 iOS 模拟器。
3. 点击菜单栏 **Product -> Run (⌘R)** 即可直接运行调试。
4. 打包安装包：点击 **Product -> Archive**，根据向导导出 Ad-Hoc、Development 或 App Store 签名的 `.ipa` 安装文件。
5. 或在终端执行本工程提供的脚本：
   ```bash
   chmod +x build_ipa.sh
   ./build_ipa.sh
   ```
   执行完成后即可在当前目录下生成 `GaoSiLearning.ipa`。

### 方式 2：使用 GitHub Actions 自动云打包（无需本地 Mac 电脑）
本工程已内置配置自动化 CI/CD 流水线 [`.github/workflows/ios-build.yml`](file:///D:/GaoSiLearning/.github/workflows/ios-build.yml)：
1. 将工程提交推送到 GitHub 代码仓库。
2. 在 GitHub 仓库页点击 **Actions**，选择 **Build iOS IPA** 工作流。
3. 点击 **Run workflow**。
4. GitHub 会自动启动官方 `macos-14` 苹果云主机执行编译并自动打包生成 `GaoSiLearning.ipa`。
5. 构建完成后在 **Artifacts** 区域即可直接一键下载 `.ipa` 安装包。

---

## 四、iOS 真机安装说明

生成的 `GaoSiLearning.ipa` 支持以下常见的真机侧载安装方式：

1. **AltStore / Sideloadly（推荐，免越狱，个人免费 Apple ID）**：
   - 电脑安装 AltStore 或 Sideloadly。
   - 连接 iPhone，拖入 `GaoSiLearning.ipa`，输入个人 Apple ID 即可自动签名安装到真机上，7 天免费使用并支持自动续签。
2. **爱思助手 / 蒲公英分发（企业或测试证书）**：
   - 使用爱思助手的「应用安装」直接导入安装。
3. **TrollStore（巨魔商店，支持 iOS 14.0~16.6.1 / 17.0 部分机型）**：
   - 通过手机端巨魔商店直接打开 `GaoSiLearning.ipa` 即可实现永久免签名免证书闪装。
