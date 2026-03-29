Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

function Get-FilePath {
    param (
        [string]$ScriptRoot,
        [string]$FileName
    )

    Join-Path $ScriptRoot $FileName
}

function Ensure-StateFile {
    param (
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        '{ "days": {} }' | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

function Read-JsonObject {
    param (
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    $raw | ConvertFrom-Json
}

function Get-DayKey {
    param (
        [datetime]$Date
    )

    $Date.ToString("dddd").ToLowerInvariant()
}

function Get-TasksFromCalendarCache {
    param (
        [psobject]$CalendarCache
    )

    $today = Get-Date
    $dateKey = $today.ToString("yyyy-MM-dd")
    $tasks = @()

    if ($null -ne $CalendarCache -and $CalendarCache.status -ne "error" -and $null -ne $CalendarCache.events) {
        foreach ($event in @($CalendarCache.events)) {
            $tasks += Format-CalendarEntry -Event $event
        }
    }

    [PSCustomObject]@{
        DateKey   = $dateKey
        DateLabel = $today.ToString("dddd d. MMMM", [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO"))
        Tasks     = $tasks
        Title     = "Dette star pa kalenderen i dag"
    }
}

function Get-CompletedIndexes {
    param (
        [string]$StateFile,
        [string]$DateKey
    )

    Ensure-StateFile -Path $StateFile
    $state = Read-JsonObject -Path $StateFile

    if ($null -eq $state -or $null -eq $state.days) {
        return @()
    }

    if ($state.days.PSObject.Properties.Name -contains $DateKey) {
        return @($state.days.$DateKey)
    }

    @()
}

function Save-CompletedIndexes {
    param (
        [string]$StateFile,
        [string]$DateKey,
        [int[]]$Indexes
    )

    Ensure-StateFile -Path $StateFile

    $stateTable = @{ days = @{} }
    $existing = Read-JsonObject -Path $StateFile

    if ($null -ne $existing -and $null -ne $existing.days) {
        foreach ($property in $existing.days.PSObject.Properties) {
            $stateTable.days[$property.Name] = @($property.Value)
        }
    }

    $stateTable.days[$DateKey] = @($Indexes | Sort-Object -Unique)

    $json = $stateTable | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $StateFile -Value $json -Encoding UTF8
}

function New-CardPanel {
    param (
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Color]$BackColor = [System.Drawing.Color]::White
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = $BackColor
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panel
}

function New-ShadowPanel {
    param (
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Color]$BackColor
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = $BackColor
    $panel
}

function New-RoundedGraphicsPath {
    param (
        [int]$Width,
        [int]$Height,
        [int]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [Math]::Max(2, $Radius * 2)

    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc($Width - $diameter, 0, $diameter, $diameter, 270, 90)
    $path.AddArc($Width - $diameter, $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc(0, $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $path
}

function Set-RoundedRegion {
    param (
        [System.Windows.Forms.Control]$Control,
        [int]$Radius
    )

    if ($Control.Width -le 0 -or $Control.Height -le 0) {
        return
    }

    $path = New-RoundedGraphicsPath -Width $Control.Width -Height $Control.Height -Radius $Radius
    $region = New-Object System.Drawing.Region($path)
    $path.Dispose()

    if ($null -ne $Control.Region) {
        $Control.Region.Dispose()
    }

    $Control.Region = $region
}

function Format-CalendarEntry {
    param (
        [psobject]$Event
    )

    if (-not $Event.start) {
        return $Event.summary
    }

    if ($Event.start.allDay) {
        return "Hele dagen - $($Event.summary)"
    }

    return "$($Event.start.label) - $($Event.summary)"
}

function Refresh-TaskList {
    param (
        [System.Windows.Forms.CheckedListBox]$TaskList,
        [System.Windows.Forms.Label]$ProgressLabel,
        [System.Windows.Forms.Label]$EmptyLabel,
        [string[]]$Tasks,
        [int[]]$CompletedIndexes
    )

    $TaskList.Items.Clear()

    if ($Tasks.Count -eq 0) {
        $TaskList.Visible = $false
        $EmptyLabel.Visible = $true
        $ProgressLabel.Text = "0 av 0 ferdig"
        return
    }

    $TaskList.Visible = $true
    $EmptyLabel.Visible = $false

    foreach ($task in $Tasks) {
        [void]$TaskList.Items.Add($task, $false)
    }

    foreach ($index in $CompletedIndexes) {
        if ($index -ge 0 -and $index -lt $TaskList.Items.Count) {
            $TaskList.SetItemChecked($index, $true)
        }
    }

    $doneCount = @($CompletedIndexes).Count
    $ProgressLabel.Text = "$doneCount av $($Tasks.Count) ferdig"
}

function Refresh-CalendarList {
    param (
        [System.Windows.Forms.ListBox]$CalendarList,
        [System.Windows.Forms.Label]$CalendarStatusLabel,
        [System.Windows.Forms.Label]$CalendarHintLabel,
        [psobject]$CalendarCache
    )

    $CalendarList.Items.Clear()

    if ($null -eq $CalendarCache) {
        $CalendarStatusLabel.Text = "Ingen synkdata ennå"
        $CalendarHintLabel.Text = "Kjor Sync Google Calendar etter at credentials.json er lagt inn."
        return
    }

    if ($CalendarCache.status -eq "error") {
        $CalendarStatusLabel.Text = "Synk feilet"
        $CalendarHintLabel.Text = [string]$CalendarCache.message
        return
    }

    $CalendarStatusLabel.Text = "Google Calendar"
    if ($CalendarCache.generatedAt) {
        $CalendarHintLabel.Text = "Sist oppdatert: $($CalendarCache.generatedAt)"
    }
    else {
        $CalendarHintLabel.Text = "Kalenderdata lastet"
    }

    $events = @()
    if ($null -ne $CalendarCache.events) {
        $events = @($CalendarCache.events)
    }

    if ($events.Count -eq 0) {
        [void]$CalendarList.Items.Add("Ingen kalenderhendelser i dag.")
        return
    }

    foreach ($event in $events) {
        [void]$CalendarList.Items.Add((Format-CalendarEntry -Event $event))
    }
}

function Invoke-CalendarSync {
    param (
        [string]$ScriptRoot,
        [string]$SyncScriptPath,
        [string]$CalendarCachePath
    )

    if (-not (Test-Path -LiteralPath $SyncScriptPath)) {
        return [PSCustomObject]@{
            Success = $false
            Output  = "Fant ikke sync-google-calendar.mjs."
            Cache   = Read-JsonObject -Path $CalendarCachePath
        }
    }

    $credentialsPath = Get-FilePath -ScriptRoot $ScriptRoot -FileName "credentials.json"
    $nodeModulesPath = Get-FilePath -ScriptRoot $ScriptRoot -FileName "node_modules"

    if (-not (Test-Path -LiteralPath $credentialsPath) -or -not (Test-Path -LiteralPath $nodeModulesPath)) {
        return [PSCustomObject]@{
            Success = $false
            Output  = "Google Calendar er ikke satt opp ennå."
            Cache   = Read-JsonObject -Path $CalendarCachePath
        }
    }

    $originalLocation = Get-Location

    try {
        Set-Location -LiteralPath $ScriptRoot
        $output = & node $SyncScriptPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location -LiteralPath $originalLocation.Path
    }

    [PSCustomObject]@{
        Success = ($exitCode -eq 0)
        Output  = ($output | Out-String).Trim()
        Cache   = Read-JsonObject -Path $CalendarCachePath
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateFile = Get-FilePath -ScriptRoot $scriptRoot -FileName "task-state.json"
$calendarCacheFile = Get-FilePath -ScriptRoot $scriptRoot -FileName "calendar-cache.json"
$syncScript = Get-FilePath -ScriptRoot $scriptRoot -FileName "sync-google-calendar.mjs"
$initialSyncResult = Invoke-CalendarSync -ScriptRoot $scriptRoot -SyncScriptPath $syncScript -CalendarCachePath $calendarCacheFile
$calendarCache = $initialSyncResult.Cache
$taskData = Get-TasksFromCalendarCache -CalendarCache $calendarCache
$completedIndexes = Get-CompletedIndexes -StateFile $stateFile -DateKey $taskData.DateKey

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$formWidth = 400
$formHeight = 690
$margin = 18
$pageBackground = [System.Drawing.Color]::FromArgb(247, 243, 236)
$panelBackground = [System.Drawing.Color]::FromArgb(255, 251, 245)
$textPrimary = [System.Drawing.Color]::FromArgb(59, 53, 45)
$textMuted = [System.Drawing.Color]::FromArgb(133, 122, 108)
$listBackground = [System.Drawing.Color]::FromArgb(251, 247, 241)
$buttonPrimary = [System.Drawing.Color]::FromArgb(221, 202, 178)
$buttonSecondary = [System.Drawing.Color]::FromArgb(238, 230, 219)
$buttonNeutral = [System.Drawing.Color]::FromArgb(244, 238, 230)
$buttonText = [System.Drawing.Color]::FromArgb(79, 70, 58)
$shadowColor = [System.Drawing.Color]::FromArgb(228, 220, 209)

$form = New-Object System.Windows.Forms.Form
$form.Text = $taskData.Title
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
$form.Location = New-Object System.Drawing.Point(($screen.Right - $formWidth - $margin), ($screen.Top + $margin))
$form.TopMost = $true
$form.BackColor = $pageBackground
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.MaximizeBox = $false
$form.MinimizeBox = $true

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "X"
$closeButton.Size = New-Object System.Drawing.Size(32, 28)
$closeButton.Location = New-Object System.Drawing.Point(348, 16)
$closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeButton.BackColor = $buttonNeutral
$closeButton.ForeColor = $buttonText
$closeButton.FlatAppearance.BorderSize = 0
$closeButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$form.Controls.Add($closeButton)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $taskData.Title
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 17)
$titleLabel.ForeColor = $textPrimary
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(22, 20)
$form.Controls.Add($titleLabel)

$dateLabel = New-Object System.Windows.Forms.Label
$dateLabel.Text = $taskData.DateLabel
$dateLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$dateLabel.ForeColor = $textMuted
$dateLabel.AutoSize = $true
$dateLabel.Location = New-Object System.Drawing.Point(24, 50)
$form.Controls.Add($dateLabel)

$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = ""
$progressLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$progressLabel.ForeColor = $textPrimary
$progressLabel.AutoSize = $true
$progressLabel.Location = New-Object System.Drawing.Point(24, 74)
$form.Controls.Add($progressLabel)

$taskPanelShadow = New-ShadowPanel -X 22 -Y 112 -Width 364 -Height 302 -BackColor $shadowColor
$form.Controls.Add($taskPanelShadow)

$taskPanel = New-CardPanel -X 18 -Y 108 -Width 364 -Height 302 -BackColor $panelBackground
$taskPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$form.Controls.Add($taskPanel)

$taskPanelTitle = New-Object System.Windows.Forms.Label
$taskPanelTitle.Text = "Todo fra kalender"
$taskPanelTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$taskPanelTitle.ForeColor = $textPrimary
$taskPanelTitle.AutoSize = $true
$taskPanelTitle.Location = New-Object System.Drawing.Point(16, 14)
$taskPanel.Controls.Add($taskPanelTitle)

$taskList = New-Object System.Windows.Forms.CheckedListBox
$taskList.Location = New-Object System.Drawing.Point(16, 46)
$taskList.Size = New-Object System.Drawing.Size(332, 236)
$taskList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$taskList.CheckOnClick = $true
$taskList.BackColor = $listBackground
$taskList.ForeColor = $textPrimary
$taskList.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$taskPanel.Controls.Add($taskList)

$emptyLabel = New-Object System.Windows.Forms.Label
$emptyLabel.Text = "Ingen kalenderhendelser funnet for i dag.`r`nTrykk Sync Google for aa hente dagens avtaler."
$emptyLabel.ForeColor = $textMuted
$emptyLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$emptyLabel.AutoSize = $true
$emptyLabel.Location = New-Object System.Drawing.Point(16, 54)
$emptyLabel.Visible = $false
$taskPanel.Controls.Add($emptyLabel)

$calendarPanelShadow = New-ShadowPanel -X 22 -Y 430 -Width 364 -Height 166 -BackColor $shadowColor
$form.Controls.Add($calendarPanelShadow)

$calendarPanel = New-CardPanel -X 18 -Y 426 -Width 364 -Height 166 -BackColor $panelBackground
$calendarPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$form.Controls.Add($calendarPanel)

$calendarPanelTitle = New-Object System.Windows.Forms.Label
$calendarPanelTitle.Text = "Dagens kalender"
$calendarPanelTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$calendarPanelTitle.ForeColor = $textPrimary
$calendarPanelTitle.AutoSize = $true
$calendarPanelTitle.Location = New-Object System.Drawing.Point(16, 14)
$calendarPanel.Controls.Add($calendarPanelTitle)

$calendarStatusLabel = New-Object System.Windows.Forms.Label
$calendarStatusLabel.Text = ""
$calendarStatusLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$calendarStatusLabel.ForeColor = $textPrimary
$calendarStatusLabel.AutoSize = $true
$calendarStatusLabel.Location = New-Object System.Drawing.Point(18, 42)
$calendarPanel.Controls.Add($calendarStatusLabel)

$calendarHintLabel = New-Object System.Windows.Forms.Label
$calendarHintLabel.Text = ""
$calendarHintLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$calendarHintLabel.ForeColor = $textMuted
$calendarHintLabel.AutoSize = $true
$calendarHintLabel.Location = New-Object System.Drawing.Point(18, 62)
$calendarPanel.Controls.Add($calendarHintLabel)

$calendarList = New-Object System.Windows.Forms.ListBox
$calendarList.Location = New-Object System.Drawing.Point(16, 88)
$calendarList.Size = New-Object System.Drawing.Size(332, 58)
$calendarList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$calendarList.BackColor = $listBackground
$calendarList.ForeColor = $textPrimary
$calendarList.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$calendarPanel.Controls.Add($calendarList)

$footerPanel = New-Object System.Windows.Forms.Panel
$footerPanel.Location = New-Object System.Drawing.Point(18, 610)
$footerPanel.Size = New-Object System.Drawing.Size(364, 40)
$footerPanel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($footerPanel)

$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = "Apne kalenderdata"
$openButton.Size = New-Object System.Drawing.Size(120, 30)
$openButton.Location = New-Object System.Drawing.Point(0, 4)
$openButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$openButton.BackColor = $buttonSecondary
$openButton.ForeColor = $buttonText
$openButton.FlatAppearance.BorderSize = 0
$openButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$footerPanel.Controls.Add($openButton)

$syncButton = New-Object System.Windows.Forms.Button
$syncButton.Text = "Sync Google"
$syncButton.Size = New-Object System.Drawing.Size(104, 30)
$syncButton.Location = New-Object System.Drawing.Point(132, 4)
$syncButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$syncButton.BackColor = $buttonPrimary
$syncButton.ForeColor = $buttonText
$syncButton.FlatAppearance.BorderSize = 0
$syncButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$footerPanel.Controls.Add($syncButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Last pa nytt"
$refreshButton.Size = New-Object System.Drawing.Size(104, 30)
$refreshButton.Location = New-Object System.Drawing.Point(248, 4)
$refreshButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$refreshButton.BackColor = $buttonNeutral
$refreshButton.ForeColor = $buttonText
$refreshButton.FlatAppearance.BorderSize = 0
$refreshButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$footerPanel.Controls.Add($refreshButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Todo-lista bygges fra kalenderen. Kryss av det som er gjort."
$statusLabel.ForeColor = $textMuted
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(22, 654)
$form.Controls.Add($statusLabel)

$closeButton.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    Set-RoundedRegion -Control $form -Radius 18
    Set-RoundedRegion -Control $closeButton -Radius 10
    Set-RoundedRegion -Control $taskPanelShadow -Radius 16
    Set-RoundedRegion -Control $taskPanel -Radius 16
    Set-RoundedRegion -Control $calendarPanelShadow -Radius 16
    Set-RoundedRegion -Control $calendarPanel -Radius 16
    Set-RoundedRegion -Control $taskList -Radius 12
    Set-RoundedRegion -Control $calendarList -Radius 12
    Set-RoundedRegion -Control $openButton -Radius 12
    Set-RoundedRegion -Control $syncButton -Radius 12
    Set-RoundedRegion -Control $refreshButton -Radius 12
})

$currentTasks = @($taskData.Tasks)
$currentDateKey = $taskData.DateKey

Refresh-TaskList -TaskList $taskList -ProgressLabel $progressLabel -EmptyLabel $emptyLabel -Tasks $currentTasks -CompletedIndexes $completedIndexes
Refresh-CalendarList -CalendarList $calendarList -CalendarStatusLabel $calendarStatusLabel -CalendarHintLabel $calendarHintLabel -CalendarCache $calendarCache

$taskList.Add_ItemCheck({
    param ($sender, $eventArgs)

    $checked = New-Object System.Collections.Generic.List[int]

    for ($i = 0; $i -lt $sender.Items.Count; $i++) {
        $isChecked = $sender.GetItemChecked($i)
        if ($i -eq $eventArgs.Index) {
            $isChecked = $eventArgs.NewValue -eq [System.Windows.Forms.CheckState]::Checked
        }

        if ($isChecked) {
            [void]$checked.Add($i)
        }
    }

    Save-CompletedIndexes -StateFile $stateFile -DateKey $currentDateKey -Indexes $checked.ToArray()
    $progressLabel.Text = "$($checked.Count) av $($sender.Items.Count) ferdig"
})

$openButton.Add_Click({
    Start-Process notepad.exe -ArgumentList "`"$calendarCacheFile`""
})

$syncButton.Add_Click({
    try {
        $syncResult = Invoke-CalendarSync -ScriptRoot $scriptRoot -SyncScriptPath $syncScript -CalendarCachePath $calendarCacheFile
        $calendarCache = $syncResult.Cache
        $latest = Get-TasksFromCalendarCache -CalendarCache $calendarCache
        $latestCompleted = Get-CompletedIndexes -StateFile $stateFile -DateKey $latest.DateKey
        $currentTasks = @($latest.Tasks)
        $currentDateKey = $latest.DateKey
        $form.Text = $latest.Title
        $titleLabel.Text = $latest.Title
        $dateLabel.Text = $latest.DateLabel

        Refresh-TaskList -TaskList $taskList -ProgressLabel $progressLabel -EmptyLabel $emptyLabel -Tasks $currentTasks -CompletedIndexes $latestCompleted
        Refresh-CalendarList -CalendarList $calendarList -CalendarStatusLabel $calendarStatusLabel -CalendarHintLabel $calendarHintLabel -CalendarCache $calendarCache

        if (-not $syncResult.Success) {
            [System.Windows.Forms.MessageBox]::Show($syncResult.Output, "Sync feilet", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }

        [System.Windows.Forms.MessageBox]::Show("Google Calendar er synket for i dag.", "Sync ferdig", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Sync feilet", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$refreshButton.Add_Click({
    $calendarCache = Read-JsonObject -Path $calendarCacheFile
    $latest = Get-TasksFromCalendarCache -CalendarCache $calendarCache
    $latestCompleted = Get-CompletedIndexes -StateFile $stateFile -DateKey $latest.DateKey

    $form.Text = $latest.Title
    $titleLabel.Text = $latest.Title
    $dateLabel.Text = $latest.DateLabel
    $currentTasks = @($latest.Tasks)
    $currentDateKey = $latest.DateKey

    Refresh-TaskList -TaskList $taskList -ProgressLabel $progressLabel -EmptyLabel $emptyLabel -Tasks $currentTasks -CompletedIndexes $latestCompleted
    Refresh-CalendarList -CalendarList $calendarList -CalendarStatusLabel $calendarStatusLabel -CalendarHintLabel $calendarHintLabel -CalendarCache $calendarCache
})

[void]$form.ShowDialog()
