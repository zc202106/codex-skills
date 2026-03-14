# 配置与排障说明

## 配置文件

- 公共基线配置：`<repo-root>/scripts/automation-config.json`
- 本地覆盖配置：`<repo-root>/scripts/automation-config.local.json`
- 本地覆盖示例：`<repo-root>/scripts/automation-config.local.example.json`

## 仓库发现规则

- 默认把当前工作目录对应的仓库当作根目录，除非有明确证据表明不是。
- 启用闭环流程前，先确认 `<repo-root>/scripts/automation-config.json` 存在。
- 如果用户换了另一份检出、另一台机器或另一块盘，不要改 skill，自适应读取该仓库自己的配置文件。

## 配置结构

- `repo`：仓库相关位置
- `repo.wslProjectPath`：`SkyNode` 的 WSL 路径
- `repo.fullLogLocalDir`：拉取完整日志时的本地目录
- `toolchain.cCompiler`、`toolchain.cxxCompiler`、`toolchain.cmake`
- `remote.host`、`remote.user`、`remote.password`
- `programs.<name>`：一个可执行程序的一个变体配置项，键名可以自定义
- `programs.<name>.buildDir`
- `programs.<name>.buildTarget`
- `programs.<name>.binaryRelativePath`
- `programs.<name>.remoteBinaryPath`
- `programs.<name>.remoteWorkDir`
- `programs.<name>.remoteStartCommand`
- `programs.<name>.remoteStopCommand`
- `programs.<name>.remoteLogGlob`：远端日志匹配规则，必须可配置
- `programs.<name>.configureArgs`

## 已验证的路径坑点

- `rk_ptz` 的真实可执行文件路径是 `/mnt/eop/vi/rk_ptz`，不是 `/mnt/eop/vi/rk_ptz/rk_ptz`
- `UpperControl` 的真实可执行文件路径是 `/mnt/eop/control/UpperControl`，不是 `/mnt/eop/control/UpperControl/UpperControl`
- `rk_ptz` 的工作目录是 `/mnt/eop/vi`
- `UpperControl` 的工作目录是 `/mnt/eop/control`
- `rk_ptz` 的完整日志前缀是 `rkptz*.log`，不是 `rk_ptz*.log`

## 日志配置原则

- skill 不应写死任何日志路径或日志前缀。
- 远端日志位置统一从 `programs.<name>.remoteLogGlob` 读取。
- 如果更换板卡、版本或部署目录后日志文件名规则变化，只修改配置文件，不修改 skill。
- 如果同一个 `rk_ptz` 因宏组合不同而产生不同日志前缀，应拆成多个 `programs.<name>` 变体配置。
- 拉完整日志时，先通过 `remoteLogGlob` 定位最新文件，再下载整份日志。

## 构建注意事项

- 构建 `UpperControl` 时应显式使用 `--target UpperControl`
- 构建 `rk_ptz` 时应显式使用 `--target rk_ptz`
- 当只验证单个程序时，不要顺手把整个工程一起编译
- 机器相关参数应放到 `automation-config.local.json`，尤其是板端 IP、登录凭据、WSL 路径和工具链路径

## 运行期注意事项

- `start.sh` 可能会一直占住 SSH 会话，判断是否启动成功时要看 `ps -ef` 和日志
- `pkill` 可能返回非零，但这不一定代表失败，启停后仍要检查真实进程状态
- `Text file busy` 说明旧进程还占着可执行文件，需要先停进程、稍等，再重新部署
- 如果 `rk_ptz` 报 `ipc:///tmp/nng/upper.nng` 连接拒绝，下一步优先检查 `UpperControl` 进程和日志
