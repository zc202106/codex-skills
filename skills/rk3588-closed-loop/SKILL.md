---
name: rk3588-closed-loop
description: 使用仓库内的自动化脚本和配置文件，对 RK3588 板端程序执行交叉编译、部署、启动、抓日志和迭代分析。适用于 SkyNode 板端闭环验证任务，包括 `rk_ptz` 或 `UpperControl` 在 WSL 中交叉编译、上传到板端、远端启停、抓取完整日志以及根据运行结果继续修复。只要仓库中存在 `scripts/automation-config.json`，并且流程应当通过配置文件适配不同机器路径、工具链和板端参数，就应使用此 skill。
---

# RK3588 板端闭环

## 工作流

1. 把当前工作仓库视为根目录，先确认仓库下存在 `scripts/automation-config.json`。
2. 先读取 `scripts/automation-config.json`，如果存在，再叠加读取 `scripts/automation-config.local.json`。
3. 不要假设固定的 Windows 路径、盘符、WSL 路径、板端 IP、日志目录或日志前缀，一切以配置文件为准。
4. 从配置里的 `programs` 选择目标变体键。这个键可以是 `rk_ptz_vi`、`rk_ptz_rtsp` 这类变体名，不要求等于真实可执行文件名。
5. 用 `scripts/build-rk3588.ps1` 只构建选中的目标。
6. 用 `scripts/deploy-rk3588.ps1` 部署到板端。
7. 用 `scripts/run-rk3588.ps1` 启动目标程序。
8. 用 `scripts/fetch-log-rk3588.ps1` 查看短日志。
9. 任何非简单判断前，都先用 `scripts/pull-full-log-rk3588.ps1` 拉取完整日志。
10. 如果问题在源码，修代码后重复上述闭环。

## 必须遵守

- 把 `scripts/automation-config.json` 视为公共基线配置。
- 把 `scripts/automation-config.local.json` 视为本机、本板卡、本工具链的覆盖配置。
- 如果仓库还没有 `scripts/automation-config.local.json`，优先从示例文件创建，而不是直接改公共脚本。
- 日志路径和日志匹配规则必须从 `programs.<name>.remoteLogGlob` 读取，不要在 skill 或执行步骤里写死。
- 同一个 `rk_ptz` 如果因编译宏不同而对应不同部署方式或日志规则，应拆成多个变体键，而不是共用一个配置项。
- 只构建用户要求的目标，不要默认把全工程一起编译。
- 启动是否成功必须靠进程状态和日志判断，不能只看 `start.sh` 是否返回。
- 如果某个仓库的日志前缀和历史经验不同，先改配置，再执行闭环。
- 如果没有 `plink/pscp`，优先退回到 WSL 的 `sshpass + ssh/scp`。
- 通过 `functions.shell_command` 调用这些 `scripts/*.ps1` 时，默认直接设置 `sandbox_permissions` 为 `require_escalated`，不要先在沙箱里试跑再重试，避免重复弹确认。

## 常用命令

在当前仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-rk3588.ps1 -Program rk_ptz_vi
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-rk3588.ps1 -Program rk_ptz_vi
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-rk3588.ps1 -Program rk_ptz_vi
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fetch-log-rk3588.ps1 -Program rk_ptz_vi -TailLines 120
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\pull-full-log-rk3588.ps1 -Program rk_ptz_vi
```

需要时把 `rk_ptz_vi` 替换成其他变体键，例如 `rk_ptz_rtsp`、`rk_ptz_uvc`，或替换成 `UpperControl`。

如果是在 Codex 里执行上面这些命令，统一按提权命令处理：

- `functions.shell_command` 传入原始 PowerShell 命令。
- `sandbox_permissions` 固定为 `require_escalated`。
- `justification` 简短写明用途，例如“是否允许提权执行 RK3588 构建脚本？”。
- 这组脚本涉及 WSL、SSH、SCP、远端进程和板端日志，默认按提权路径执行，减少中途权限拦截。

## 决策点

- 如果部署时报 `Text file busy`，先停旧进程，再重新部署。
- 如果 `start.sh` 挂住远端会话，不要傻等返回，直接去查 `ps -ef` 和最新日志。
- 如果 `rk_ptz` 报 NNG 连接拒绝，接着检查 `UpperControl` 是否已经正常启动，并一起分析两边日志。
- 如果在处理 `UpperControl` 时构建失败，先确认构建命令是不是只编了 `UpperControl` 目标。

## 参考

需要查看配置结构、真实路径坑点或运行期排障提示时，读取 `references/config-and-troubleshooting.md`。
