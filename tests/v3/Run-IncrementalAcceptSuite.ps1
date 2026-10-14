[CmdletBinding()]
param(
	[string] $GodotExecutable = 'D:\Dungeondraft\Dungeondraft.exe',
	[string] $ProfileRoot = '..\..\integration\qa-appdata'
)

$ErrorActionPreference = 'Stop'
$testsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $testsRoot '..')).Path
$engineSource = (Resolve-Path -LiteralPath $GodotExecutable).Path
$engineRoot = Join-Path $testsRoot '.staged\v3-engine'
New-Item -ItemType Directory -Path $engineRoot -Force | Out-Null
$stagedEngine = Join-Path (Resolve-Path -LiteralPath $engineRoot).Path 'godot3-incremental-accept.exe'
Copy-Item -LiteralPath $engineSource -Destination $stagedEngine -Force
$fixtureStage = Join-Path $testsRoot '.staged\incremental-accept'
New-Item -ItemType Directory -Path $fixtureStage -Force | Out-Null
$stagedHost = Join-Path $fixtureStage 'contour_shadows.gd'
$stagedMask = Join-Path $fixtureStage 'shadow_mask.gd'
$stagedDriver = Join-Path $fixtureStage 'integration_driver.gd'
$hostSource = [IO.File]::ReadAllText((Join-Path $repoRoot 'mod/scripts/contour_shadows.gd'))
$testPreamble = "extends Reference`nvar Global = null`nvar Script = null`n`n"
[IO.File]::WriteAllText($stagedHost, $testPreamble + $hostSource, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $repoRoot 'mod/scripts/library/shadow_mask.gd') -Destination $stagedMask -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'integration/v2_driver.gd') -Destination $stagedDriver -Force

$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$stdoutPath = Join-Path $artifactRoot 'incremental-accept.stdout.log'
$stderrPath = Join-Path $artifactRoot 'incremental-accept.stderr.log'
$engineDirectory = Split-Path -Parent $engineSource
$originalPath = $env:PATH
$originalAppData = $env:APPDATA
$qaProfile = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $ProfileRoot)).Path
try {
	$env:PATH = $engineDirectory + [IO.Path]::PathSeparator + $originalPath
	$env:APPDATA = $qaProfile
	$arguments = @(
		'--no-window',
		'--audio-driver', 'Dummy',
		'--video-driver', 'GLES2',
		'--path', ('"' + $testsRoot + '"'),
		'--script', 'res://v3/incremental_accept_suite.gd'
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
	$env:APPDATA = $originalAppData
}

Write-Host "Incremental acceptance exit code: $($process.ExitCode)"
Write-Host "Staged host SHA256: $((Get-FileHash -LiteralPath $stagedHost -Algorithm SHA256).Hash)"
Write-Host "Staged mask SHA256: $((Get-FileHash -LiteralPath $stagedMask -Algorithm SHA256).Hash)"
Write-Host "Staged driver SHA256: $((Get-FileHash -LiteralPath $stagedDriver -Algorithm SHA256).Hash)"
Write-Host "Report: $(Join-Path $PSScriptRoot 'artifacts/incremental-accept-report.json')"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
if ($process.ExitCode -ne 0) {
	Get-Content -LiteralPath $stdoutPath -Raw
	Get-Content -LiteralPath $stderrPath -Raw
	throw 'Incremental host acceptance failed.'
}
Get-Content -LiteralPath (Join-Path $artifactRoot 'incremental-accept-report.json') -Raw
