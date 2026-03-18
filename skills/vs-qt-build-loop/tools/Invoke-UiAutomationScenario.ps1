[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$ProcessId = 0
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
}
"@

$config = Read-Config -ConfigPath $ConfigPath
$repro = $config.repro

if (-not $repro.enabled -or $repro.mode -ne 'ui-automation') {
    $result = [pscustomobject]@{
        Enabled = $false
        Executed = $false
        Actions = @()
        Note = '当前未启用真实 GUI 自动化。'
    }
    Save-JsonFile -Path $OutputPath -InputObject $result
    return $result
}

$shell = New-Object -ComObject WScript.Shell
$actionsResult = @()

function Invoke-WindowActivate {
    param(
        [string]$WindowTitlePattern
    )

    if ([string]::IsNullOrWhiteSpace($WindowTitlePattern)) {
        return $false
    }

    return $shell.AppActivate($WindowTitlePattern)
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
            $name = $window.Current.Name
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -match $WindowTitlePattern) {
                return $window
            }
        }

        Start-Sleep -Milliseconds 300
    }

    return $null
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

Start-Sleep -Seconds ([int]$repro.uiAutomation.postLaunchDelaySeconds)

foreach ($action in $repro.uiAutomation.actions) {
    if (($action.PSObject.Properties.Name -contains 'enabled') -and (-not [bool]$action.enabled)) {
        continue
    }

    $actionType = $action.type
    $actionResult = [ordered]@{
        type = $actionType
        success = $true
        detail = ''
    }

    switch ($actionType) {
        'wait' {
            $seconds = if ($action.PSObject.Properties.Name -contains 'seconds') { [int]$action.seconds } else { 1 }
            Start-Sleep -Seconds $seconds
            $actionResult.detail = "等待 $seconds 秒"
        }
        'activate_window' {
            $pattern = $action.windowTitlePattern
            $ok = Invoke-WindowActivate -WindowTitlePattern $pattern
            $actionResult.success = [bool]$ok
            $actionResult.detail = "激活窗口: $pattern"
        }
        'send_keys' {
            $keys = $action.keys
            if (-not [string]::IsNullOrWhiteSpace($keys)) {
                $shell.SendKeys($keys)
                $actionResult.detail = "发送按键: $keys"
            } else {
                $actionResult.success = $false
                $actionResult.detail = '缺少 keys'
            }
        }
        'send_text' {
            $text = $action.text
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $shell.SendKeys($text)
                $actionResult.detail = "发送文本: $text"
            } else {
                $actionResult.success = $false
                $actionResult.detail = '缺少 text'
            }
        }
        'click_position' {
            if (($action.PSObject.Properties.Name -contains 'x') -and ($action.PSObject.Properties.Name -contains 'y')) {
                Invoke-MouseClick -X ([int]$action.x) -Y ([int]$action.y)
                $actionResult.detail = "点击坐标: ($($action.x), $($action.y))"
            } else {
                $actionResult.success = $false
                $actionResult.detail = '缺少 x/y'
            }
        }
        'click_control' {
            $window = Find-WindowElement -WindowTitlePattern $action.windowTitlePattern
            if ($null -eq $window) {
                $actionResult.success = $false
                $actionResult.detail = "未找到窗口: $($action.windowTitlePattern)"
            } else {
                $element = Find-ControlElement `
                    -WindowElement $window `
                    -ControlName $action.controlName `
                    -AutomationId $action.automationId `
                    -ControlType $action.controlType
                if ($null -eq $element) {
                    $actionResult.success = $false
                    $actionResult.detail = '未找到目标控件'
                } else {
                    $method = Invoke-ControlClick -Element $element
                    $actionResult.success = -not [string]::IsNullOrWhiteSpace($method)
                    $actionResult.detail = "点击控件: $method"
                }
            }
        }
        'set_text_control' {
            $window = Find-WindowElement -WindowTitlePattern $action.windowTitlePattern
            if ($null -eq $window) {
                $actionResult.success = $false
                $actionResult.detail = "未找到窗口: $($action.windowTitlePattern)"
            } else {
                $element = Find-ControlElement `
                    -WindowElement $window `
                    -ControlName $action.controlName `
                    -AutomationId $action.automationId `
                    -ControlType $action.controlType
                if ($null -eq $element) {
                    $actionResult.success = $false
                    $actionResult.detail = '未找到目标控件'
                } elseif ($action.PSObject.Properties.Name -notcontains 'text') {
                    $actionResult.success = $false
                    $actionResult.detail = '缺少 text'
                } else {
                    $method = Invoke-ControlSetText -Element $element -Text $action.text
                    $actionResult.detail = "设置控件文本: $method"
                }
            }
        }
        'invoke_control' {
            $window = Find-WindowElement -WindowTitlePattern $action.windowTitlePattern
            if ($null -eq $window) {
                $actionResult.success = $false
                $actionResult.detail = "未找到窗口: $($action.windowTitlePattern)"
            } else {
                $element = Find-ControlElement `
                    -WindowElement $window `
                    -ControlName $action.controlName `
                    -AutomationId $action.automationId `
                    -ControlType $action.controlType
                if ($null -eq $element) {
                    $actionResult.success = $false
                    $actionResult.detail = '未找到目标控件'
                } else {
                    $method = Invoke-ControlClick -Element $element
                    $actionResult.success = -not [string]::IsNullOrWhiteSpace($method)
                    $actionResult.detail = "触发控件: $method"
                }
            }
        }
        default {
            $actionResult.success = $false
            $actionResult.detail = "不支持的动作类型: $actionType"
        }
    }

    $actionsResult += [pscustomobject]$actionResult
}

$result = [pscustomobject]@{
    Enabled = $true
    Executed = $true
    ProcessId = $ProcessId
    Actions = $actionsResult
}

Save-JsonFile -Path $OutputPath -InputObject $result
$result
