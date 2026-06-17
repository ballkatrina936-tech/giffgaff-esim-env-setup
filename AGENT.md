# AGENT.md - AI Agent 执行指南

## 任务

在 Windows + MuMu 5 模拟器中自动搭建 giffgaff eSIM 环境。

## 前置条件检查

1. 确认操作系统为 Windows
2. 确认 MuMu Player 5 已安装（常见路径：`D:\Program Files\Netease\MuMuPlayer\nx_main`）
3. 确认至少有一个非主实例的 MuMu VM

## 执行步骤

### 步骤 1：克隆仓库（如尚未克隆）

```bash
git clone https://github.com/ballkatrina936-tech/giffgaff-esim-env-setup.git
```

### 步骤 2：检查工具包

检查工具包目录中是否有以下 5 个文件：

| 文件 | 自动下载 | 匹配模式 |
|------|----------|----------|
| LSPosed ZIP | ✅ 脚本自动下载 | `LSPosed-v1.9.2-*.zip` |
| Via APK | ✅ 脚本自动下载 | `via*.apk` |
| HookEuicc APK | ✅ 脚本自动下载 | `HookEuicc*.apk` |
| giffgaff APK | ❌ 需手动下载 | `giffgaff*.apk` |
| Kitsune Mask APK | ❌ 需手动下载 | `Kitsune*.apk` 或 `*Mask*.apk` |

如果缺少 giffgaff APK 或 Kitsune Mask，告知用户以下下载链接：
- giffgaff: https://mi9.com/package/com.giffgaffmobile.controller/download/
- Kitsune Mask: https://sourceforge.net/projects/magisk/files/Magisk%20Delta%20(Kitsune%20Mask)/

### 步骤 3：运行脚本

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File setup-giffgaff-env.ps1 -NonInteractive -VmIndex <VM编号> -ToolDir <工具包目录> [-MuMuDir <MuMu路径>]
```

### 步骤 4：处理结果

- **成功**：脚本输出 "配置完成"，giffgaff 已打开到登录页。告知用户手动登录和购买。
- **失败**：查看 `logs/` 目录下的日志文件，根据错误信息排查。

## 安全说明

- 脚本不会读取、记录或上传用户的账号密码、验证码
- 脚本不会代替用户付款或购买套餐
- 脚本仅修改指定 MuMu 实例的设置，不影响主系统
