[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$modRoot = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'mod')).Path
$stagedRoot = Join-Path $PSScriptRoot '.staged'
if (-not (Test-Path -LiteralPath $stagedRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $stagedRoot | Out-Null
}
$stagedRoot = (Resolve-Path -LiteralPath $stagedRoot).Path.TrimEnd('\')
$testRoot = Join-Path $stagedRoot ('distribution-tools-test-' + [Guid]::NewGuid().ToString('N'))
$testPrefix = $stagedRoot + '\'
if (-not $testRoot.StartsWith($testPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create test files outside tests/.staged: $testRoot"
}

$installer = Join-Path $repoRoot 'tools/Install-ContourShadows.ps1'
$packager = Join-Path $repoRoot 'tools/Package-ContourShadows.ps1'
$assertions = 0

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    $freshMods = Join-Path $testRoot 'fresh/mods'
    New-Item -ItemType Directory -Path $freshMods -Force | Out-Null
    & $installer -Destination $freshMods -SourcePath $modRoot -Confirm:$false | Out-Null
    $freshPlugin = Join-Path $freshMods 'contour_shadows'
    Assert-Condition (Test-Path -LiteralPath (Join-Path $freshPlugin 'contour_shadows.ddmod') -PathType Leaf) 'fresh install copies the manifest'
    $assertions++
    Assert-Condition (Test-Path -LiteralPath (Join-Path $freshPlugin 'scripts/library/shadow_renderer.gd') -PathType Leaf) 'fresh install copies the renderer'
    $assertions++
    Assert-Condition (Test-Path -LiteralPath (Join-Path $freshPlugin 'scripts/library/shadow_renderer_cpu_fallback.gd') -PathType Leaf) 'fresh install copies the CPU compatibility backend'
    $assertions++
	Assert-Condition (Test-Path -LiteralPath (Join-Path $freshPlugin 'scripts/library/path_source.gd') -PathType Leaf) 'fresh install copies the Pathway source adapter'
	$assertions++
	Assert-Condition (Test-Path -LiteralPath (Join-Path $freshPlugin 'scripts/library/shadow_mask.gd') -PathType Leaf) 'fresh install copies the local erasure mask'
	$assertions++
    Assert-Condition (@(Get-ChildItem -LiteralPath (Split-Path -Parent $freshMods) -Directory -Filter 'contour_shadows.backup.*').Count -eq 0) 'fresh install creates no backup'
    $assertions++

    $conflictArea = Join-Path $testRoot 'conflict'
    $conflictMods = Join-Path $conflictArea 'mods'
    $oldPlugin = Join-Path $conflictMods 'contour_shadows'
    New-Item -ItemType Directory -Path $oldPlugin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $oldPlugin 'keep.txt') -Value 'previous plugin copy' -NoNewline
    & $installer -Destination $conflictMods -SourcePath $modRoot -Confirm:$false | Out-Null
    $newPlugin = Join-Path $conflictMods 'contour_shadows'
    $backups = @(Get-ChildItem -LiteralPath $conflictArea -Directory -Filter 'contour_shadows.backup.*')
    Assert-Condition (Test-Path -LiteralPath (Join-Path $newPlugin 'contour_shadows.ddmod') -PathType Leaf) 'replacement installs the new manifest'
    $assertions++
    Assert-Condition ($backups.Count -eq 1) 'replacement keeps one timestamped backup beside the mods folder'
    $assertions++
    Assert-Condition ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'keep.txt') -Raw) -eq 'previous plugin copy') 'replacement backup retains prior files'
    $assertions++

    $whatIfMods = Join-Path $testRoot 'whatif/mods'
    New-Item -ItemType Directory -Path $whatIfMods -Force | Out-Null
    & $installer -Destination $whatIfMods -SourcePath $modRoot -WhatIf | Out-Null
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $whatIfMods 'contour_shadows'))) 'WhatIf leaves the destination unchanged'
    $assertions++

    $zipOne = Join-Path $testRoot 'package-a.zip'
    $zipTwo = Join-Path $testRoot 'package-b.zip'
    & $packager -OutputPath $zipOne -Confirm:$false | Out-Null
    & $packager -OutputPath $zipTwo -Confirm:$false | Out-Null
    $hashOne = (Get-FileHash -LiteralPath $zipOne -Algorithm SHA256).Hash
    $hashTwo = (Get-FileHash -LiteralPath $zipTwo -Algorithm SHA256).Hash
    Assert-Condition ($hashOne -eq $hashTwo) 'two packages from the same payload are byte-identical'
    $assertions++

    Add-Type -AssemblyName System.IO.Compression
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipOne)
    try {
        $actualEntries = [string[]]@($archive.Entries | ForEach-Object FullName)
    }
    finally { $archive.Dispose() }
    [Array]::Sort($actualEntries, [StringComparer]::Ordinal)

    $sourceFiles = @(Get-ChildItem -LiteralPath $modRoot -File -Recurse | Where-Object {
        $_.Name -notin @('.DS_Store', 'Thumbs.db') -and $_.Extension -ne '.import'
    })
    $expectedEntries = [string[]]@($sourceFiles | ForEach-Object {
        'contour_shadows/' + $_.FullName.Substring($modRoot.TrimEnd('\').Length + 1).Replace('\', '/')
    })
    [Array]::Sort($expectedEntries, [StringComparer]::Ordinal)
    Assert-Condition (($actualEntries -join "`n") -ceq ($expectedEntries -join "`n")) 'archive contains only the install payload under contour_shadows/'
    $assertions++

    $existingHash = $hashOne
    $refusedOverwrite = $false
    try { & $packager -OutputPath $zipOne -Confirm:$false | Out-Null }
    catch { $refusedOverwrite = $true }
    Assert-Condition $refusedOverwrite 'packager refuses to overwrite an existing archive'
    $assertions++
    Assert-Condition ((Get-FileHash -LiteralPath $zipOne -Algorithm SHA256).Hash -eq $existingHash) 'refused overwrite preserves the existing archive'
    $assertions++

    Write-Host "DISTRIBUTION_TOOL_ASSERTION_COUNT: $assertions"
    Write-Host 'RESULT: PASS'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path.TrimEnd('\')
        if (-not $resolvedTestRoot.StartsWith($testPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing cleanup outside tests/.staged: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
