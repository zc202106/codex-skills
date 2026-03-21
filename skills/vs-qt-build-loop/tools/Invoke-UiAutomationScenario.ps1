[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = '',

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$ProcessId = 0,

    [ValidateSet('auto', 'uiAutomation', 'steps')]
    [string]$ActionSource = 'auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CodexUser32 {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath
$repro = $config.repro

function Test-IsAutomationActionType {
    param(
        [string]$ActionType
    )

    return @(
        'wait',
        'wait_window',
        'launch',
        'activate_window',
        'send_keys',
        'send_text',
        'click_position',
        'click_control',
        'set_text_control',
        'invoke_control',
        'close_window'
    ) -contains $ActionType
}

function New-DisabledResult {
    param(
        [string]$Note,
        [string]$ResolvedActionSource = 'none'
    )

    $result = [pscustomobject]@{
        Enabled = $false
        Executed = $false
        ProcessId = $ProcessId
        ActionSource = $ResolvedActionSource
        Success = $false
        Actions = @()
        Note = $Note
    }
    Save-JsonFile -Path $OutputPath -InputObject $result
    return $result
}

if (-not $repro.enabled) {
    return New-DisabledResult -Note '未启用复现场景。'
}

if ($repro.mode -ne 'ui-automation') {
    return New-DisabledResult -Note "当前模式不是 ui-automation: $($repro.mode)"
}

$stepActions = @($repro.steps | Where-Object {
    $stepType = [string](Get-OptionalPropertyValue -InputObject $_ -Name 'type' -DefaultValue '')
    Test-IsAutomationActionType -ActionType $stepType
})
$uiAutomationActions = @(@($repro.uiAutomation.actions) | Where-Object { $null -ne $_ })
$resolvedActionSource = switch ($ActionSource) {
    'steps' { 'steps' }
    'uiAutomation' { 'uiAutomation' }
    default {
        if ($uiAutomationActions.Count -gt 0) {
            'uiAutomation'
        } elseif ($stepActions.Count -gt 0) {
            'steps'
        } else {
            'uiAutomation'
        }
    }
}

$actions = @(if ($resolvedActionSource -eq 'steps') {
    $stepActions
} else {
    $uiAutomationActions
})

if ($actions.Count -eq 0) {
    return New-DisabledResult -Note '未配置可执行的自动化动作。' -ResolvedActionSource $resolvedActionSource
}

if ($ProcessId -le 0) {
    return New-DisabledResult -Note '缺少有效的 ProcessId，无法附着到目标程序。' -ResolvedActionSource $resolvedActionSource
}

$shell = New-Object -ComObject WScript.Shell
$defaultWindowTitlePattern = [string](Get-OptionalPropertyValue -InputObject $repro.uiAutomation -Name 'windowTitlePattern' -DefaultValue '')
$defaultFindTimeoutSeconds = [int](Get-OptionalPropertyValue -InputObject $repro.uiAutomation -Name 'windowFindTimeoutSeconds' -DefaultValue 5)
$postLaunchDelaySeconds = [int](Get-OptionalPropertyValue -InputObject $repro.uiAutomation -Name 'postLaunchDelaySeconds' -DefaultValue 0)
$actionsResult = @()
$stoppedOnFailure = $false

function Get-ActionWindowTitlePattern {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Action
    )

    $pattern = [string](Get-OptionalPropertyValue -InputObject $Action -Name 'windowTitlePattern' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($pattern)) {
        return $pattern
    }

    return $defaultWindowTitlePattern
}

function Get-ActionTimeoutSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Action
    )

    return [int](Get-OptionalPropertyValue -InputObject $Action -Name 'timeoutSeconds' -DefaultValue $defaultFindTimeoutSeconds)
}

function Find-WindowElement {
    param(
        [string]$WindowTitlePattern,
        [int]$TimeoutSeconds = 5
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition
        )

        foreach ($window in $windows) {
            if ($ProcessId -gt 0 -and $window.Current.ProcessId -ne $ProcessId) {
                continue
            }

            $name = $window.Current.Name
            if ([string]::IsNullOrWhiteSpace($WindowTitlePattern)) {
                return $window
            }

            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -match $WindowTitlePattern) {
                return $window
            }
        }

        Start-Sleep -Milliseconds 300
    }

    return $null
}

function Invoke-WindowActivate {
    param(
        [string]$WindowTitlePattern,
        [int]$TimeoutSeconds = 5
    )

    function Test-WindowIsForeground {
        param(
            [Parameter(Mandatory = $true)]
            [System.Windows.Automation.AutomationElement]$WindowElement
        )

        $foregroundWindowHandle = [CodexUser32]::GetForegroundWindow()
        if ($foregroundWindowHandle -eq [IntPtr]::Zero) {
            return $false
        }

        $foregroundProcessId = 0
        [void][CodexUser32]::GetWindowThreadProcessId($foregroundWindowHandle, [ref]$foregroundProcessId)
        if ($foregroundProcessId -ne $WindowElement.Current.ProcessId) {
            return $false
        }

        return $true
    }

    $window = Find-WindowElement -WindowTitlePattern $WindowTitlePattern -TimeoutSeconds $TimeoutSeconds
    if ($null -eq $window) {
        return $false
    }

    try {
        $pattern = $null
        if ($window.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.WindowPattern]$pattern).SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
        }
        $window.SetFocus()
    } catch {
        Write-Log -Level WARN -Message "窗口聚焦失败，尝试回退到 AppActivate: $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds 200
    if (Test-WindowIsForeground -WindowElement $window) {
        return $true
    }

    $appActivateTarget = if (-not [string]::IsNullOrWhiteSpace($WindowTitlePattern)) {
        $WindowTitlePattern
    } else {
        $ProcessId
    }
    if ($shell.AppActivate($appActivateTarget)) {
        Start-Sleep -Milliseconds 200
        $window = Find-WindowElement -WindowTitlePattern $WindowTitlePattern -TimeoutSeconds 1
        if ($null -ne $window -and (Test-WindowIsForeground -WindowElement $window)) {
            return $true
        }
    }

    Write-Log -Level WARN -Message "窗口激活失败: pattern='$WindowTitlePattern', processId=$ProcessId"
    return $false
}

function Invoke-MouseClick {
    param(
        [int]$X,
        [int]$Y
    )

    [CodexUser32]::SetCursorPos($X, $Y) | Out-Null
    [CodexUser32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [CodexUser32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Get-ControlTypeObject {
    param(
        [string]$ControlTypeName
    )

    if ([string]::IsNullOrWhiteSpace($ControlTypeName)) {
        return $null
    }

    $fieldName = '{0}ControlType' -f $ControlTypeName
    $field = [System.Windows.Automation.ControlType].GetField($fieldName, [System.Reflection.BindingFlags]'Public,Static,IgnoreCase')
    if ($null -eq $field) {
        return $null
    }

    return $field.GetValue($null)
}

function Find-ControlElement {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$WindowElement,

        [string]$ControlName,
        [string]$AutomationId,
        [string]$ControlType
    )

    $conditions = @()
    if (-not [string]::IsNullOrWhiteSpace($ControlName)) {
        $conditions += New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            $ControlName
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $conditions += New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $AutomationId
        )
    }
    $controlTypeObject = Get-ControlTypeObject -ControlTypeName $ControlType
    if ($null -ne $controlTypeObject) {
        $conditions += New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            $controlTypeObject
        )
    }

    $condition = if ($conditions.Count -eq 0) {
        [System.Windows.Automation.Condition]::TrueCondition
    } elseif ($conditions.Count -eq 1) {
        $conditions[0]
    } else {
        New-Object System.Windows.Automation.AndCondition($conditions)
    }

    return $WindowElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Get-AutomationElementSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element,

        [int]$Depth = 0,

        [int]$MaxDepth = 3
    )

    $left = $Element.Current.BoundingRectangle.Left
    $top = $Element.Current.BoundingRectangle.Top
    $width = $Element.Current.BoundingRectangle.Width
    $height = $Element.Current.BoundingRectangle.Height

    $snapshot = [ordered]@{
        name = $Element.Current.Name
        automationId = $Element.Current.AutomationId
        className = $Element.Current.ClassName
        controlType = if ($null -ne $Element.Current.ControlType) { $Element.Current.ControlType.ProgrammaticName } else { '' }
        frameworkId = $Element.Current.FrameworkId
        isEnabled = $Element.Current.IsEnabled
        processId = $Element.Current.ProcessId
        boundingRectangle = [ordered]@{
            left = if ([double]::IsInfinity($left) -or [double]::IsNaN($left)) { $null } else { [math]::Round($left, 2) }
            top = if ([double]::IsInfinity($top) -or [double]::IsNaN($top)) { $null } else { [math]::Round($top, 2) }
            width = if ([double]::IsInfinity($width) -or [double]::IsNaN($width)) { $null } else { [math]::Round($width, 2) }
            height = if ([double]::IsInfinity($height) -or [double]::IsNaN($height)) { $null } else { [math]::Round($height, 2) }
        }
        children = @()
    }

    if ($Depth -ge $MaxDepth) {
        return [pscustomobject]$snapshot
    }

    $children = $Element.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
    )

    $childSnapshots = @()
    foreach ($child in $children) {
        $childSnapshots += Get-AutomationElementSnapshot -Element $child -Depth ($Depth + 1) -MaxDepth $MaxDepth
    }
    $snapshot.children = $childSnapshots

    return [pscustomobject]$snapshot
}

function Save-WindowSnapshot {
    param(
        [System.Windows.Automation.AutomationElement]$WindowElement
    )

    if ($null -eq $WindowElement) {
        return $null
    }

    $snapshotPath = '{0}.window-tree.json' -f $OutputPath
    $snapshot = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        processId = $ProcessId
        actionSource = $resolvedActionSource
        window = Get-AutomationElementSnapshot -Element $WindowElement -Depth 0 -MaxDepth 3
    }
    Save-JsonFile -Path $snapshotPath -InputObject $snapshot
    return $snapshotPath
}

function Invoke-ControlClick {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element
    )

    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
        return 'invoke-pattern'
    }

    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.SelectionItemPattern]$pattern).Select()
        return 'selection-item-pattern'
    }

    $rect = $Element.Current.BoundingRectangle
    if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
        $x = [int]($rect.Left + ($rect.Width / 2))
        $y = [int]($rect.Top + ($rect.Height / 2))
        Invoke-MouseClick -X $x -Y $y
        return "mouse-click ($x,$y)"
    }

    return $null
}

function Invoke-ControlSetText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.ValuePattern]$pattern).SetValue($Text)
        return 'value-pattern'
    }

    $Element.SetFocus()
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    return 'sendkeys'
}

function Invoke-WindowClose {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$WindowElement
    )

    $pattern = $null
    if ($WindowElement.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) {
        ([System.Windows.Automation.WindowPattern]$pattern).Close()
        return 'window-pattern'
    }

    $WindowElement.SetFocus()
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait('%{F4}')
    return 'alt-f4'
}

function Invoke-ClickOrInvokeControl {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Action,

        [Parameter(Mandatory = $true)]
        [string]$DetailPrefix
    )

    $pattern = Get-ActionWindowTitlePattern -Action $Action
    $window = Find-WindowElement -WindowTitlePattern $pattern -TimeoutSeconds (Get-ActionTimeoutSeconds -Action $Action)
    if ($null -eq $window) {
        return @{ success = $false; detail = "未找到窗口: $pattern" }
    }

    $element = Find-ControlElement `
        -WindowElement $window `
        -ControlName (Get-OptionalPropertyValue -InputObject $Action -Name 'controlName' -DefaultValue '') `
        -AutomationId (Get-OptionalPropertyValue -InputObject $Action -Name 'automationId' -DefaultValue '') `
        -ControlType (Get-OptionalPropertyValue -InputObject $Action -Name 'controlType' -DefaultValue '')
    if ($null -eq $element) {
        return @{ success = $false; detail = '未找到目标控件' }
    }

    $method = Invoke-ControlClick -Element $element
    return @{
        success = -not [string]::IsNullOrWhiteSpace($method)
        detail  = "${DetailPrefix}: $method"
    }
}

Start-Sleep -Seconds $postLaunchDelaySeconds

$initialWindow = Find-WindowElement -WindowTitlePattern $defaultWindowTitlePattern -TimeoutSeconds $defaultFindTimeoutSeconds
$windowSnapshotPath = Save-WindowSnapshot -WindowElement $initialWindow

for ($index = 0; $index -lt $actions.Count; $index++) {
    $action = $actions[$index]
    $isEnabled = [bool](Get-OptionalPropertyValue -InputObject $action -Name 'enabled' -DefaultValue $true)
    if (-not $isEnabled) {
        continue
    }

    $actionType = [string](Get-OptionalPropertyValue -InputObject $action -Name 'type' -DefaultValue '')
    $actionResult = [ordered]@{
        index = $index + 1
        type = $actionType
        description = [string](Get-OptionalPropertyValue -InputObject $action -Name 'description' -DefaultValue '')
        success = $true
        detail = ''
        startedAt = (Get-Date).ToString('s')
    }

    switch ($actionType) {
        'launch' {
            $actionResult.detail = '进程已由运行脚本启动，跳过 launch。'
        }
        'wait' {
            $seconds = [int](Get-OptionalPropertyValue -InputObject $action -Name 'seconds' -DefaultValue 1)
            Start-Sleep -Seconds $seconds
            $actionResult.detail = "等待 $seconds 秒"
        }
        'wait_window' {
            $pattern = Get-ActionWindowTitlePattern -Action $action
            $window = Find-WindowElement -WindowTitlePattern $pattern -TimeoutSeconds (Get-ActionTimeoutSeconds -Action $action)
            $actionResult.success = $null -ne $window
            $actionResult.detail = if ($actionResult.success) { "窗口已出现: $pattern" } else { "等待窗口超时: $pattern" }
        }
        'activate_window' {
            $pattern = Get-ActionWindowTitlePattern -Action $action
            $ok = Invoke-WindowActivate -WindowTitlePattern $pattern -TimeoutSeconds (Get-ActionTimeoutSeconds -Action $action)
            $actionResult.success = [bool]$ok
            $actionResult.detail = "激活窗口: $pattern"
        }
        'send_keys' {
            $keys = [string](Get-OptionalPropertyValue -InputObject $action -Name 'keys' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($keys)) {
                $shell.SendKeys($keys)
                $actionResult.detail = "发送按键: $keys"
            } else {
                $actionResult.success = $false
                $actionResult.detail = '缺少 keys'
            }
        }
        'send_text' {
            $text = [string](Get-OptionalPropertyValue -InputObject $action -Name 'text' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $shell.SendKeys($text)
                $actionResult.detail = "发送文本: $text"
            } else {
                $actionResult.success = $false
                $actionResult.detail = '缺少 text'
            }
        }
        'click_position' {
            $x = Get-OptionalPropertyValue -InputObject $action -Name 'x' -DefaultValue $null
            $y = Get-OptionalPropertyValue -InputObject $action -Name 'y' -DefaultValue $null
            if ($null -ne $x -and $null -ne $y) {
                Invoke-MouseClick -X ([int]$x) -Y ([int]$y)
                $actionResult.detail = "点击坐标: ($x, $y)"
            } else {
                $actionResult.success = $false
                $actionResult.detail = '缺少 x/y'
            }
        }
        'click_control' {
            $r = Invoke-ClickOrInvokeControl -Action $action -DetailPrefix '点击控件'
            $actionResult.success = $r.success
            $actionResult.detail = $r.detail
        }
        'set_text_control' {
            $pattern = Get-ActionWindowTitlePattern -Action $action
            $window = Find-WindowElement -WindowTitlePattern $pattern -TimeoutSeconds (Get-ActionTimeoutSeconds -Action $action)
            if ($null -eq $window) {
                $actionResult.success = $false
                $actionResult.detail = "未找到窗口: $pattern"
            } else {
                $element = Find-ControlElement `
                    -WindowElement $window `
                    -ControlName (Get-OptionalPropertyValue -InputObject $action -Name 'controlName' -DefaultValue '') `
                    -AutomationId (Get-OptionalPropertyValue -InputObject $action -Name 'automationId' -DefaultValue '') `
                    -ControlType (Get-OptionalPropertyValue -InputObject $action -Name 'controlType' -DefaultValue '')
                $text = [string](Get-OptionalPropertyValue -InputObject $action -Name 'text' -DefaultValue '')
                if ($null -eq $element) {
                    $actionResult.success = $false
                    $actionResult.detail = '未找到目标控件'
                } elseif ([string]::IsNullOrWhiteSpace($text)) {
                    $actionResult.success = $false
                    $actionResult.detail = '缺少 text'
                } else {
                    $method = Invoke-ControlSetText -Element $element -Text $text
                    $actionResult.detail = "设置控件文本: $method"
                }
            }
        }
        'invoke_control' {
            $r = Invoke-ClickOrInvokeControl -Action $action -DetailPrefix '触发控件'
            $actionResult.success = $r.success
            $actionResult.detail = $r.detail
        }
        'close_window' {
            $pattern = Get-ActionWindowTitlePattern -Action $action
            $window = Find-WindowElement -WindowTitlePattern $pattern -TimeoutSeconds (Get-ActionTimeoutSeconds -Action $action)
            if ($null -eq $window) {
                $actionResult.success = $false
                $actionResult.detail = "未找到窗口: $pattern"
            } else {
                $method = Invoke-WindowClose -WindowElement $window
                $actionResult.detail = "关闭窗口: $method"
            }
        }
        default {
            $actionResult.success = $false
            $actionResult.detail = "不支持的动作类型: $actionType"
        }
    }

    $actionResult.completedAt = (Get-Date).ToString('s')
    $actionsResult += [pscustomobject]$actionResult

    $continueOnError = [bool](Get-OptionalPropertyValue -InputObject $action -Name 'continueOnError' -DefaultValue $true)
    if (-not $actionResult.success -and -not $continueOnError) {
        $stoppedOnFailure = $true
        break
    }
}

$result = [pscustomobject]@{
    Enabled = $true
    Executed = $true
    ProcessId = $ProcessId
    ActionSource = $resolvedActionSource
    Success = @($actionsResult | Where-Object { -not $_.success }).Count -eq 0
    StoppedOnFailure = $stoppedOnFailure
    WindowSnapshotPath = $windowSnapshotPath
    Actions = $actionsResult
}

Save-JsonFile -Path $OutputPath -InputObject $result
$result
