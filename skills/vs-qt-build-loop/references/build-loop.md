# 构建闭环

## 适用内容

需要以下细节时再读取本文件：

- 构建入口如何选择
- 哪些编译错误允许自动修复
- 当前项目特化的 MSBuild 参数

## 构建入口

- 找到 `.sln`：优先 `MSBuild`
- 没有 `.sln` 但找到 `.pro`：`qmake + jom`
- 两者都存在且用户未指定：优先 `.sln`

### 常见误判

- 不要因为某个 `.vcxproj` 能单独打开，就直接拿它当主入口。
- 如果工程的 `IncludePath`、`LibraryPath`、项目依赖或 Qt 配置依赖 `$(SolutionDir)`，单编 `.vcxproj` 时这些路径可能不会展开。
- 典型表象：
  - 头文件明明在仓库里，却报 `json/json.h`、`xxx.lib`、`QtMsBuild` 等找不到
  - 日志里先看到 `Platform.default.props` 给出 `v100` 之类默认值，随后项目文件再覆盖成真实工具集，例如 `v141`；不要把前者误判成最终生效工具集
- 处理原则：
  - 只要仓库里有对应 `.sln`，先回到 `.sln` 入口复现
  - 再看解决方案级 `IncludePath`、`LibraryPath`、项目引用是否恢复正常
  - 只有确认 `.sln` 入口同样失败，才把问题归因到真实依赖缺失或工具链异常

## 当前项目的稳定参数

当前 `GroundNode/PoseidonCore.sln` 已验证可用的关键参数：

- `QtInstall=C:\Qt\Qt5.11.0\5.11.0\msvc2017_64`
- `QtMsBuild=D:\Video\150\GroundNode\QtMsBuild`
- `TrackFileAccess=false`
- `ForceRebuild=true`

## 配置拆分建议

- `config.json`
  用作公共基线配置，不写死具体项目路径
- `config.local.example.json`
  用作项目覆盖示例，展示如何只覆盖本机和本项目差异
- `config.local.json`
  用作当前机器的本地实例配置，建议加入 `.gitignore`
- `config.<profile>.local.json`
  用作多项目 profile 配置，例如 `config.groundnode.local.json`
- `projectGuard`
  用作工程配置保护，防止闭环过程中悄悄改写 `.sln/.vcxproj/.props/.targets/.pro/.pri`

迁移到新项目时，优先复制：

- `config.local.example.json -> config.local.json`

然后只改 `config.local.json` 里的项目相关字段，不改公共基线和脚本。

如果同一台机器要维护多个项目，推荐：

- `config.groundnode.local.json`
- `config.demo.local.json`
- `config.other.local.json`

运行时通过 `-Profile groundnode` 之类的参数切换，不要来回手改同一个 `config.local.json`。

## 工程配置保护

默认启用 `projectGuard`：

- 构建前扫描工程配置文件快照
- 构建后再次扫描
- 如发现变化，立即中止闭环
- 在 trace 日志目录输出 `project-config-guard.json`

这层保护只盯工程配置文件，不拦截正常源码修改。

## 允许自动修复的典型场景

- Qt 生成文件缺失：重新执行 `qmake`
- 输出目录缺失：自动创建目录

## 不自动修复的场景

- 工具集或 SDK 缺失
- 第三方库真实缺失
- 系统级环境未安装
- 无法确认依赖关系的链接错误
