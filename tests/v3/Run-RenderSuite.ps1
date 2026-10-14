[CmdletBinding()]
param(
    [string] $GodotExecutable = 'D:\Dungeondraft\Dungeondraft.exe',
    [switch] $FullBenchmark
)

$ErrorActionPreference = 'Stop'
$testsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
$engineSource = (Resolve-Path -LiteralPath $GodotExecutable).Path
$stageRoot = Join-Path $testsRoot '.staged'
$engineRoot = Join-Path $stageRoot 'v3-engine'

if (-not (Test-Path -LiteralPath $engineRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $engineRoot -Force | Out-Null
}
$engineRoot = (Resolve-Path -LiteralPath $engineRoot).Path
$stagedEngine = Join-Path $engineRoot 'godot3-test.exe'
$stagedRenderer = Join-Path $stageRoot 'shadow_renderer_v3.gd'
$stagedProductionRenderer = Join-Path $stageRoot 'shadow_renderer_prod.gd'
$stagedCpuFallback = Join-Path $stageRoot 'shadow_renderer_cpu_fallback.gd'
Copy-Item -LiteralPath $engineSource -Destination $stagedEngine -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'renderer_cpu_reference.gd') -Destination $stagedRenderer -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'mod/scripts/library/shadow_renderer.gd') -Destination $stagedProductionRenderer -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'mod/scripts/library/shadow_renderer_cpu_fallback.gd') -Destination $stagedCpuFallback -Force

$sourceEngineDirectory = Split-Path -Parent $engineSource
$originalPath = $env:PATH
$originalBenchmarkFlag = $env:CONTOUR_SHADOWS_FULL_BENCHMARK
$stdoutPath = Join-Path $PSScriptRoot 'artifacts/renderer-v3.stdout.log'
$stderrPath = Join-Path $PSScriptRoot 'artifacts/renderer-v3.stderr.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $stdoutPath) -Force | Out-Null
$arguments = @(
    '--no-window',
    '--audio-driver', 'Dummy',
    '--video-driver', 'GLES2',
    '--path', ('"' + $testsRoot + '"'),
    '--script', 'res://v3/render_suite.gd'
)
$process = $null
try {
    # The copied engine has no adjacent Dungeondraft PCK. Its Mono dependencies
    # still resolve from the installed engine directory.
    $env:PATH = $sourceEngineDirectory + [IO.Path]::PathSeparator + $originalPath
	$env:CONTOUR_SHADOWS_FULL_BENCHMARK = if ($FullBenchmark) { '1' } else { '0' }
    $process = Start-Process -FilePath $stagedEngine `
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
	if ($null -eq $originalBenchmarkFlag) {
		Remove-Item Env:CONTOUR_SHADOWS_FULL_BENCHMARK -ErrorAction SilentlyContinue
	}
	else {
		$env:CONTOUR_SHADOWS_FULL_BENCHMARK = $originalBenchmarkFlag
	}
}

Write-Host "Native renderer suite exit code: $($process.ExitCode)"
Write-Host "Benchmark report: $(Join-Path $PSScriptRoot 'artifacts/benchmark.json')"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
if ($process.ExitCode -ne 0) {
    Get-Content -LiteralPath $stdoutPath -Raw
    Get-Content -LiteralPath $stderrPath -Raw
    throw 'Renderer v3 native suite failed.'
}
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'artifacts/benchmark.json') -Raw
