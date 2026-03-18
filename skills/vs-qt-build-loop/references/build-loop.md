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

- `config.template.json`
  用作通用模板，不写死具体项目路径
- `config.json`
  用作当前项目实例配置，允许写入已验证的实际路径和参数

迁移到新项目时，优先复制：

- `config.template.json -> config.json`

然后只改项目相关字段，不改脚本。

## 允许自动修复的典型场景

- Qt 生成文件缺失：重新执行 `qmake`
- 翻译输出目录缺失：重新生成 `.qm`
- 输出目录缺失：自动创建目录

## 不自动修复的场景

- 工具集或 SDK 缺失
- 第三方库真实缺失
- 系统级环境未安装
- 无法确认依赖关系的链接错误
