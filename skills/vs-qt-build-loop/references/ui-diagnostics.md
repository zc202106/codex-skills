# UI 诊断与复现

## 适用内容

需要以下细节时再读取本文件：

- 如何根据用户描述定位 UI 代码
- 诊断日志优先加在哪
- GUI 自动化如何设计动作

## UI 诊断日志原则

优先在以下位置加日志：

- 用户操作入口
- 信号/槽触发点
- 关键状态变量变化
- 条件分支
- UI 刷新和数据回写结果
- 线程回调和异步返回

日志应尽量使用统一前缀，例如：

- `[CODEX_UI]`

## 候选文件定位

先调用：

- `tools/Add-DiagnosticLogs.ps1`

它会根据：

- `uiDiagnostics.keywordRules`

给出候选文件与诊断建议。

## 复现步骤设计

用户提 UI bug 时，尽量整理成：

1. 从哪个窗口进入
2. 点击/输入/切换顺序
3. 期望结果
4. 实际结果
5. 是否依赖登录态、语言、配置、外设、网络

## GUI 自动化优先级

优先使用控件级动作：

- `click_control`
- `set_text_control`
- `invoke_control`

定位优先字段：

- `windowTitlePattern`
- `controlName`
- `automationId`
- `controlType`

控件定位不稳定时，再退回：

- `send_keys`
- `click_position`
