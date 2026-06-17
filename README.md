# giffgaff eSIM 环境一键配置工具

在 Windows + MuMu 5 模拟器中自动搭建 giffgaff eSIM 环境：Root → Kitsune Mask → Zygisk → LSPosed → HookEuicc → giffgaff 登录页。

**脚本自动执行到 giffgaff 登录页为止**，之后的账号登录、验证码、付款、eSIM 购买由用户手动完成。

---

## 快速开始

### 方式一：双击启动（推荐新手）

1. 下载本项目（Clone 或 Download ZIP）
2. 双击 `start.bat`
3. 跟着中文引导操作即可

### 方式二：配合 AI Agent 使用（推荐进阶用户）

如果你使用 Trae、CodeBuddy、Cursor 等 AI 编程助手，直接对 Agent 说：

> "帮我克隆 https://github.com/ballkatrina936-tech/giffgaff-esim-env-setup 并运行 giffgaff eSIM 环境配置脚本，用 VM 1 实例"

Agent 会自动：
1. 克隆仓库
2. 检测 MuMu 安装位置
3. 自动下载工具包（HookEuicc、LSPosed、Via）
4. 引导你手动下载 giffgaff APK 和 Kitsune Mask
5. 运行配置脚本

### 方式三：PowerShell 命令行

```powershell
# 交互式（推荐）
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1

# 非交互式（适合 Agent 调用）
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1 -NonInteractive -VmIndex 1 -ToolDir "C:\giffgaff_tools"
```

---

## 前置条件

| 条件 | 说明 |
|------|------|
| 操作系统 | Windows 10/11 |
| MuMu Player 5 | [下载地址](https://www.mumuplayer.com/download/) |
| MuMu 实例 | 建议新建一个干净实例（不要用主实例） |

**不支持**雷电、夜神、蓝叠等其他模拟器。

---

## 工具包说明

脚本会自动下载以下文件，无需手动准备：

| 工具 | 来源 | 自动下载 |
|------|------|----------|
| LSPosed v1.9.2 | GitHub Releases | ✅ 是 |
| Via 浏览器 | 官方 CDN | ✅ 是 |
| HookEuicc | GitHub Releases API | ✅ 是 |

以下文件因下载源有 Cloudflare 防护无法自动下载，脚本会**弹出浏览器引导你下载**：

| 工具 | 下载链接 | 自动下载 |
|------|----------|----------|
| giffgaff APK | [mi9.com](https://mi9.com/package/com.giffgaffmobile.controller/download/) / [Uptodown](https://my-giffgaff.en.uptodown.com/android/download) | ❌ 手动 |
| Kitsune Mask | [SourceForge](https://sourceforge.net/projects/magisk/files/Magisk%20Delta%20(Kitsune%20Mask)/) | ❌ 手动 |

下载后放入工具包目录（默认 `tools/`，或脚本指定的目录）即可，脚本会自动检测。

### 文件名匹配规则

脚本通过通配符匹配文件名，只要文件名包含关键词即可：

```
HookEuicc*.apk          → 如 app-release-sign.apk 需改名为 HookEuicc.apk
giffgaff*.apk           → 如 giffgaff_20.16.0.apk
Kitsune*.apk / *Mask*.apk → 如 Magisk Delta Kitsune 27.001 Canary.apk
LSPosed-v1.9.2-*.zip    → 自动下载
via-release.apk         → 自动下载
```

---

## 脚本参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-ToolDir` | `./tools` | 工具包目录 |
| `-VmIndex` | 交互选择 | MuMu 实例编号 |
| `-MuMuDir` | 自动检测 | MuMu 安装路径 |
| `-NonInteractive` | 否 | 非交互模式（适合 Agent） |
| `-SkipDownload` | 否 | 跳过自动下载 |
| `-NoAcceptGiffgaffTerms` | 否 | 不自动接受 giffgaff 条款 |

---

## 脚本自动执行的步骤

1. 检测 MuMu 5 和 `mumu-cli.exe`
2. 列出所有 MuMu 实例，交互选择
3. 自动下载工具包（LSPosed、Via、HookEuicc）
4. 引导手动下载（giffgaff APK、Kitsune Mask）
5. 启动指定 MuMu 实例
6. 开启 root 权限和系统盘可写
7. 安装 Via、giffgaff、Kitsune Mask、HookEuicc
8. 在 Kitsune Mask 中安装 Magisk
9. 开启 Zygisk
10. 安装 LSPosed 模块
11. 在 LSPosed 中启用 HookEuicc
12. 给 HookEuicc 勾选电话服务和 giffgaff 作用域
13. 打开 HookEuicc 主开关
14. 打开 giffgaff，停在登录页

## 用户需手动完成的操作

- 输入 giffgaff 账号密码
- 输入邮箱或短信验证码
- 选择套餐或 eSIM
- 填写地址
- 付款
- 确认最终购买/提交

---

## 配合 AI Agent 使用（详细指南）

### Trae / CodeBuddy / Cursor

1. 克隆仓库到本地
2. 用 Agent 打开项目目录
3. 对 Agent 说：

```
帮我运行 giffgaff eSIM 环境配置脚本。
- MuMu 已安装在 D:\Program Files\Netease\MuMuPlayer\nx_main
- 使用 VM 1 实例（新建的干净实例）
- 工具包在 C:\giffgaff_tools 目录
- 如果缺少 APK 文件，告诉我下载链接
```

4. Agent 会执行：
```powershell
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1 -NonInteractive -VmIndex 1 -ToolDir "C:\giffgaff_tools" -MuMuDir "D:\Program Files\Netease\MuMuPlayer\nx_main"
```

5. 如果缺少文件，Agent 会告诉你下载链接，你下载放入目录后让 Agent 重新运行

### 注意事项

- 脚本**不会记录、读取、上传**你的账号密码或验证码
- 脚本**不会代替你**付款、购买套餐、提交 eSIM 申请
- 强烈建议使用**新建的干净 MuMu 实例**运行脚本
- 脚本会修改指定实例的 root 和系统盘可写设置

---

## 常见问题

### 找不到 MuMu

脚本会自动扫描常见安装路径。如果找不到，可以：
- 用 `-MuMuDir` 参数手动指定路径
- 交互模式下手动输入路径

### 缺少 -VmIndex

交互模式下会列出所有实例供选择。非交互模式必须指定 `-VmIndex`。

### 缺少 APK/ZIP

脚本会自动下载 LSPosed、Via、HookEuicc。giffgaff APK 和 Kitsune Mask 需要手动下载，脚本会弹出浏览器并等待文件放入工具包目录。

### giffgaff 版本旧

脚本会自动点击 "UPDATE IN 60 SECONDS" 按钮跳过更新提示。

### LSPosed/HookEuicc 未生效

重启 MuMu 实例后重新运行脚本即可。

### 日志位置

`logs/setup-日期时间.log`

---

## 技术架构

```
start.bat                    → 双击启动器（设置 UTF-8 + Bypass 策略）
setup-giffgaff-env.ps1       → 主脚本（交互式向导 + 自动化引擎）
tools/                       → 工具包目录（APK 和 ZIP）
logs/                        → 运行日志
```

### 自动化流程

```
用户双击 start.bat
    ↓
交互式向导：检测 MuMu → 选择实例 → 下载工具包 → 确认配置
    ↓
自动化引擎：启动 VM → Root → 安装 APK → Magisk → Zygisk → LSPosed → HookEuicc → giffgaff
    ↓
用户手动：登录 → 验证码 → 选套餐 → 付款 → 购买 eSIM
```

---

## License

MIT License

---

## 致谢

- [Kitsune Mask](https://github.com/topjohnwu/Magisk) (原 Magisk Delta)
- [LSPosed](https://github.com/LSPosed/LSPosed)
- [HookEuicc](https://github.com/Unicorn369/HookEuicc)
- [Via 浏览器](https://viayoo.com/)
- [MuMu Player](https://www.mumuplayer.com/)
