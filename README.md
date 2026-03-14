# codex-skills

这个仓库提供一套面向嵌入式 Linux 板端程序的 Codex skills 和配套自动化脚本，重点解决的是“闭环流程”本身，而不是某个具体业务程序的历史坑点。

当前核心目标是让使用者可以围绕同一套流程完成：

- 读取配置
- 交叉编译
- 部署到板端
- 远端停止和启动
- 拉取完整日志
- 基于日志继续修复并重复闭环

## 当前包含的 Skill

### rk3588-closed-loop

适用于 RK3588 或类似嵌入式 Linux 板端程序的自动化闭环验证。

这个 skill 不绑定某个具体程序名。只要你的业务仓库中存在：

- `scripts/automation-config.json`
- 可选的 `scripts/automation-config.local.json`
- 一组与配置匹配的 `scripts/*.ps1`

就可以通过配置里的 `programs` 定义不同程序变体，然后复用同一套闭环流程。

默认推荐使用单入口脚本 `scripts/loop-rk3588.ps1` 执行完整闭环，这样更容易减少 Codex 中重复的提权确认。

## 推荐目录结构

建议把本仓库的 `scripts/` 目录复制到你的业务仓库根目录，让 skill 直接驱动业务仓库自己的配置和产物。

```text
your-project/
├─ scripts/
│  ├─ automation-config.json
│  ├─ automation-config.local.example.json
│  ├─ automation-config.local.json
│  ├─ common.ps1
│  ├─ build-rk3588.ps1
│  ├─ deploy-rk3588.ps1
│  ├─ run-rk3588.ps1
│  ├─ loop-rk3588.ps1
│  ├─ pull-full-log-rk3588.ps1
│  └─ show-rk3588-programs.ps1
├─ src/
├─ build/
└─ ...
```

## 安装 Skill

可通过 Codex 的 skill 安装脚本从本仓库安装：

```bash
$skill-installer --repo zc202106/codex-skills --path skills/rk3588-closed-loop
```

等价命令：

```bash
python ~/.codex/skills/install/.system-skill/skill-installer/scripts/install-skill-from-github.py --repo zc202106/codex-skills --path skills/rk3588-closed-loop
```

## 接入步骤

### 1. 复制脚本

将本仓库的 `scripts/` 目录复制到你的业务仓库根目录。

### 2. 生成本地配置

从：

```text
scripts/automation-config.local.example.json
```

复制生成：

```text
scripts/automation-config.local.json
```

不要直接把机器差异写进公共基线 `automation-config.json`。

### 3. 配置程序变体

在 `automation-config.json` 的 `programs` 节点中，为每个目标程序或变体维护独立配置项。

每个程序项至少应明确：

- `buildDir`
- `buildTarget`
- `binaryRelativePath`
- `remoteBinaryPath`
- `remoteWorkDir`
- `remoteStartCommand`
- `remoteStopCommand`
- `remoteLogGlob`
- `configureArgs`

### 4. 填写本机覆盖配置

`automation-config.local.json` 通常至少要补这些字段：

- `repo.wslProjectPath`
- `toolchain.wslDistro`
- `toolchain.cCompiler`
- `toolchain.cxxCompiler`
- `toolchain.cmake`
- `remote.host`
- `remote.user`
- `remote.password`

如果某个程序在你的机器或板卡上有特殊日志规则，也可以在本地覆盖配置中重写 `programs.<name>.remoteLogGlob`。

## 配置原则

### automation-config.json

用于描述公共结构，适合放：

- 默认程序定义
- 默认构建目录
- 默认部署目录
- 默认启动和停止命令
- 默认日志匹配规则

### automation-config.local.json

用于描述本机差异，适合放：

- WSL 工程路径
- 工具链路径
- 当前板端登录信息
- 与本机或当前板卡相关的日志覆盖

### 通用约束

- 不要假设固定的程序名。
- 不要假设固定的日志前缀。
- 不要假设固定的部署目录。
- 不要把项目特有坑点写死到 skill 逻辑里。
- 所有程序差异都应通过 `programs.<name>` 配置项表达。

## 环境依赖

建议至少具备以下环境：

- PowerShell 7，也就是 `pwsh`
- WSL
- 交叉编译工具链
- `sshpass` 或 PuTTY 的 `plink/pscp`

如果没有 `plink/pscp`，脚本会自动回退到 WSL 里的 `sshpass + ssh/scp`。

### 安装 pwsh

Windows 上推荐安装 PowerShell 7，并确保命令行里可以直接执行 `pwsh`。

```powershell
winget install --id Microsoft.PowerShell --source winget
pwsh -v
```

如果没有 `winget`，也可以直接从官方发布页下载安装包：

```text
https://github.com/PowerShell/PowerShell/releases
```

### 安装 sshpass

如果你不打算使用 PuTTY 的 `plink/pscp`，建议在 WSL 中安装 `sshpass`。

以 Ubuntu 为例：

```bash
sudo apt-get update
sudo apt-get install -y sshpass
command -v sshpass
sshpass -V
```

如果你使用的是其他 WSL 发行版，请改用对应发行版的包管理器安装。

### 可选方案：使用 PuTTY

如果你不想在 WSL 里安装 `sshpass`，也可以在 Windows 侧安装 PuTTY，并确保以下命令可用：

- `plink`
- `pscp`

## 首次接入自检

第一次接入新机器或新工程时，建议按顺序执行下面这些检查。

### 1. 检查 `pwsh`

```powershell
pwsh -v
```

### 2. 检查 WSL

```powershell
wsl -l -v
```

### 3. 检查 `sshpass`

```powershell
wsl bash -lc "command -v sshpass && sshpass -V"
```

如果这里失败，而你又没有安装 `plink/pscp`，后续密码登录闭环会无法完成。

### 4. 检查配置文件

```powershell
Get-ChildItem .\scripts\automation-config*
```

至少应存在：

- `scripts/automation-config.json`
- `scripts/automation-config.local.json`

### 5. 检查程序配置是否被正确识别

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\show-rk3588-programs.ps1
```

预期结果是能列出 `programs` 中定义的程序键。

### 6. 检查 WSL 工程路径和工具链

```powershell
wsl bash -lc "cd <你的wslProjectPath> && <你的cmake路径> --version"
```

### 7. 检查板端连通性

```powershell
wsl bash -lc "sshpass -p '<你的密码>' ssh -o StrictHostKeyChecking=no <user>@<host> 'echo BOARD_OK'"
```

预期结果是返回 `BOARD_OK`。

### 8. 最小闭环顺序

建议先用最小流程验证环境，而不是一开始就直接构建部署：

1. `show-rk3588-programs.ps1`
2. `pull-full-log-rk3588.ps1`
3. `loop-rk3588.ps1`

## 配置示例

下面是一个通用示例，重点在配置结构，不代表某个具体项目必须这样命名：

```json
{
  "repo": {
    "wslProjectPath": "/mnt/d/your-project"
  },
  "toolchain": {
    "wslDistro": "Ubuntu",
    "cCompiler": "/opt/toolchains/host/bin/aarch64-linux-gnu-gcc",
    "cxxCompiler": "/opt/toolchains/host/bin/aarch64-linux-gnu-g++",
    "cmake": "/opt/toolchains/host/bin/cmake"
  },
  "remote": {
    "host": "192.168.1.100",
    "user": "root",
    "password": "change-me"
  },
  "programs": {
    "app_default": {
      "buildDir": "build-app-default",
      "buildTarget": "app",
      "binaryRelativePath": "build-app-default/app",
      "remoteBinaryPath": "/opt/app/app",
      "remoteWorkDir": "/opt/app",
      "remoteStartCommand": "cd /opt/app && ./start.sh &",
      "remoteStopCommand": "pkill -f app",
      "remoteLogGlob": "/var/log/app*.log",
      "configureArgs": [
        "-DBUILD_RK3588=ON"
      ]
    }
  }
}
```

## 常见配置错误

### 1. 把 Windows 路径填到 `wslProjectPath`

错误示例：

- `D:\work\project`

正确形式必须是：

- `/mnt/d/work/project`

### 2. 不同变体共用同一个错误的日志规则

如果不同变体产生日志的目录或前缀不同，就必须拆成不同配置项，否则程序可能已经运行，但脚本会误判为“没日志”。

### 3. 把本机差异直接写进 `automation-config.json`

本机、板卡、账号、密码、工具链路径这些差异项应放在 `automation-config.local.json`。

### 4. 只改了远端可执行文件路径，没同步改工作目录

有些程序启动依赖相对路径、配置文件和同目录脚本。如果工作目录不对，即使可执行文件上传成功，也可能启动异常。

### 5. 没按真实部署方式拆分程序变体

如果编译宏、部署目录、启动命令或日志规则不同，就应该拆成多个程序项。

## 推荐执行方式

在业务仓库根目录优先使用 `pwsh` 执行脚本。默认建议先用单入口闭环脚本：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-rk3588.ps1 -Program <program-key>
```

如果需要拆开排查，再分别执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\pull-full-log-rk3588.ps1 -Program <program-key>
```

其中 `<program-key>` 指配置文件 `programs` 下的键名。

## 当前脚本特性

这套脚本是按“闭环稳定执行”收敛的，重点包括：

- 外部命令统一增加超时控制，避免无限挂住
- 启动脚本改为真正脱离 SSH 会话的方式
- 部署前自动尝试停止旧进程，减少 `Text file busy`
- 远端输出抑制 host-key 提示，避免污染日志路径解析
- 日志不存在时返回明确结果，而不是脚本空指针
- 启动后会主动检查进程状态

## 在 Codex 中使用的建议

- 优先直接调用业务仓库里的 `scripts/*.ps1`
- 统一使用 `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`
- 为减少提权确认次数，优先使用 `loop-rk3588.ps1` 这种单入口脚本
- 这类命令通常涉及 WSL、SSH、SCP、远端进程和板端日志，建议直接按提权命令处理

不建议直接手写这类长链命令去启停程序：

```text
pwsh -> wsl -> sshpass -> ssh
```

## 常见闭环问题

### 1. 部署时报 `Text file busy`

说明旧进程还占着可执行文件，应先停旧进程，再重新部署。

### 2. 远端启动命令一直不返回

不要只盯着命令返回值，应该继续检查：

- 远端进程是否存在
- 最新日志是否有新增内容

### 3. 没抓到日志

优先检查：

- `programs.<name>.remoteLogGlob` 是否正确
- 目标程序是否真的启动成功
- 日志规则是否与当前部署方式一致

## 适用边界

这个仓库解决的是“自动化闭环流程”问题，不替代业务仓库自身的配置管理。具体程序名、板端目录、日志前缀、交叉工具链路径、构建宏组合，都应由业务仓库自己的 `scripts/automation-config*.json` 决定。
