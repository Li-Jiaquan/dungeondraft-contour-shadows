[CmdletBinding()]
param(
	[ValidateSet('GLES2', 'GLES3')]
	[string] $Driver = 'GLES2',
	[string] $GodotExecutable = 'D:\Dungeondraft\Dungeondraft.exe'
)

$ErrorActionPreference = 'Stop'
$testsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engineSource = (Resolve-Path -LiteralPath $GodotExecutable).Path
$engineRoot = Join-Path $testsRoot '.staged\v3-engine'
New-Item -ItemType Directory -Path $engineRoot -Force | Out-Null
$stagedEngine = Join-Path (Resolve-Path -LiteralPath $engineRoot).Path 'godot3-test.exe'
Copy-Item -LiteralPath $engineSource -Destination $stagedEngine -Force

$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$stdoutPath = Join-Path $artifactRoot ("path-suite-$($Driver.ToLower()).stdout.log")
$stderrPath = Join-Path $artifactRoot ("path-suite-$($Driver.ToLower()).stderr.log")
$sourceEngineDirectory = Split-Path -Parent $engineSource
$originalPath = $env:PATH
$originalShaderFlag = $env:CONTOUR_PATH_SHADER_TEST
try {
	$env:PATH = $sourceEngineDirectory + [IO.Path]::PathSeparator + $originalPath
	$env:CONTOUR_PATH_SHADER_TEST = if ($Driver -eq 'GLES3') { '1' } else { '0' }
	$arguments = @(
		'--no-window',
		'--audio-driver', 'Dummy',
		'--video-driver', $Driver,
		'--path', ('"' + $testsRoot + '"'),
		'--script', 'res://v3/path_suite.gd'
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
	if ($null -eq $originalShaderFlag) {
		Remove-Item Env:CONTOUR_PATH_SHADER_TEST -ErrorAction SilentlyContinue
	}
	else {
		$env:CONTOUR_PATH_SHADER_TEST = $originalShaderFlag
	}
}

Write-Host "Path suite driver: $Driver"
Write-Host "Exit code: $($process.ExitCode)"
Write-Host "Report: $(Join-Path $testsRoot '.staged/path-suite-report.txt')"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
if ($process.ExitCode -ne 0) {
	Get-Content -LiteralPath $stdoutPath -Raw
	Get-Content -LiteralPath $stderrPath -Raw
	throw 'Path source suite failed.'
}
Get-Content -LiteralPath (Join-Path $testsRoot '.staged/path-suite-report.txt') -Raw
