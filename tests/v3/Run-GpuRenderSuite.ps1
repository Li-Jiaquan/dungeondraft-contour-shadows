[CmdletBinding()]
param(
	[ValidateSet('GLES2', 'GLES3')]
	[string] $Driver = 'GLES3',
	[string] $GodotExecutable = 'D:\Dungeondraft\Dungeondraft.exe'
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
$stagedCpuFallback = Join-Path $stageRoot 'shadow_renderer_cpu_fallback.gd'
Copy-Item -LiteralPath $engineSource -Destination $stagedEngine -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'mod/scripts/library/shadow_renderer.gd') -Destination $stagedRenderer -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'mod/scripts/library/shadow_renderer_cpu_fallback.gd') -Destination $stagedCpuFallback -Force

$driverKey = $Driver.ToLower()
$stdoutPath = Join-Path $PSScriptRoot "artifacts/gpu-render-$driverKey.stdout.log"
$stderrPath = Join-Path $PSScriptRoot "artifacts/gpu-render-$driverKey.stderr.log"
$env:GPU_PROBE_DRIVER = $Driver
$sourceEngineDirectory = Split-Path -Parent $engineSource
$originalPath = $env:PATH
try {
	$env:PATH = $sourceEngineDirectory + [IO.Path]::PathSeparator + $originalPath
	$arguments = @(
		'--no-window',
		'--audio-driver', 'Dummy',
		'--video-driver', $Driver,
		'--path', ('"' + $testsRoot + '"'),
		'--script', 'res://v3/gpu_render_suite.gd'
	)
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
	Remove-Item Env:GPU_PROBE_DRIVER -ErrorAction SilentlyContinue
}

Write-Host "GPU renderer suite driver: $Driver"
Write-Host "Exit code: $($process.ExitCode)"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
if ($process.ExitCode -ne 0) {
	Get-Content -LiteralPath $stdoutPath -Raw
	Get-Content -LiteralPath $stderrPath -Raw
	throw "GPU renderer suite failed on $Driver."
}
Get-Content -LiteralPath $stdoutPath -Raw
