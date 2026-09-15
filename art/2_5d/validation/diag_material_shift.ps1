#requires -Version 7.2
# Diagnostic copies only; preserve all original BIN chunks byte-for-byte.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '../models/breeze_town_farm.glb'
$bytes = [IO.File]::ReadAllBytes($source)
$jsonLength = [BitConverter]::ToUInt32($bytes, 12)
$originalJson = [Text.Encoding]::UTF8.GetString($bytes, 20, $jsonLength).TrimEnd([char]32, [char]0)
$tailOffset = 20 + $jsonLength
$tail = [byte[]]::new($bytes.Length - $tailOffset)
[Buffer]::BlockCopy($bytes, $tailOffset, $tail, 0, $tail.Length)

function Write-DiagnosticGlb([object] $Document, [string] $Name) {
    $jsonBytes = [Text.Encoding]::UTF8.GetBytes(($Document | ConvertTo-Json -Depth 100 -Compress))
    $paddingCount = (4 - $jsonBytes.Length % 4) % 4
    $stream = [IO.File]::Open((Join-Path $PSScriptRoot $Name), [IO.FileMode]::Create, [IO.FileAccess]::Write)
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint32] 0x46546c67)
        $writer.Write([uint32] 2)
        $writer.Write([uint32] (20 + $jsonBytes.Length + $paddingCount + $tail.Length))
        $writer.Write([uint32] ($jsonBytes.Length + $paddingCount))
        $writer.Write([uint32] 0x4e4f534a)
        $writer.Write($jsonBytes)
        for ($i = 0; $i -lt $paddingCount; $i++) { $writer.Write([byte] 32) }
        $writer.Write($tail)
    }
    finally { $writer.Dispose(); $stream.Dispose() }
}

$shifted = $originalJson | ConvertFrom-Json -AsHashtable -Depth 100
$unused = @{ name = 'DIAGNOSTIC_UNUSED_MATERIAL_ZERO'; pbrMetallicRoughness = @{ baseColorFactor = @(1.0, 0.0, 1.0, 1.0); metallicFactor = 0.0; roughnessFactor = 1.0 } }
$shifted.materials = @($unused) + @($shifted.materials)
$primitiveCount = 0
foreach ($mesh in $shifted.meshes) {
    foreach ($primitive in $mesh.primitives) {
        if ($primitive.Contains('material')) {
            $primitive.material = [int] $primitive.material + 1
            $primitiveCount++
        }
        if ($primitive.Contains('extensions') -and $primitive.extensions.Contains('KHR_materials_variants')) {
            foreach ($mapping in $primitive.extensions.KHR_materials_variants.mappings) {
                $mapping.material = [int] $mapping.material + 1
            }
        }
    }
}
Write-DiagnosticGlb $shifted 'diag_material_shift.glb'
$prefixed = $originalJson | ConvertFrom-Json -AsHashtable -Depth 100
$prefixMaterialIndex = $prefixed.materials.Count
$prefixed.materials = @($prefixed.materials) + @(@{ name = 'DIAGNOSTIC_UNUSED_PRIMITIVE_MATERIAL'; pbrMetallicRoughness = @{ baseColorFactor = @(1.0, 0.0, 1.0, 1.0); metallicFactor = 0.0; roughnessFactor = 1.0 } })
foreach ($mesh in $prefixed.meshes) {
    $dummy = $mesh.primitives[0] | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100
    $dummy.material = $prefixMaterialIndex
    [void] $dummy.attributes.Remove('COLOR_0')
    $mesh.primitives = @($dummy) + @($mesh.primitives)
}
Write-DiagnosticGlb $prefixed 'diag_material_primitive_prefix.glb'
$split = $originalJson | ConvertFrom-Json -AsHashtable -Depth 100
$splitMeshes = 0
foreach ($mesh in $split.meshes) {
    $firstPrimitive = $mesh.primitives[0]
    if (-not $firstPrimitive.Contains('indices') -or -not $firstPrimitive.attributes.Contains('COLOR_0')) { continue }
    $sourceAccessor = $split.accessors[[int] $firstPrimitive.indices]
    if ([int] $sourceAccessor.count -lt 6) { continue }
    $componentBytes = switch ([int] $sourceAccessor.componentType) { 5121 { 1 }; 5123 { 2 }; 5125 { 4 }; default { throw 'Unexpected index component type' } }
    $sourceOffset = if ($sourceAccessor.Contains('byteOffset')) { [int] $sourceAccessor.byteOffset } else { 0 }
    $firstAccessor = $sourceAccessor | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100
    $restAccessor = $sourceAccessor | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100
    $firstAccessor.count = 3
    $firstAccessor.byteOffset = $sourceOffset
    $restAccessor.count = [int] $sourceAccessor.count - 3
    $restAccessor.byteOffset = $sourceOffset + 3 * $componentBytes
    foreach ($accessor in @($firstAccessor, $restAccessor)) { [void] $accessor.Remove('min'); [void] $accessor.Remove('max') }
    $firstIndex = $split.accessors.Count
    $split.accessors = @($split.accessors) + @($firstAccessor, $restAccessor)
    $firstTriangle = $firstPrimitive | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100
    $remaining = $firstPrimitive | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable -Depth 100
    $firstTriangle.indices = $firstIndex
    $remaining.indices = $firstIndex + 1
    $following = @()
    if ($mesh.primitives.Count -gt 1) { $following = @($mesh.primitives | Select-Object -Skip 1) }
    $mesh.primitives = @($firstTriangle, $remaining) + $following
    $splitMeshes++
}
Write-DiagnosticGlb $split 'diag_material_triangle_split.glb'
$report = @{
    source = [IO.Path]::GetFullPath($source)
    source_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    original_bin_chunks_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($tail))
    shifted_primitives = $primitiveCount
    split_meshes = $splitMeshes
    original_material_0 = ($originalJson | ConvertFrom-Json -AsHashtable -Depth 100).materials[0].name
    shifted_material_1 = $shifted.materials[1].name
}
$outputBytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'diag_material_shift.glb'))
$outputTailOffset = 20 + [BitConverter]::ToUInt32($outputBytes, 12)
$outputTail = [byte[]]::new($outputBytes.Length - $outputTailOffset)
[Buffer]::BlockCopy($outputBytes, $outputTailOffset, $outputTail, 0, $outputTail.Length)
$report.shifted_bin_chunks_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($outputTail))
$report.bin_chunks_identical = $report.original_bin_chunks_sha256 -eq $report.shifted_bin_chunks_sha256
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'diag_material_shift_binary.json') -Encoding utf8NoBOM
$report | ConvertTo-Json -Depth 10 -Compress
