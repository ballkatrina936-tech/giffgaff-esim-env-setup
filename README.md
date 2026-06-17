# giffgaff eSIM 环境自动化工具

这个工具用于在 Windows + MuMu 5 模拟器里自动配置 giffgaff eSIM 所需环境：MuMu root、Kitsune Mask/Magisk、Zygisk、LSPosed、HookEuicc、giffgaff App。

脚本只会自动做到 giffgaff 登录页。账号密码、验证码、付款、地址、eSIM 购买和最终提交都需要你自己手动完成。

## 适合谁

- 想低成本准备 giffgaff 海外手机号/eSIM 环境的用户
- 不熟悉 MuMu、Magisk、LSPosed、ADB 的普通用户
- 想把教程步骤减少到“一键配置 + 自己登录”的用户

## 重要提醒

- 第一版只支持 Windows + MuMu 5。
- 不支持雷电、夜神、蓝叠等其他模拟器。
- 强烈建议新建一个干净 MuMu 实例运行脚本，不要直接操作你日常使用的主实例。
- 脚本会修改指定 MuMu 实例的 root 和系统盘可写设置。
- 不会记录、读取、上传你的账号密码或验证码。
- 不会代替你付款、购买套餐、提交 eSIM 申请。

## 工具包下载

请新建一个工具包目录，例如：

```powershell
C:\giffgaff_tools
```

把下面文件下载到这个目录。

脚本可以自动下载：

- LSPosed  
  https://github.com/LSPosed/LSPosed/releases/download/v1.9.2/LSPosed-v1.9.2-7024-zygisk-release.zip
- Via 浏览器  
  https://res.viayoo.com/v1/via-release.apk

需要你手动下载：

- MuMu 模拟器  
  https://www.mumuplayer.com/download/
- HookEuicc  
  https://github.com/Unicorn369/HookEuicc
- giffgaff APK  
  https://mi9.com/package/com.giffgaffmobile.controller/download/
- Kitsune Mask 备份  
  https://mega.nz/file/DEUVTRBA#lGEogAthS3kt2YuCmi0kszwPuFV4KI0o3-hApgdBxEw

Kitsune Mask 说明：原项目页面已失效，这里只放备份链接，仅供学习交流使用。请自行判断来源可信度。

## 文件名要求

工具包目录中至少需要能匹配到这些文件：

```text
HookEuicc*.apk
giffgaff*.apk
Kitsune*.apk 或 *Mask*.apk
LSPosed-v1.9.2-7024-zygisk-release.zip
via-release.apk 或 Via*.apk
```

如果 LSPosed 或 Via 不存在，脚本会尝试自动下载。

## 使用方法

1. 安装 MuMu 模拟器 5。
2. 打开 MuMu 多开器，新建一个干净实例。
3. 启动新实例一次，确认能进入桌面，然后关闭或保持打开都可以。
4. 准备工具包目录，例如 `C:\giffgaff_tools`。
5. 右键 PowerShell，选择“以管理员身份运行”。
6. 进入脚本所在目录。
7. 用新实例编号运行。新建的第二个实例通常是 `1`：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1 -ToolDir C:\giffgaff_tools -VmIndex 1
```

如果你的新实例编号不是 `1`，请把 `-VmIndex 1` 改成对应编号。主实例通常是 `0`，不建议用于第一次测试。

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1 -ToolDir C:\giffgaff_tools -VmIndex 2
```

## 脚本会做什么

脚本会自动执行：

1. 检测 MuMu 5 和 `mumu-cli.exe`。
2. 启动指定 MuMu 实例。
3. 开启 root 权限。
4. 开启系统盘可写。
5. 安装 Via、giffgaff、Kitsune Mask、HookEuicc。
6. 推送 LSPosed ZIP 到模拟器下载目录。
7. 在 Kitsune Mask 中安装 Magisk。
8. 开启 Zygisk。
9. 安装 LSPosed 模块。
10. 在 LSPosed 中启用 HookEuicc。
11. 给 HookEuicc 勾选电话服务和 giffgaff。
12. 打开 HookEuicc 主开关。
13. 打开 giffgaff，并停在登录页。

## 你需要手动做什么

脚本结束后，请你自己完成：

- 输入 giffgaff 账号密码
- 输入邮箱或短信验证码
- 选择套餐或 eSIM
- 填写地址
- 付款
- 确认最终购买/提交

这些步骤涉及敏感信息或真实交易，脚本不会自动处理。

## 常见问题

### 提示找不到 MuMu

请先安装 MuMu 5，并确认能正常打开一次。脚本会自动搜索常见安装路径：

- `D:\Program Files\Netease\MuMuPlayer\nx_main`
- `C:\Program Files\Netease\MuMuPlayer\nx_main`
- `C:\Program Files (x86)\Netease\MuMuPlayer\nx_main`

如果你安装在其他目录，可以用：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1 -ToolDir C:\giffgaff_tools -MuMuDir "D:\Your\MuMu\nx_main"
```

### 提示需要传入 `-VmIndex`

请先在 MuMu 多开器中新建一个干净实例，然后带上实例编号运行，例如：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-giffgaff-env.ps1 -ToolDir C:\giffgaff_tools -VmIndex 1
```

这样可以避免脚本修改你日常使用的主实例。

### 提示缺少 APK 或 ZIP

请按照“工具包下载”章节补齐文件。LSPosed 和 Via 会自动下载，其他文件需要你手动下载。

### giffgaff 提示版本旧

脚本会点击 “UPDATE IN 60 SECONDS” 尝试进入流程。如果未来 giffgaff 强制更新，请重新下载最新版 giffgaff APK 后再运行脚本。

### LSPosed 或 HookEuicc 没生效

重新运行脚本。脚本会重复检查并尽量修复已完成但未生效的步骤。

### 日志在哪里

日志保存在脚本目录下：

```text
logs\setup-日期时间.log
```

遇到问题时，把日志里的最后几十行发给维护者。
