# rk3588-closed-loop

## 适用场景

适用于 RK3588 或类似嵌入式 Linux 板端程序的自动化闭环验证。

目标流程包括：

- 读取配置
- 交叉编译
- 部署到板端
- 远端停止和启动
- 拉取完整日志
- 基于日志继续修复并重复闭环

## 目录与使用方式

这个 skill 不绑定某个具体程序名。只要你的业务仓库中存在：

- `scripts/automation-config.json`
- 可选的 `scripts/automation-config.local.json`
- 一组与配置匹配的 `scripts/*.ps1`

就可以通过配置里的 `programs` 定义不同程序变体，然后复用同一套闭环流程。

默认推荐使用单入口脚本：

- `scripts/loop-rk3588.ps1`

## 推荐目录结构

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

- 不要假设固定的程序名
- 不要假设固定的日志前缀
- 不要假设固定的部署目录
- 不要把项目特有坑点写死到 skill 逻辑里
- 所有程序差异都应通过 `programs.<name>` 配置项表达

## 环境依赖

建议至少具备以下环境：

- PowerShell 7，也就是 `pwsh`
- WSL
- 交叉编译工具链
- `sshpass` 或 PuTTY 的 `plink/pscp`

如果没有 `plink/pscp`，脚本会自动回退到 WSL 里的 `sshpass + ssh/scp`。

## 首次接入自检

建议按顺序执行：

1. `pwsh -v`
2. `wsl -l -v`
3. `wsl bash -lc "command -v sshpass && sshpass -V"`
4. `Get-ChildItem .\scripts\automation-config*`
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\show-rk3588-programs.ps1`

## 推荐执行方式

优先使用单入口脚本：

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

## 常见问题

### 1. 部署时报 `Text file busy`

说明旧进程还占着可执行文件，应先停旧进程，再重新部署。

### 2. 远端启动命令一直不返回

继续检查：

- 远端进程是否存在
- 最新日志是否有新增内容

### 3. 没抓到日志

优先检查：

- `programs.<name>.remoteLogGlob` 是否正确
- 目标程序是否真的启动成功
- 日志规则是否与当前部署方式一致

## 适用边界

这个 skill 解决的是“自动化闭环流程”问题，不替代业务仓库自身的配置管理。
