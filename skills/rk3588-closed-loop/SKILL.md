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
5. 默认优先用 `scripts/loop-rk3588.ps1` 执行“构建 + 部署 + 启动 + 拉取完整日志”的单入口闭环。
6. 只有在需要单步排查时，才分别使用 `scripts/build-rk3588.ps1`、`scripts/deploy-rk3588.ps1`、`scripts/run-rk3588.ps1` 和 `scripts/pull-full-log-rk3588.ps1`。
7. 基于完整日志分析问题；如果问题在源码或配置，修复后重复上述闭环。

## 必须遵守

- 把 `scripts/automation-config.json` 视为公共基线配置。
- 把 `scripts/automation-config.local.json` 视为本机、本板卡、本工具链的覆盖配置。
- 如果仓库还没有 `scripts/automation-config.local.json`，优先从示例文件创建，而不是直接改公共脚本。
- 优先通过仓库内 `scripts/*.ps1` 执行闭环，不要临时手写长链式远端命令替代脚本。
- 为减少 Codex 的提权确认次数，默认优先使用 `scripts/loop-rk3588.ps1` 作为单入口脚本。
- 在 Windows 侧执行仓库脚本时，优先使用 `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`。
- 只构建用户要求的目标，不要默认把全工程一起编译。
- 在 WSL1 或疑似 WSL1 环境下执行构建时，不要从 PowerShell 并发启动多个独立 `wsl.exe make ...` / `wsl.exe cmake --build ...` 会话；这类调用可能让 `make/cc1plus` 收到 `SIGHUP` 并报 `Hangup`。Codex 中不要反复尝试这种已知失败路径。
- 从 Codex/PowerShell 调用 `wsl bash -lc '...'` 时，不要在命令里使用 Bash 的 `$!`、`$?`、`$p1`、`$p2` 等变量做并行 PID 或退出码管理；调用层可能提前展开或污染这些变量，表现为 PID/退出码为空、路径错位、`wait: pid 0 is not a child`、`Hangup`。不要尝试靠反复改引号或反斜杠修补，直接改用下面“正确构建方式”。
- 不要把多行 PowerShell here-string 直接通过管道传给 `wsl bash` 来做最终构建退出码判断；Windows CRLF 可能残留到 Bash 脚本里，出现 `exit: 0\r: numeric argument required` 或 `syntax error: unexpected end of file`，即使前面的 `Built target eop` 已经成功也会让工具返回失败。需要多行脚本时，优先使用 `wsl bash -lc '...'` 单行脚本；如果必须管道输入，先严格转换为 LF，并避免用 `exit $((...))` 这类会被 CRLF 污染的最终判断。
- 日志路径和日志匹配规则必须从 `programs.<name>.remoteLogGlob` 读取，不要在 skill 或执行步骤里写死。
- 如果同一个真实程序因编译宏、部署方式、启动方式或日志规则不同而存在多种形态，应拆成多个配置项，而不是共用一个程序项。
- 启动是否成功必须靠进程状态和日志判断，不能只看 `start.sh` 或远端命令是否返回。
- 如果没有 `plink/pscp`，优先退回到 WSL 的 `sshpass + ssh/scp`。
- 远程执行板端命令时，必须使用非登录、非交互 shell，统一通过 `env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root USER=root LOGNAME=root /bin/sh -c '<command>'` 包装，并对 SSH 使用 `-T` 禁止伪终端。不要用 `bash -l`、`bash -lc`、交互 shell 或依赖 `/etc/profile` 的命令启动板端程序；现场已确认自动化新 SSH 会话可能触发 `/etc/profile.d/udiskie.sh` 异常，而人工使用路径不会触发。需要复杂命令时也应通过 skill/仓库脚本的 `Invoke-RemoteCommand` 入口执行，不要手写绕过该包装。
- detached 远程启动不要使用 `sh -lc` 或 `bash -lc`，应通过最小环境的 `/bin/sh -c` 后台启动，例如由脚本生成 `nohup env -i ... /bin/sh -c '<start command>' </dev/null >/tmp/<program>-codex-start.log 2>&1 &`。
- 不要直接执行 `pwsh -> wsl -> sshpass -> ssh` 这类嵌套长命令去启停程序；这类命令在远端脚本挂住、后台进程未真正脱离会话或标准流未关闭时，容易把 Codex 会话一起卡住。
- 如果必须做一次性远端排查，优先使用仓库公共脚本封装；若不得不用直接远端命令，必须带连接超时与整体超时，并确保远端启动命令使用真正脱离会话的形式。
- 通过 `functions.shell_command` 调用这些 `scripts/*.ps1` 时，默认直接设置 `sandbox_permissions` 为 `require_escalated`，不要先在沙箱里试跑再重试，避免重复弹确认。

## 常用命令

在当前仓库根目录执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-rk3588.ps1 -Program <program-key>
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\pull-full-log-rk3588.ps1 -Program <program-key>
```

其中 `<program-key>` 指配置文件 `programs` 下的键名。

如果需要在 Codex 里验证多个 WSL/CMake 构建目录，直接使用单个 WSL shell 顺序执行，避免 PowerShell 展开 Bash 变量，也避免多个独立 `wsl.exe` 会话触发 `Hangup`。这是默认正确方式，不要先尝试带 `$!/$?/wait` 的并行写法：

```powershell
wsl bash -lc 'set -e; cd /mnt/d/path/to/repo/SkyNode; /opt/cmake/bin/cmake --build cmake-build-debug-3588eop --target eop -- -j2; /opt/cmake/bin/cmake --build cmake-build-debug-3576eop --target eop -- -j2; test -x cmake-build-debug-3588eop/eop; test -x cmake-build-debug-3576eop/eop; echo SKY_BOTH_BUILDS_OK'
```

如果脱离 Codex、在人工 PowerShell 终端里确实要并行，必须先确认 `$!/$?` 没有被 PowerShell 提前展开；否则仍使用上面的顺序命令。不要把下面这种并行 PID 管理写法作为 Codex 默认验证命令：

```powershell
wsl bash -lc 'set -o pipefail; cd /mnt/d/path/to/repo; (/opt/cmake/bin/cmake --build SkyNode/cmake-build-debug-3588eop --target eop -- -j2) & p1=$!; (/opt/cmake/bin/cmake --build SkyNode/cmake-build-debug-3576eop --target eop -- -j2) & p2=$!; wait $p1; r1=$?; wait $p2; r2=$?; echo RK3588_EXIT=$r1; echo RK3576_EXIT=$r2; if [ $r1 -ne 0 ] || [ $r2 -ne 0 ]; then exit 1; fi'
```

如果已经看到 PID/退出码为空、`wait: pid 0 is not a child`、`Hangup` 或路径跳到错误目录，不要继续试同类并行命令；立即改用上面的顺序构建命令，并在结论中明确前一次失败来自命令包装层而非 C++ 编译。

如果单目录构建也需要从 Windows 侧调用，优先使用：

```powershell
wsl bash -lc 'cd /mnt/d/path/to/build-dir && make eop -j2'
```

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
