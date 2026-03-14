---
name: rk3588-closed-loop
description: 使用仓库内的自动化脚本和配置文件，对 RK3588 或类似嵌入式 Linux 板端程序执行交叉编译、部署、启动、抓日志和迭代分析。只要仓库中存在 `scripts/automation-config.json`，并且流程应通过配置文件适配不同机器路径、工具链、板端参数和程序变体，就应使用此 skill。
---

# RK3588 闭环流程

## 工作流

1. 把当前工作仓库视为根目录，先确认仓库下存在 `scripts/automation-config.json`。
2. 读取 `scripts/automation-config.json`，如果存在，再叠加读取 `scripts/automation-config.local.json`。
3. 不要假设固定的 Windows 路径、WSL 路径、板端 IP、部署目录、日志目录、日志前缀或程序名，一切以配置文件为准。
4. 从配置里的 `programs` 选择目标程序键。这个键是配置变体名，不要求等于真实可执行文件名。
5. 用 `scripts/build-rk3588.ps1` 只构建选中的目标。
6. 用 `scripts/deploy-rk3588.ps1` 部署到板端。
7. 用 `scripts/run-rk3588.ps1` 启动目标程序。
8. 用 `scripts/fetch-log-rk3588.ps1` 查看短日志。
9. 任何非简单判断前，都先用 `scripts/pull-full-log-rk3588.ps1` 拉取完整日志。
10. 如果问题在源码或配置，修复后重复上述闭环。

## 必须遵守

- 把 `scripts/automation-config.json` 视为公共基线配置。
- 把 `scripts/automation-config.local.json` 视为本机、本板卡、本工具链的覆盖配置。
- 如果仓库还没有 `scripts/automation-config.local.json`，优先从示例文件创建，而不是直接改公共脚本。
- 优先通过仓库内 `scripts/*.ps1` 执行闭环，不要临时手写长链式远端命令替代脚本。
- 在 Windows 侧执行仓库脚本时，优先使用 `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`。
- 只构建用户要求的目标，不要默认把全工程一起编译。
- 日志路径和日志匹配规则必须从 `programs.<name>.remoteLogGlob` 读取，不要在 skill 或执行步骤里写死。
- 如果同一个真实程序因编译宏、部署方式、启动方式或日志规则不同而存在多种形态，应拆成多个配置项，而不是共用一个程序项。
- 启动是否成功必须靠进程状态和日志判断，不能只看 `start.sh` 或远端命令是否返回。
- 如果没有 `plink/pscp`，优先退回到 WSL 的 `sshpass + ssh/scp`。
- 不要直接执行 `pwsh -> wsl -> sshpass -> ssh` 这类嵌套长命令去启停程序；这类命令在远端脚本挂住、后台进程未真正脱离会话或标准流未关闭时，容易把 Codex 会话一起卡住。
- 如果必须做一次性远端排查，优先使用仓库公共脚本封装；若不得不用直接远端命令，必须带连接超时与整体超时，并确保远端启动命令使用真正脱离会话的形式。
- 通过 `functions.shell_command` 调用这些 `scripts/*.ps1` 时，默认直接设置 `sandbox_permissions` 为 `require_escalated`，不要先在沙箱里试跑再重试，避免重复弹确认。

## 常用命令

在当前仓库根目录执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\fetch-log-rk3588.ps1 -Program <program-key> -TailLines 120
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\pull-full-log-rk3588.ps1 -Program <program-key>
```

其中 `<program-key>` 指配置文件 `programs` 下的键名。

如果是在 Codex 里执行上面这些命令，统一按提权命令处理：

- `functions.shell_command` 传入原始 PowerShell 命令。
- `sandbox_permissions` 固定为 `require_escalated`。
- `justification` 简短写明用途，例如“是否允许提权执行 RK3588 构建脚本？”。
- 这组脚本涉及 WSL、SSH、SCP、远端进程和板端日志，默认按提权路径执行，减少中途权限拦截。

## 决策点

- 如果部署时报 `Text file busy`，先停旧进程，再重新部署。
- 如果远端启动命令挂住会话，不要等待返回，直接检查进程和日志。
- 如果程序启动后没有产生日志，先检查进程是否存在，再检查 `remoteLogGlob` 是否匹配真实日志。
- 如果构建失败，先确认是否真的只构建了当前目标，以及配置项是否选对了程序变体。

## 参考

需要查看配置结构、闭环排障建议或迁移注意事项时，读取仓库中与 `scripts/` 配套的说明文档。
