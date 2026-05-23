---
name: vs-qt-build-loop
description: 在 Windows 10/11 环境下，为 Visual Studio + Qt 项目提供自动构建、重试修复、自动运行、日志抓取和 UI 问题闭环。适用于 VS2017 与 Qt 5.11.0 项目，支持根据 `.sln`、`.vcxproj` 或 `.pro` 自动选择 MSBuild 或 qmake+jom，适合处理“修改代码 -> 编译 -> 运行 -> 抓日志 -> 分析 -> 继续修复”的问题，尤其适合 Qt GUI 工程中的 UI 逻辑 bug、运行期日志分析和可追溯闭环。
---

# VS + Qt 构建运行闭环

优先调用本技能目录下的脚本，不要在对话里临时重写整套流程。

## 快速入口

1. 默认读取 `config.local.json`。
2. 项目实例优先从 `config.local.example.json` 复制出 `config.local.json`，只覆盖项目差异。
3. 多项目并行时，优先使用 `config.<profile>.local.json`，并通过 `-Profile <name>` 选择。
4. 用 `tools/Resolve-BuildTarget.ps1` 识别 `.sln` / `.pro`。
5. 默认调用 `tools/Invoke-VsQtBuildLoop.ps1` 执行完整闭环。
6. 若同时存在 `.sln` 和 `.vcxproj`，不要直接单编 `.vcxproj`；优先走 `.sln`，否则依赖 `$(SolutionDir)` 的头文件、库路径和项目引用可能失效，导致把环境问题误判成“第三方库缺失”或“工具集错误”。
7. 项目采用Release+x64配置，不要去管Debug配置。
8. 优先采用增量编译。
9. 地面端编译验证时禁止运行 `lupdate` 和 `lrelease`；`.ts/.qm` 翻译文件由用户维护，除非用户明确要求单独处理翻译产物。
10. 用户要求快速或并行构建时，必须确认实际 MSBuild 命令包含 `/m`。如果闭环脚本当前配置没有传 `/m`，先用脚本完成标准验证，再按项目推荐命令补跑一次 `/m` 并行 MSBuild，或修正本地闭环配置后重跑。

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
- `tools/Update-QtTranslations.ps1` 仅在用户明确要求处理翻译文件时调用；普通地面端编译验证不要调用。

要求：

- 激活 `vcvarsall.bat`
- 注入 Qt 工具链
- 地面端编译验证时禁止运行 `lupdate`，不自动更新 `.ts`。
- 地面端编译验证时禁止运行 `lrelease`，不生成或覆盖 `.qm`。
- 不自动填写、修正、回退或覆盖 `.ts/.qm` 中已有翻译内容；翻译内容由用户维护。
- 不自动同步 `.qm` 到源码目录或 exe 目录，除非用户明确要求生成运行时翻译产物。
- 校验工程配置文件未被改写

### GroundNode 翻译约定

- `GroundNode/Ruiyan_UAV` 当前翻译文件使用 `zh.ts`、`en.ts`、`ar.ts`。
- 不再生成或引用旧文件名 `RuiyanUAV_CN.ts`、`RuiyanUAV_EN.ts`、`RuiyanUAV_RU.ts`。
- 若为 GroundNode 临时生成闭环配置，`translations.enabled` 必须默认为 `false`；只有用户明确要求处理翻译文件时，才允许启用翻译步骤。
- 不自动生成或覆盖 `.ts/.qm`，除非用户明确要求生成或更新运行时语言包。

### 3. 构建与修复

- `.sln` 优先走 `MSBuild`
- 只有 `.pro` 时走 `qmake + jom`
- 存在 `.sln` 时，不要退化成直接编单个 `.vcxproj`；很多 VS + Qt 工程把 `IncludePath`、`LibraryPath`、依赖项目和 `QtMsBuild` 绑定在解决方案上下文里
- 优先执行增量编译，只有工程配置、生成规则、关键依赖或中间产物状态变化导致增量结果不可信时，才切换到全量编译
- 需要手动补跑 MSBuild 时，优先使用 VS 安装目录下的 `Bin\amd64\MSBuild.exe` 并显式加 `/m`；不要因为 PowerShell 引号错误把 `Program Files (x86)` 里的 `x86` 解析成命令。可靠写法示例：

```powershell
& cmd.exe /c 'call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" amd64 && "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\amd64\MSBuild.exe" GroundNode\PoseidonCore.sln /p:Configuration=Release /p:Platform=x64 /m /v:minimal'
```

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
