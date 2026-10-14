[CmdletBinding()]
param(
	[ValidateSet('GLES2', 'GLES3')]
	[string] $Driver = 'GLES3',
	[string] $GodotExecutable = 'D:\Dungeondraft\Dungeondraft.exe'
)

$ErrorActionPreference = 'Stop'
$testsRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $testsRoot '..')).Path
$engineSource = (Resolve-Path -LiteralPath $GodotExecutable).Path
$stageRoot = Join-Path $testsRoot '.staged'
$engineRoot = Join-Path $stageRoot 'v3-engine'
if (-not (Test-Path -LiteralPath $engineRoot -PathType Container)) {
	New-Item -ItemType Directory -Path $engineRoot -Force | Out-Null
}
$engineRoot = (Resolve-Path -LiteralPath $engineRoot).Path
$stagedEngine = Join-Path $engineRoot 'godot3-test.exe'
Copy-Item -LiteralPath $engineSource -Destination $stagedEngine -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'mod/scripts/library/shadow_mask.gd') -Destination (Join-Path $stageRoot 'shadow_mask_gpu_stroke_v3.gd') -Force

$driverKey = $Driver.ToLower()
$stdoutPath = Join-Path $PSScriptRoot "artifacts/mask-gpu-stroke-$driverKey.stdout.log"
$stderrPath = Join-Path $PSScriptRoot "artifacts/mask-gpu-stroke-$driverKey.stderr.log"
$reportPath = Join-Path $PSScriptRoot "artifacts/mask-gpu-stroke-$driverKey.report.json"
$originalPath = $env:PATH
$originalDriver = $env:GPU_PROBE_DRIVER
try {
	$env:PATH = (Split-Path -Parent $engineSource) + [IO.Path]::PathSeparator + $originalPath
	$env:GPU_PROBE_DRIVER = $Driver
	$arguments = @(
		'--no-window',
		'--audio-driver', 'Dummy',
		'--video-driver', $Driver,
		'--path', ('"' + $testsRoot + '"'),
		'--script', 'res://v3/mask_gpu_stroke_suite.gd'
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
	if ($null -eq $originalDriver) {
		Remove-Item Env:GPU_PROBE_DRIVER -ErrorAction SilentlyContinue
	} else {
		$env:GPU_PROBE_DRIVER = $originalDriver
	}
}

Write-Host "GPU mask stroke suite driver: $Driver"
Write-Host "Exit code: $($process.ExitCode)"
Write-Host "Report: $reportPath"
if ($process.ExitCode -ne 0) {
	Get-Content -LiteralPath $stdoutPath -Raw
	Get-Content -LiteralPath $stderrPath -Raw
	throw "GPU mask stroke suite failed on $Driver."
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'artifacts/mask-gpu-stroke-report.json') -Destination $reportPath -Force
Get-Content -LiteralPath $stdoutPath -Raw
