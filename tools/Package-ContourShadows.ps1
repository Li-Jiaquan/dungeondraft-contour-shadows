[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    throw 'OutputPath must be an explicit absolute path.'
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modRoot = (Resolve-Path (Join-Path $repoRoot 'mod')).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$modPrefix = $modRoot.TrimEnd('\') + '\'
if ($outputFull.StartsWith($modPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Place the archive outside mod/ so it cannot become part of the install payload.'
}
if (Test-Path -LiteralPath $outputFull) {
    throw "Output already exists; choose a new path to preserve the existing file: $outputFull"
}
$required = @(
    'contour_shadows.ddmod',
    'scripts\contour_shadows.gd',
    'scripts\library\shadow_renderer.gd',
    'scripts\library\shadow_renderer_cpu_fallback.gd',
    'scripts\library\shadow_geometry.gd',
	'scripts\library\path_source.gd',
	'scripts\library\shadow_mask.gd',
    'icons\contour_shadows.png'
)
foreach ($relative in $required) {
    $path = Join-Path $modRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Mod payload is incomplete: $path"
    }
}
if (-not $PSCmdlet.ShouldProcess($outputFull, 'Create deterministic Contour Shadows ZIP')) {
    return
}

$outputDirectory = Split-Path -Parent $outputFull
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$outputDirectory = (Resolve-Path -LiteralPath $outputDirectory).Path
$outputFull = Join-Path $outputDirectory (Split-Path -Leaf $outputFull)
if (Test-Path -LiteralPath $outputFull) {
    throw "Output already exists; choose a new path to preserve the existing file: $outputFull"
}
if ($outputFull.StartsWith($modPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The resolved output path points inside mod/; choose an external output directory.'
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = Get-ChildItem -LiteralPath $modRoot -File -Recurse | Where-Object {
    $_.Name -notin @('.DS_Store', 'Thumbs.db') -and $_.Extension -ne '.import'
}
$entries = @{}
foreach ($file in $files) {
    $relative = $file.FullName.Substring($modRoot.TrimEnd('\').Length + 1).Replace('\', '/')
    $entryName = 'contour_shadows/' + $relative
    if ($entries.ContainsKey($entryName)) {
        throw "Duplicate archive entry: $entryName"
    }
    $entries[$entryName] = $file.FullName
}
$entryNames = [string[]]@($entries.Keys)
[Array]::Sort($entryNames, [StringComparer]::Ordinal)

$archive = $null
try {
    $archive = [System.IO.Compression.ZipFile]::Open($outputFull, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($entryName in $entryNames) {
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputStream = [System.IO.File]::OpenRead($entries[$entryName])
        $outputStream = $entry.Open()
        try {
            $inputStream.CopyTo($outputStream)
        }
        finally {
            $outputStream.Dispose()
            $inputStream.Dispose()
        }
    }
}
catch {
    if ($archive -ne $null) {
        $archive.Dispose()
    }
    throw
}
finally {
    if ($archive -ne $null) {
        $archive.Dispose()
    }
}

$archiveInfo = Get-Item -LiteralPath $outputFull
Write-Host "Created: $($archiveInfo.FullName)"
Write-Host "Files: $($entryNames.Count); bytes: $($archiveInfo.Length)"
