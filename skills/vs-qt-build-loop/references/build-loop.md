# 构建闭环

## 适用内容

需要以下细节时再读取本文件：

- 构建入口如何选择
- 翻译文件如何同步
- 哪些编译错误允许自动修复
- 当前项目特化的 MSBuild 参数

## 构建入口

- 找到 `.sln`：优先 `MSBuild`
- 没有 `.sln` 但找到 `.pro`：`qmake + jom`
- 两者都存在且用户未指定：优先 `.sln`

## 翻译更新

构建前调用：

- `tools/Update-QtTranslations.ps1`

动作包括：

- 扫描 `translations.tsPatterns`
- 执行 `lupdate`
- 执行 `lrelease`
- 生成 `qm-manifest.json`
- 复制 `.qm` 到：
  - `translations.qmOutputDirectory`
  - `translations.copyTargets`

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
- 翻译输出目录缺失：重新生成 `.qm`
- 输出目录缺失：自动创建目录

## 不自动修复的场景

- 工具集或 SDK 缺失
- 第三方库真实缺失
- 系统级环境未安装
- 无法确认依赖关系的链接错误
