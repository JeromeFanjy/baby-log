# 原生 iOS 版安装说明（SwiftUI）

`NewbornLogApp.swift` 是完整源码（约 1000 行，单文件），功能与网页版一致：
喂养（亲喂/储存奶/配方奶 + 计时器）、大小便（类型/性状/颜色/量）、补剂（含维生素K1）、每日统计、历史日期翻看、
编辑/删除、导出备份（存文件 / 隔空投送 / 微信 / 剪贴板）、导入恢复。
要求：Xcode 14+（建议最新版），iOS 15+ 真机。

## 一、前提

1. 一台 Mac（App Store 搜索 **Xcode** 免费下载，约 15 GB，需要较新 macOS）
2. 你自己的 **Apple ID**（免费即可，用于签名）
3. iPhone + 数据线

> 免费 Apple ID 签名的 App 有效期 **7 天**，到期后用数据线再 Run 一次即续期；
> 想长期免维护或上架/TestFlight，需注册 Apple Developer Program（99 美元/年）。

## 二、创建项目（5 分钟）

1. 打开 Xcode → **Create New Project…** → 选 **iOS → App** → Next
2. 填：
   - Product Name：`BabyLog`（随意）
   - Interface：**SwiftUI**
   - Language：**Swift**
   - 勾掉 Use Core Data / Include Tests
3. 保存到任意位置。

## 三、替换成我们的代码

1. 左侧项目导航里，**删除** Xcode 模板自带的两个文件：`BabyLogApp.swift` 和 `ContentView.swift`（选中 → 右键 → Delete → Move to Trash）
2. 把 `NewbornLogApp.swift` **拖进**项目导航的 BabyLog 文件夹
3. 弹出对话框勾选 **Copy items if needed**，并确认 **Target Membership** 勾选了 `BabyLog`（一定要勾，否则编译报找不到入口）

## 四、签名 + 装到手机

1. 点左侧蓝色项目名 → **Signing & Capabilities**
2. 勾选 **Automatically manage signing**
3. **Team** 下拉 → **Add an Account…** → 登录你的 Apple ID（免费账号即可，Xcode 会自动建"个人团队"）
4. **Bundle Identifier** 改成唯一的，如 `com.yourname.babylog`（提示冲突就换个名字）
5. 数据线连接 iPhone → 手机弹「信任此电脑」→ 点信任
6. Xcode 顶部设备栏选你的 iPhone → 点 ▶ **Run**

第一次装会提示「不受信任的开发者」：iPhone 上 **设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任**，即可打开。

## 五、常见问题

| 问题 | 解决 |
|---|---|
| 7 天后 App 打不开 | 连上 Mac 再 Run 一次即可续期；或升级付费开发者账号 |
| 提示签名失败 / Team 为空 | 检查第 2、3 步；确认 Apple ID 已登录 |
| 提示 Bundle ID 不可用 | 改个更独特的，如 `com.yourname.baby.log` |
| 想给家人手机装 | 付费账号用 TestFlight（内测分发）最方便；免费账号只能装在自己的设备 |
| 想上架 App Store | 99 美元/年 + 审核（需要隐私政策、截图等） |
| 数据备份 | App 内 ⚙️ → 导出为文件 → 存「文件」/隔空投送/发微信；换机时导入 |

## 六、不想折腾 Xcode？

直接用文件夹上一层的**网页版**（`../index.html`），体验几乎一样，今天就能用。
