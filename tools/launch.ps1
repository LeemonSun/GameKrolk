param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskMutex = $null
$ownsMutex = $false
function Show-GameMessage([string]$message) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($message, 'GameKrolk') | Out-Null
}
try {
    $projectFile = Join-Path $projectRoot 'project.godot'
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw 'project.godot is missing. Keep the launcher inside the game folder.' }
    $candidates = @()
    if ($env:GAMEKROLK_GODOT) { $candidates += $env:GAMEKROLK_GODOT }
    $candidates += Join-Path (Split-Path $projectRoot -Parent) 'local\godot\Godot_v4.7.2-stable_win64.exe'
    $candidates += Join-Path $projectRoot 'tools\godot\Godot.exe'
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCommand) { $candidates += $godotCommand.Source }
    $engine = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $engine) { throw 'Godot 4.7.2 was not found. Set GAMEKROLK_GODOT to your Godot executable, then run START_GAME.cmd again.' }
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($projectRoot.ToLowerInvariant())))).Replace('-', '').Substring(0, 24) } finally { $hash.Dispose() }
    $mutexName = 'Local\GameKrolk-' + $key
    if ($SmokeTest) { $mutexName += '-test' }
    $taskMutex = New-Object Threading.Mutex($false, $mutexName)
    try { $ownsMutex = $taskMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { Show-GameMessage 'GameKrolk is already running. Close its window before starting another copy.'; exit 0 }
    $logDirectory = Join-Path $projectRoot 'work'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logFile = Join-Path $logDirectory $(if ($SmokeTest) { 'launcher-smoke.log' } else { 'game.log' })
    $gameArguments = @('--path', ('"{0}"' -f $projectRoot), '--log-file', ('"{0}"' -f $logFile))
    if ($SmokeTest) { $gameArguments += @('--quit-after', '10', '--', '--test-mode') }
    $gameProcess = Start-Process -FilePath $engine -WorkingDirectory $projectRoot -ArgumentList $gameArguments -PassThru
    $null = $gameProcess.Handle
    $gameProcess.WaitForExit()
    $gameProcess.Refresh()
    if ($gameProcess.ExitCode -ne 0) { throw ('The game exited with code {0}. Log: {1}' -f $gameProcess.ExitCode, $logFile) }
} catch {
    Show-GameMessage $_.Exception.Message
    exit 1
} finally {
    if ($ownsMutex -and $taskMutex) { $taskMutex.ReleaseMutex() }
    if ($taskMutex) { $taskMutex.Dispose() }
}
