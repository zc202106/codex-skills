---
name: vs-qt-build-loop
description: 在 Windows 10/11 环境下，为 Visual Studio + Qt 项目提供自动构建、日志分析、自动修复重试、翻译更新与产物报告闭环。适用于 VS2017 与 Qt 5.11.0 项目，支持根据 `.sln`、`.vcxproj` 或 `.pro` 自动选择 MSBuild 或 qmake+jom，自动激活 `vcvarsall.bat` 与 Qt 工具链，捕获编译日志，执行低风险常见修复，扫描并更新 `.ts` 文件，使用 `lrelease` 生成 `.qm`，复制翻译产物到输出目录，并在解决方案同级保留每次修改的追溯记录。若连续 3 次闭环仍失败，则停止自动重试并将问题交由用户决定。
---

# VS + Qt 构建修复闭环

按下面流程工作，优先调用本技能目录下的 PowerShell 脚本，不要临时重写一套流程。

## 快速入口

1. 读取根目录下的 `config.json`，确认 VS2017、Qt 5.11.0、`jom`、项目根目录和构建参数。
2. 根据用户提供的路径，优先识别 `.sln`，其次识别 `.pro`。
3. 调用 `tools/Invoke-VsQtBuildLoop.ps1` 执行闭环。
4. 如果用户只要求更新翻译，直接调用 `tools/Update-QtTranslations.ps1`。
5. 如果用户只要求分析失败日志，直接调用 `tools/Analyze-BuildError.ps1`。

## 决策规则

### 选择构建入口

- 找到 `.sln`：优先使用 `MSBuild.exe`。
- 没有 `.sln` 但找到 `.pro`：使用 `qmake + jom`。
- 两者都存在：
  - 用户显式指定时，按用户要求。
  - 未指定时，优先 `.sln`，因为它更接近实际 VS 工程依赖关系。

### 选择修复策略

- 只做“低风险、可追溯、可重试”的自动修复。
- 每次修改前，先调用 `tools/New-TraceRecord.ps1` 保存追溯快照。
- 每轮修复后必须重新构建，不要仅凭日志推断成功。
- 最多闭环 3 次；第 3 次失败后停止自动修复，汇总问题交给用户决定。

## 标准闭环

### 0. UI 问题定位与诊断日志

当用户描述的是 UI 逻辑 bug 时，先执行：

- 根据问题描述定位界面入口、槽函数、状态同步点、界面刷新路径
- 调用 `tools/Add-DiagnosticLogs.ps1` 生成候选文件和诊断建议
- 在实际代码对应位置添加诊断日志，优先覆盖：
  - 用户操作入口
  - 信号/槽触发点
  - 关键条件分支
  - 关键状态变量变化
  - UI 刷新、数据回填、线程回调
- 如果同一问题连续 2 轮还无法定位，必须补日志，不靠猜

### 1. 环境激活

调用 `tools/Initialize-BuildEnvironment.ps1`：

- 激活 `vcvarsall.bat`
- 注入 Qt 的 `bin`、`qmake`、`lupdate`、`lrelease`
- 校验 `MSBuild`、`qmake`、`jom`、`lupdate`、`lrelease` 是否可用
- 将最终环境写入日志

### 2. 构建方式识别

由 `tools/Resolve-BuildTarget.ps1` 输出：

- `BuildMode`: `msbuild` 或 `qmake`
- `SolutionPath` / `ProPath`
- `BuildDirectory`
- `OutputDirectory`
- `TraceRoot`

### 3. 翻译产物更新

构建前调用 `tools/Update-QtTranslations.ps1`：

- 扫描 `translations` 配置中声明的 `.ts` 文件
- 执行 `lupdate`
- 执行 `lrelease`
- 把 `.qm` 复制到：
  - 项目源码目录中的翻译同步目录
  - 构建输出目录 / exe 所在目录
- 生成 `qm-manifest.json`

### 4. 编译与日志捕获

由 `tools/Invoke-VsQtBuildLoop.ps1` 调用：

- `MSBuild` 模式：
  - 必须显式传入 `Configuration`、`Platform`
  - 日志写入独立文件
- `qmake` 模式：
  - 先执行 `qmake`
  - 再执行 `jom`
  - 构建目录与源码目录分离

### 5. 错误分析与自动修复

调用 `tools/Analyze-BuildError.ps1`：

- 读取最新日志
- 匹配 `config.json` 中的常见错误规则
- 输出：
  - `ErrorCategory`
  - `Confidence`
  - `SuggestedFixes`
  - `CanAutoFix`

如果 `CanAutoFix=true`，则在 `Invoke-VsQtBuildLoop.ps1` 中执行对应修复器。默认只自动处理以下类型：

- Qt 生成文件缺失：重新执行 `qmake`
- 翻译输出目录缺失：自动创建目录并重新生成 `.qm`
- `LNK1104` 或文件路径缺失且目标目录不存在：自动创建目录
- `MSB8020`、工具集或 SDK 缺失：只报告，不自动改系统环境
- 头文件/库文件真实缺失：只报告，不猜测依赖

### 6. 自动运行与运行日志

构建成功后，不要直接结束，继续调用：

- `tools/Invoke-ReproScenario.ps1`
- `tools/Start-ProgramWithLogs.ps1`
- `tools/Analyze-RuntimeLog.ps1`

要求：

- 若配置中声明了复现步骤，先记录并执行复现步骤
- 自动启动配置中的目标 exe
- 在进程工作目录下运行，抓取标准输出/标准错误到日志文件
- 按配置决定等待时长、是否超时结束进程、是否允许非 0 退出码
- 将运行日志纳入本轮追溯目录
- 如果运行日志命中可自动修复规则，则进入下一轮闭环
- 如果运行阶段 3 轮内仍无法自动解决，则停止并交由用户决定

### 6.1 UI 场景复现

处理 UI 逻辑 bug 时，尽量把用户描述转成可执行或半自动可执行步骤：

- 进入哪个窗口
- 点击、切换、输入、确认的顺序
- 期望行为
- 实际行为
- 是否依赖登录态、配置文件、语言包、外设或网络状态

优先把这些步骤写入 `config.json` 的 `repro` 段，由 `tools/Invoke-ReproScenario.ps1` 输出标准化复现说明。
如果暂时无法做真实 GUI 自动化，也要保留“启动程序 + 人工交互步骤 + 控制台日志 + 追溯记录”的闭环。

当 `repro.mode=ui-automation` 时，继续调用 `tools/Invoke-UiAutomationScenario.ps1` 执行动作序列。
当前建议优先使用以下动作类型：

- `wait`
- `activate_window`
- `send_keys`
- `send_text`
- `click_position`
- `click_control`
- `set_text_control`
- `invoke_control`

控件级动作优先使用：

- `windowTitlePattern`
- `controlName`
- `automationId`
- `controlType`

其中 `controlType` 可使用常见值，如：

- `Button`
- `Edit`
- `ComboBox`
- `CheckBox`
- `RadioButton`
- `TabItem`

### 7. 报告输出

闭环结束后生成：

- `build-report.md`
- `build-report.json`
- `qm-manifest.json`
- `runtime.log`
- `runtime-analysis.json`
- `repro-summary.json`
- 每轮日志
- 每轮修复记录

## 追溯要求

每次准备修改文件时，在项目 `.sln` 同级目录下创建：

`_codex_trace/<yyyyMMdd-HHmmss>-<attempt>/`

目录内至少包含：

- `change-summary.md`
- `context.json`
- `before/`：修改前文件副本
- `after/`：修改后文件副本
- `logs/`

如果本轮没有实际改文件，也要写 `change-summary.md` 说明“仅分析，无代码修改”。

## 推荐调用方式

```powershell
pwsh -File .\tools\Invoke-VsQtBuildLoop.ps1 `
  -ConfigPath .\config.json `
  -ProjectPath D:\Work\Demo\Demo.sln
```

```powershell
pwsh -File .\tools\Invoke-VsQtBuildLoop.ps1 `
  -ConfigPath .\config.json `
  -ProjectPath D:\Work\Demo\Demo.pro
```

## 约束

- 不要超过 3 次自动修复重试。
- 不要自动安装 VS、Qt、SDK 或修改系统级注册表。
- 不要在无法确认依赖的情况下胡乱增删库。
- 如果连续 2 轮修复方向不确定，优先加日志和更细粒度报告，不靠猜。
- 对 Qt GUI 程序也要执行“自动运行 + 抓控制台日志”，即使日志为空也要记录为空结果。
- UI 问题必须尽量把“用户提的问题 -> 对应代码位置 -> 日志点 -> 复现步骤”串起来。

