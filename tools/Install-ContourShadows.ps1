[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string] $Destination,
    [string] $SourcePath
)

$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathRooted($Destination)) {
    throw 'Destination must be an explicit absolute path to the Dungeondraft mods folder.'
}
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
    throw "Destination must already exist as a directory: $destinationPath"
}
$destinationPath = (Resolve-Path -LiteralPath $destinationPath).Path.TrimEnd('\')
$destinationRoot = [IO.Path]::GetPathRoot($destinationPath).TrimEnd('\')
if ([string]::Equals($destinationPath, $destinationRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must be a mods folder, not a drive root.'
}

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $candidatePaths = @(
        (Join-Path $repoRoot 'mod'),
        (Join-Path $repoRoot 'contour_shadows'),
        $repoRoot
    )
}
else {
    if (-not [IO.Path]::IsPathRooted($SourcePath)) {
        throw 'SourcePath must be absolute when supplied.'
    }
    $sourceFull = (Resolve-Path -LiteralPath $SourcePath).Path
    $candidatePaths = @(
        $sourceFull,
        (Join-Path $sourceFull 'contour_shadows'),
        (Join-Path $sourceFull 'mod')
    )
}

$payloadRoot = $null
foreach ($candidate in $candidatePaths) {
    if (Test-Path -LiteralPath (Join-Path $candidate 'contour_shadows.ddmod') -PathType Leaf) {
        $payloadRoot = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if ($null -eq $payloadRoot) {
    throw 'Could not find a mod payload containing contour_shadows.ddmod. Pass the extracted mod folder with -SourcePath.'
}

$required = @(
    'contour_shadows.ddmod',
    'scripts\contour_shadows.gd',
    'scripts\library\localization.gd',
    'scripts\library\shadow_renderer.gd',
    'scripts\library\shadow_renderer_cpu_fallback.gd',
    'scripts\library\shadow_geometry.gd',
	'scripts\library\path_source.gd',
	'scripts\library\shadow_mask.gd',
    'icons\contour_shadows.png'
)
foreach ($relative in $required) {
    $path = Join-Path $payloadRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Mod payload is incomplete: $path"
    }
}

$targetPath = Join-Path $destinationPath 'contour_shadows'
$destinationPrefix = $destinationPath.TrimEnd('\') + '\'
if (-not $targetPath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Install target escaped the explicit destination: $targetPath"
}
if ([string]::Equals($payloadRoot.TrimEnd('\'), $targetPath.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source payload and install target resolve to the same directory.'
}
if ((Test-Path -LiteralPath $targetPath) -and -not (Test-Path -LiteralPath $targetPath -PathType Container)) {
    throw "An existing file occupies the plugin directory name: $targetPath"
}
if (Test-Path -LiteralPath $targetPath -PathType Container) {
    $targetItem = Get-Item -LiteralPath $targetPath -Force
    if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to replace a reparse point: $targetPath"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$destinationParent = Split-Path -Parent $destinationPath
$backupPath = Join-Path $destinationParent ("contour_shadows.backup." + $stamp)
while (Test-Path -LiteralPath $backupPath) {
    $backupPath = Join-Path $destinationParent ("contour_shadows.backup." + $stamp + '.' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
$stagePath = Join-Path $destinationPath ('.contour_shadows.install.' + [Guid]::NewGuid().ToString('N'))

if (-not $PSCmdlet.ShouldProcess($targetPath, 'Install contour_shadows and preserve any existing copy as a timestamped backup')) {
    return
}

New-Item -ItemType Directory -Path $stagePath | Out-Null
$stageResolved = (Resolve-Path -LiteralPath $stagePath).Path
if (-not $stageResolved.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary install path escaped the explicit destination: $stageResolved"
}

$existingMoved = $false
try {
    Get-ChildItem -LiteralPath $payloadRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stagePath -Recurse
    }
    if (Test-Path -LiteralPath $targetPath) {
        Move-Item -LiteralPath $targetPath -Destination $backupPath
        $existingMoved = $true
    }
    Move-Item -LiteralPath $stagePath -Destination $targetPath
}
catch {
    if (Test-Path -LiteralPath $stagePath) {
        $failedStage = (Resolve-Path -LiteralPath $stagePath).Path.TrimEnd('\')
        if (-not $failedStage.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove a temporary path outside the explicit destination: $failedStage"
        }
        Remove-Item -LiteralPath $failedStage -Recurse -Force
    }
    if ($existingMoved -and -not (Test-Path -LiteralPath $targetPath) -and (Test-Path -LiteralPath $backupPath)) {
        Move-Item -LiteralPath $backupPath -Destination $targetPath
    }
    throw
}

if ($existingMoved) {
    Write-Host "Previous plugin preserved beside the mods folder at: $backupPath"
}
Write-Host "Installed contour_shadows at: $targetPath"
