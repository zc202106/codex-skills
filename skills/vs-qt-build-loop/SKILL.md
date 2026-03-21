---
name: vs-qt-build-loop
description: 在 Windows 10/11 环境下，为 Visual Studio + Qt 项目提供自动构建、重试修复、翻译更新、自动运行、日志抓取和 UI 问题闭环。适用于 VS2017 与 Qt 5.11.0 项目，支持根据 `.sln`、`.vcxproj` 或 `.pro` 自动选择 MSBuild 或 qmake+jom，适合处理“修改代码 -> 编译 -> 运行 -> 抓日志 -> 分析 -> 继续修复”的问题，尤其适合 Qt GUI 工程中的 UI 逻辑 bug、翻译文件同步、运行期日志分析和可追溯闭环。
---

# VS + Qt 构建运行闭环

优先调用本技能目录下的脚本，不要在对话里临时重写整套流程。

## 快速入口

1. 默认读取 `config.json`。
2. 项目实例优先从 `config.local.example.json` 复制出 `config.local.json`，只覆盖项目差异。
3. 多项目并行时，优先使用 `config.<profile>.local.json`，并通过 `-Profile <name>` 选择。
4. 用 `tools/Resolve-BuildTarget.ps1` 识别 `.sln` / `.pro`。
5. 默认调用 `tools/Invoke-VsQtBuildLoop.ps1` 执行完整闭环。

## 主流程

### 1. UI 问题

当用户描述的是 UI 逻辑 bug：

- 先用 `tools/Add-DiagnosticLogs.ps1` 生成候选文件和日志建议。
- 把日志加到实际代码位置，再进入完整闭环。
- 如果连续 2 轮仍不明确，必须加日志，不靠猜。

UI 诊断与复现细节见：

- `references/ui-diagnostics.md`

### 2. 构建前准备

- `tools/Initialize-BuildEnvironment.ps1`
- `tools/Update-QtTranslations.ps1`

要求：

- 激活 `vcvarsall.bat`
- 注入 Qt 工具链
- 更新 `.ts`
- 生成 `.qm`
- 同步到源码目录和 exe 目录
- 校验工程配置文件未被改写

构建与翻译细节见：

- `references/build-loop.md`

### 3. 构建与修复

- `.sln` 优先走 `MSBuild`
- 只有 `.pro` 时走 `qmake + jom`
- 编译失败时调用 `tools/Analyze-BuildError.ps1`
- 仅执行低风险自动修复
- 最多 3 轮，失败后交给用户

### 4. 运行与日志

构建成功后继续执行：

- `tools/Start-ProgramWithLogs.ps1`
- `tools/Invoke-ReproScenario.ps1`
- `tools/Analyze-RuntimeLog.ps1`

如果 `repro.mode=ui-automation`，自动调用：

- `tools/Invoke-UiAutomationScenario.ps1`

运行期细节见：

- `references/runtime-loop.md`

### 5. 追溯与报告

在 `.sln` 同级生成 `_codex_trace/<timestamp-attempt>/`，至少保留：

- `change-summary.md`
- `context.json`
- `before/`
- `after/`
- `logs/`

闭环结束后输出：

- `build-report.md`
- `build-report.json`
- `qm-manifest.json`
- `runtime.log`
- `runtime-analysis.json`
- `repro-summary.json`

## 约束

- 不要超过 3 次自动修复重试。
- 不要自动安装 VS、Qt、SDK 或修改系统级注册表。
- 不要在依赖不确定时胡乱增删库。
- 对 Qt GUI 程序，即使日志为空，也要记录运行结果。
