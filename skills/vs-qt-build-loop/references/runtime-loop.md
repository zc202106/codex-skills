# 运行闭环

## 适用内容

需要以下细节时再读取本文件：

- 运行成功/失败如何判定
- 运行期日志如何抓
- 复现步骤和 GUI 自动化如何接入

## 主流程

构建成功后继续执行：

1. `tools/Invoke-ReproScenario.ps1`
2. `tools/Start-ProgramWithLogs.ps1`
3. `tools/Analyze-RuntimeLog.ps1`

如果：

- `repro.mode=ui-automation`

则 `Start-ProgramWithLogs.ps1` 会进一步调用：

- `tools/Invoke-UiAutomationScenario.ps1`

## 运行期判定

默认配置下：

- 程序启动并存活到观察窗口结束
- 按策略结束进程抓日志
- 视为运行成功

对应关键配置：

- `runtime.stopAfterCapture=true`
- `runtime.treatAliveAfterCaptureAsSuccess=true`

## 输出文件

- `runtime.log`
- `runtime-analysis.json`
- `repro-summary.json`
- `runtime.log.ui-automation.json`（启用 GUI 自动化时）

## 当前支持的 GUI 自动化动作

- `wait`
- `activate_window`
- `send_keys`
- `send_text`
- `click_position`
- `click_control`
- `set_text_control`
- `invoke_control`

## 当前边界

- 支持基础窗口与控件级操作
- 不保证复杂自绘控件一定能被标准 UIAutomation 识别
- 多显示器和特殊弹窗仍可能需要人工辅助
