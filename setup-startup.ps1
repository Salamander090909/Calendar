Add-Type -AssemblyName WScript.Shell

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "TodoSidepanel.lnk"
$targetPath = Join-Path $PSHOME "powershell.exe"
$appScript = Join-Path $scriptRoot "app.ps1"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetPath
$shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appScript`""
$shortcut.WorkingDirectory = $scriptRoot
$shortcut.IconLocation = "$targetPath,0"
$shortcut.Save()

Write-Host "Autostart er satt opp:"
Write-Host $shortcutPath
