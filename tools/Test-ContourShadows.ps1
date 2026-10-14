[CmdletBinding()]
param(
    [string] $GodotExecutable = 'D:\Dungeondraft\Dungeondraft.exe',
    [switch] $DirectEngine,
    [switch] $PrepareOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testsRoot = (Resolve-Path (Join-Path $repoRoot 'tests')).Path
$modRoot = Join-Path $repoRoot 'mod'
$stageRoot = Join-Path $testsRoot '.staged'
$libraryRoot = Join-Path $modRoot 'scripts\library'
$required = @(
    (Join-Path $modRoot 'contour_shadows.ddmod'),
    (Join-Path $modRoot 'scripts\contour_shadows.gd'),
    (Join-Path $libraryRoot 'shadow_renderer.gd'),
    (Join-Path $libraryRoot 'shadow_geometry.gd'),
	(Join-Path $libraryRoot 'path_source.gd'),
	(Join-Path $libraryRoot 'shadow_mask.gd'),
    (Join-Path $modRoot 'icons\contour_shadows.png'),
    (Join-Path $libraryRoot 'shadow_renderer_cpu_fallback.gd')
)

foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Harness input is missing: $path"
    }
}

if (Test-Path -LiteralPath $stageRoot) {
    $stageItem = Get-Item -LiteralPath $stageRoot -Force
    if (($stageItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to stage through a reparse point: $stageRoot"
    }
}
else {
    New-Item -ItemType Directory -Path $stageRoot | Out-Null
}

$stageFull = (Resolve-Path -LiteralPath $stageRoot).Path
$testsPrefix = $testsRoot.TrimEnd('\') + '\'
if (-not $stageFull.StartsWith($testsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Staging path escaped tests/: $stageFull"
}

Copy-Item -LiteralPath $required[0] -Destination (Join-Path $stageRoot 'contour_shadows.ddmod') -Force
$hostSource = [IO.File]::ReadAllText($required[1])
$hostLines = New-Object 'System.Collections.Generic.List[string]'
$sourceLines = $hostSource -split '\r?\n'
$sourceHasExtends = $sourceLines.Length -gt 0 -and $sourceLines[0] -match '^\s*extends\s+'
if ($sourceHasExtends) {
    $hostLines.Add($sourceLines[0])
}
else {
    $hostLines.Add('extends Reference')
}
$hostLines.Add('var Global = null')
$hostLines.Add('var Script = null')
$startLine = 0
if ($sourceHasExtends) {
    $startLine = 1
}
for ($i = $startLine; $i -lt $sourceLines.Length; $i++) {
    $hostLines.Add($sourceLines[$i])
}
$hostText = [string]::Join([Environment]::NewLine, $hostLines) + [Environment]::NewLine
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $stageRoot 'contour_shadows.gd'), $hostText, $utf8NoBom)
Copy-Item -LiteralPath $required[2] -Destination (Join-Path $stageRoot 'shadow_renderer.gd') -Force
Copy-Item -LiteralPath $required[3] -Destination (Join-Path $stageRoot 'shadow_geometry.gd') -Force
Copy-Item -LiteralPath $required[4] -Destination (Join-Path $stageRoot 'path_source.gd') -Force
Copy-Item -LiteralPath $required[5] -Destination (Join-Path $stageRoot 'shadow_mask.gd') -Force
Copy-Item -LiteralPath $required[6] -Destination (Join-Path $stageRoot 'contour_shadows.png') -Force
Copy-Item -LiteralPath $required[7] -Destination (Join-Path $stageRoot 'shadow_renderer_cpu_fallback.gd') -Force
$nestedLibraryRoot = Join-Path $stageRoot 'scripts\library'
if (-not (Test-Path -LiteralPath $nestedLibraryRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $nestedLibraryRoot -Force | Out-Null
}
$nestedLibraryFull = (Resolve-Path -LiteralPath $nestedLibraryRoot).Path
if (-not $nestedLibraryFull.StartsWith($stageFull.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Nested library staging path escaped tests/.staged/: $nestedLibraryFull"
}
Copy-Item -LiteralPath $required[2] -Destination (Join-Path $nestedLibraryFull 'shadow_renderer.gd') -Force
Copy-Item -LiteralPath $required[3] -Destination (Join-Path $nestedLibraryFull 'shadow_geometry.gd') -Force
Copy-Item -LiteralPath $required[4] -Destination (Join-Path $nestedLibraryFull 'path_source.gd') -Force
Copy-Item -LiteralPath $required[5] -Destination (Join-Path $nestedLibraryFull 'shadow_mask.gd') -Force
Copy-Item -LiteralPath $required[7] -Destination (Join-Path $nestedLibraryFull 'shadow_renderer_cpu_fallback.gd') -Force

$reportPath = Join-Path $stageRoot 'report.txt'
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    $reportFull = (Resolve-Path -LiteralPath $reportPath).Path
    if (-not $reportFull.StartsWith($testsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear report outside tests/: $reportFull"
    }
    $reportStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archiveReport = Join-Path $stageRoot ("report." + $reportStamp + '.txt')
    while (Test-Path -LiteralPath $archiveReport) {
        $archiveReport = Join-Path $stageRoot ("report." + $reportStamp + '.' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    }
    Copy-Item -LiteralPath $reportFull -Destination $archiveReport
    Remove-Item -LiteralPath $reportFull
    Write-Host "Previous native report preserved at: $archiveReport"
}

$scriptPath = Join-Path $testsRoot 'run.gd'
Write-Host "Staged current mod sources under: $stageFull"
Write-Host "Native report path: $reportPath"

if ($PrepareOnly) {
    Write-Host ('Prepared only. Run this harness with: .\tools\Test-ContourShadows.ps1 -GodotExecutable ' + $GodotExecutable)
    return
}

if (-not [IO.Path]::IsPathRooted($GodotExecutable)) {
    throw 'GodotExecutable must be an absolute path.'
}
$enginePath = (Resolve-Path -LiteralPath $GodotExecutable).Path
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Godot executable not found: $GodotExecutable"
}

$launchPath = $enginePath
$engineDirectory = Split-Path -Parent $enginePath
if (-not $DirectEngine) {
    $engineStage = Join-Path $stageRoot 'engine'
    if (Test-Path -LiteralPath $engineStage) {
        $engineStageItem = Get-Item -LiteralPath $engineStage -Force
        if (($engineStageItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to stage the test engine through a reparse point: $engineStage"
        }
    }
    else {
        New-Item -ItemType Directory -Path $engineStage | Out-Null
    }
    $engineStageFull = (Resolve-Path -LiteralPath $engineStage).Path
    if (-not $engineStageFull.StartsWith($stageFull.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Engine staging path escaped tests/.staged/: $engineStageFull"
    }
    $launchPath = Join-Path $engineStageFull 'godot3-test.exe'
    $sourceHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash
    $stagedHash = $null
    if (Test-Path -LiteralPath $launchPath -PathType Leaf) {
        $stagedHash = (Get-FileHash -LiteralPath $launchPath -Algorithm SHA256).Hash
    }
    if ($sourceHash -ne $stagedHash) {
        Copy-Item -LiteralPath $enginePath -Destination $launchPath -Force
    }
    $engineDirectory = Split-Path -Parent $enginePath
}

$logsRoot = Join-Path $stageRoot 'logs'
if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $logsRoot | Out-Null
}
$logsFull = (Resolve-Path -LiteralPath $logsRoot).Path
if (-not $logsFull.StartsWith($stageFull.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Log path escaped tests/.staged/: $logsFull"
}
$logStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$stdoutPath = Join-Path $logsFull ("native-$logStamp.stdout.log")
$stderrPath = Join-Path $logsFull ("native-$logStamp.stderr.log")

$arguments = @(
    '--no-window',
    '--audio-driver', 'Dummy',
    '--video-driver', 'GLES2',
    '--path', ('"' + $testsRoot + '"'),
    '--script', ('"' + $scriptPath + '"')
)
$originalPath = $env:PATH
$originalAppData = $env:APPDATA
$runtimeProfile = Join-Path $stageFull 'runtime-appdata'
New-Item -ItemType Directory -Path $runtimeProfile -Force | Out-Null
$process = $null
try {
    # The copied executable remains isolated from Dungeondraft's adjacent PCK. Mono
    # runtime dependencies still come from the original installation directory.
    $env:PATH = $engineDirectory + [IO.Path]::PathSeparator + $originalPath
    $env:APPDATA = $runtimeProfile
    $process = Start-Process -FilePath $launchPath `
        -ArgumentList $arguments `
        -WorkingDirectory $testsRoot `
        -WindowStyle Hidden `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
}
finally {
    $env:PATH = $originalPath
    $env:APPDATA = $originalAppData
}
$engineExitCode = $process.ExitCode

if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    $stdoutText = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderrText = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    throw "The native runtime did not write its report. Process exit code: $engineExitCode`nstdout: $stdoutText`nstderr: $stderrText"
}
Get-Content -LiteralPath $reportPath
$reportText = Get-Content -LiteralPath $reportPath -Raw
if ($engineExitCode -ne 0 -or $reportText -notmatch '(?m)^FAILURE_COUNT: 0\s*$' -or $reportText -notmatch '(?m)^RESULT: PASS\s*$') {
    $stdoutText = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderrText = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    throw "Native Godot test harness failed. Process exit code: $engineExitCode. Logs: $stdoutPath ; $stderrPath`nstdout: $stdoutText`nstderr: $stderrText"
}
Write-Host "Native process exit code: $engineExitCode"
Write-Host "stdout log: $stdoutPath"
Write-Host "stderr log: $stderrPath"
