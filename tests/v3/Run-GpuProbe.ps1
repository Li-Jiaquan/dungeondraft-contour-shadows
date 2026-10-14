[CmdletBinding()]
param(
	[ValidateSet('GLES2', 'GLES3')]
	[string] $Driver = 'GLES3',
	[switch] $VFlip,
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
$stagedEngine = Join-Path (Resolve-Path -LiteralPath $engineRoot).Path 'godot3-test.exe'
Copy-Item -LiteralPath $engineSource -Destination $stagedEngine -Force

$stdoutPath = Join-Path $PSScriptRoot ("artifacts/gpu-probe-$($Driver.ToLower()).stdout.log")
$stderrPath = Join-Path $PSScriptRoot ("artifacts/gpu-probe-$($Driver.ToLower()).stderr.log")
$env:GPU_PROBE_DRIVER = $Driver
$env:GPU_PROBE_V_FLIP = if ($VFlip) { '1' } else { '0' }
$sourceEngineDirectory = Split-Path -Parent $engineSource
$originalPath = $env:PATH
try {
	$env:PATH = $sourceEngineDirectory + [IO.Path]::PathSeparator + $originalPath
	$arguments = @(
		'--no-window',
		'--audio-driver', 'Dummy',
		'--video-driver', $Driver,
		'--path', ('"' + $testsRoot + '"'),
		'--script', 'res://v3/gpu_probe.gd'
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
	Remove-Item Env:GPU_PROBE_V_FLIP -ErrorAction SilentlyContinue
}

Write-Host "GPU probe driver: $Driver"
Write-Host "Exit code: $($process.ExitCode)"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
if ($process.ExitCode -ne 0) {
	Get-Content -LiteralPath $stdoutPath -Raw
	Get-Content -LiteralPath $stderrPath -Raw
	throw "GPU probe failed on $Driver."
}
Get-Content -LiteralPath $stdoutPath -Raw
