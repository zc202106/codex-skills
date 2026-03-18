# vs-qt-build-loop

## 适用场景

适用于 Windows 10/11 下基于 VS2017 + Qt 5.11.0 的 `.sln` / `.vcxproj` / `.pro` 工程自动化闭环。

目标流程包括：

1. 用户提出问题
2. 根据问题定位 UI 或业务逻辑代码
3. 在对应位置补诊断日志
4. 自动编译
5. 编译成功后自动运行程序
6. 按配置执行 GUI 复现步骤
7. 抓取控制台日志
8. 根据日志继续修复

## 当前能力

- 自动激活 `vcvarsall.bat` 与 Qt 工具链
- 自动选择 `MSBuild` 或 `qmake + jom`
- 自动更新 `.ts` 并生成 `.qm`
- 同步翻译文件到源码目录和 exe 运行目录
- 编译失败时按规则分析与重试
- 编译成功后自动运行程序并抓取控制台日志
- 记录运行期分析结果
- 在 `.sln` 同级生成 `_codex_trace` 追溯目录
- 支持 UI 逻辑问题的诊断日志建议
- 支持 GUI 复现步骤定义
- 支持基础 GUI 自动化动作
- 支持控件级自动化动作：
  - 按窗口标题定位窗口
  - 按控件文本定位控件
  - 按 `AutomationId` 定位控件
  - 按 `controlType` 过滤控件

## 当前仓库适配情况

当前默认配置已适配：

- `D:\Video\150\GroundNode\PoseidonCore.sln`
- `D:\Video\150\GroundNode\Ruiyan_UAV`

翻译文件默认同步到：

- `D:\Video\150\GroundNode\Ruiyan_UAV`
- `D:\Video\150\GroundNode\x64\Release\Ruiyan_UAV`

追溯目录默认生成在：

- `D:\Video\150\GroundNode\_codex_trace`

## 关键目录

```text
skills/vs-qt-build-loop/
├─ SKILL.md
├─ config.json
└─ tools/
   ├─ Common.ps1
   ├─ Initialize-BuildEnvironment.ps1
   ├─ Resolve-BuildTarget.ps1
   ├─ New-TraceRecord.ps1
   ├─ Update-QtTranslations.ps1
   ├─ Analyze-BuildError.ps1
   ├─ Start-ProgramWithLogs.ps1
   ├─ Analyze-RuntimeLog.ps1
   ├─ Add-DiagnosticLogs.ps1
   ├─ Invoke-ReproScenario.ps1
   ├─ Invoke-UiAutomationScenario.ps1
   └─ Invoke-VsQtBuildLoop.ps1
```

## 接入步骤

### 1. 准备 Skill 配置

编辑：

```text
skills/vs-qt-build-loop/config.json
```

至少确认这些节点：

- `environment`
- `project`
- `translations`
- `runtime`
- `repro`
- `uiDiagnostics`

### 2. 绑定实际工程路径

至少确认以下字段已经指向真实工程：

- `project.projectPath`
- `project.solutionPath`
- `project.proPath`
- `project.outputDirectory`
- `runtime.executablePath`
- `runtime.workingDirectory`

### 3. 配置翻译同步目录

默认应至少包含两个同步目标：

- 源码目录中的翻译目录
- exe 运行目录

对应字段：

- `translations.qmOutputDirectory`
- `translations.copyTargets`

### 4. 配置运行期闭环

根据程序行为调整：

- `runtime.startupTimeoutSeconds`
- `runtime.captureDurationSeconds`
- `runtime.stopAfterCapture`
- `runtime.treatAliveAfterCaptureAsSuccess`

如果程序长时间驻留、而你只是想观察启动后的控制台输出，推荐保留：

- `stopAfterCapture=true`
- `treatAliveAfterCaptureAsSuccess=true`

### 5. 配置 UI 复现步骤

如果你要处理 UI 逻辑 bug，优先填写：

- `repro.mode`
- `repro.steps`
- `repro.uiAutomation.actions`

如果暂时无法稳定自动化，先使用：

- `repro.mode = manual-assisted`

如果要启用 GUI 自动化，改成：

- `repro.mode = ui-automation`

### 6. 配置 UI 诊断日志建议

如果你经常处理固定模块的 UI 问题，可以在这里维护关键词到文件的映射：

- `uiDiagnostics.keywordRules`

## GUI 自动化动作

### 基础动作

- `wait`
- `activate_window`
- `send_keys`
- `send_text`
- `click_position`

### 控件级动作

- `click_control`
- `set_text_control`
- `invoke_control`

控件定位优先使用：

- `windowTitlePattern`
- `controlName`
- `automationId`
- `controlType`

`controlType` 常见值：

- `Button`
- `Edit`
- `ComboBox`
- `CheckBox`
- `RadioButton`
- `TabItem`

## 推荐执行方式

推荐直接执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills\vs-qt-build-loop\tools\Invoke-VsQtBuildLoop.ps1 -ConfigPath .\skills\vs-qt-build-loop\config.json -ProjectPath D:\Video\150\GroundNode\PoseidonCore.sln
```

如果只想单独调某个阶段，也可以分别执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills\vs-qt-build-loop\tools\Update-QtTranslations.ps1 -ConfigPath .\skills\vs-qt-build-loop\config.json -ProjectRoot D:\Video\150\GroundNode -OutputDirectory D:\Video\150\GroundNode\x64\Release\Ruiyan_UAV
pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills\vs-qt-build-loop\tools\Add-DiagnosticLogs.ps1 -ConfigPath .\skills\vs-qt-build-loop\config.json -IssueText "主界面切换语言后按钮状态没有刷新"
pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills\vs-qt-build-loop\tools\Invoke-ReproScenario.ps1 -ConfigPath .\skills\vs-qt-build-loop\config.json -OutputPath .\repro-summary.json
```

## 使用建议

- 提 UI bug 时，尽量描述“入口界面 + 操作步骤 + 期望结果 + 实际结果”
- 如果问题不稳定，优先让我先加日志再跑闭环
- GUI 自动化优先使用控件级动作：
  - `click_control`
  - `set_text_control`
  - `invoke_control`
- 如果控件树不稳定，再退回：
  - `send_keys`
  - `click_position`

## 当前边界

当前已支持：

- 自动编译
- 自动运行
- 控制台日志抓取
- 翻译同步
- 追溯记录
- UI 诊断日志建议
- GUI 自动化基础动作
- GUI 自动化控件级动作

当前仍建议人工辅助的部分：

- 特殊弹窗处理
- 多显示器/分辨率差异下的坐标策略
- 极复杂自绘控件的精准交互
