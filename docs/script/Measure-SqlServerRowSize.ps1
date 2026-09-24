#Requires -Version 7.0
<#
.SYNOPSIS
Estimates an uncompressed SQL Server row before off-row storage.
.DESCRIPTION
Supply physical column counts, including standard columns, for one table.
Num columns use decimal(NumPrecision, s); Date columns use datetime (8 bytes).
CheckCount includes ALL bit columns, packed together.
String byte counts are per column (DATALENGTH), not character counts or file sizes.
When a string count is positive, its byte estimate must be supplied explicitly.
OtherFixedBytes and OtherVariableBytes are totals, excluding row overhead.
NULL fixed columns still consume space. NULL strings have zero payload.
This assumes all variable payloads stay in-row. It does not predict ROW_OVERFLOW,
LOB references, compression, versioning metadata, or sort worktable sizes.
Exceeding 8060 means this inline scenario does not fit, not that saving must fail.
.EXAMPLE
./Measure-SqlServerRowSize.ps1 -NumCount 10 -DateCount 10 -CheckCount 8 `
  -ClassCount 20 -ClassBytesPerColumn 40 `
  -DescriptionCount 2 -DescriptionBytesPerColumn 200 `
  -AttachmentCount 1 -AttachmentBytesPerColumn 300
#>
[CmdletBinding()]
param(
  [ValidateRange(0, 1024)]
  [int]$NumCount = 0,

  [ValidateRange(1, 38)]
  [int]$NumPrecision = 18,

  [ValidateRange(0, 1024)]
  [int]$DateCount = 0,

  [ValidateRange(0, 1024)]
  [int]$CheckCount = 0,

  [ValidateRange(0, 1024)]
  [int]$ClassCount = 0,

  [ValidateRange(0, 8000)]
  [long]$ClassBytesPerColumn = 0,

  [ValidateRange(0, 1024)]
  [int]$DescriptionCount = 0,

  [ValidateRange(0, 2147483647)]
  [long]$DescriptionBytesPerColumn = 0,

  [ValidateRange(0, 1024)]
  [int]$AttachmentCount = 0,

  [ValidateRange(0, 2147483647)]
  [long]$AttachmentBytesPerColumn = 0,

  [ValidateRange(0, 1024)]
  [int]$OtherFixedCount = 0,

  [ValidateRange(0, 2147483647)]
  [long]$OtherFixedBytes = 0,

  [ValidateRange(0, 1024)]
  [int]$OtherVariableCount = 0,

  [ValidateRange(0, 2147483647)]
  [long]$OtherVariableBytes = 0
)

$groups = @(
  @{ Count = $ClassCount; Bytes = $ClassBytesPerColumn; Parameter = 'ClassBytesPerColumn' }
  @{ Count = $DescriptionCount; Bytes = $DescriptionBytesPerColumn; Parameter = 'DescriptionBytesPerColumn' }
  @{ Count = $AttachmentCount; Bytes = $AttachmentBytesPerColumn; Parameter = 'AttachmentBytesPerColumn' }
  @{ Count = $OtherFixedCount; Bytes = $OtherFixedBytes; Parameter = 'OtherFixedBytes' }
  @{ Count = $OtherVariableCount; Bytes = $OtherVariableBytes; Parameter = 'OtherVariableBytes' }
)
foreach ($group in $groups) {
  if ($group.Count -gt 0 -and -not $PSBoundParameters.ContainsKey($group.Parameter)) {
    throw "Specify -$($group.Parameter) explicitly, including 0 for an empty variable payload."
  }
  if ($group.Count -eq 0 -and $group.Bytes -ne 0) {
    throw "$($group.Parameter) requires a positive column count."
  }
}
if ($OtherFixedCount -gt 0 -and $OtherFixedBytes -lt $OtherFixedCount) {
  throw 'OtherFixedBytes must include storage for each fixed column; count all bit columns in CheckCount.'
}

$variableCount = $ClassCount + $DescriptionCount + $AttachmentCount + $OtherVariableCount
$columnCount = $NumCount + $DateCount + $CheckCount + $OtherFixedCount + $variableCount
if ($columnCount -lt 1 -or $columnCount -gt 1024) {
  throw 'Specify between 1 and 1024 physical columns for one ordinary table.'
}

$decimalBytes = if ($NumPrecision -le 9) { 5 }
elseif ($NumPrecision -le 19) { 9 }
elseif ($NumPrecision -le 28) { 13 }
else { 17 }

[long]$bitBytes = [math]::Ceiling($CheckCount / 8.0)
[long]$fixedBytes = $NumCount * $decimalBytes + $DateCount * 8 + $bitBytes + $OtherFixedBytes
[long]$nullBitmapBytes = 2 + [math]::Ceiling($columnCount / 8.0)
[long]$variableMetadataBytes = if ($variableCount -gt 0) { 2 + 2 * $variableCount } else { 0 }
[long]$managementBytes = 4 + $nullBitmapBytes + $variableMetadataBytes
[long]$variableBytes = $ClassCount * $ClassBytesPerColumn +
  $DescriptionCount * $DescriptionBytesPerColumn +
  $AttachmentCount * $AttachmentBytesPerColumn + $OtherVariableBytes
[long]$estimatedBytes = $fixedBytes + $managementBytes + $variableBytes

Write-Warning 'Inline estimate only, not a storage guarantee. Include standard columns; verify actual DDL, off-row storage and operations.'
[pscustomobject]@{
  Scenario = 'All variable payloads in-row'
  ColumnCount = $columnCount
  VariableColumnCount = $variableCount
  DecimalBytesPerColumn = $decimalBytes
  BitBytes = $bitBytes
  FixedBytes = $fixedBytes
  RowHeaderBytes = 4
  NullBitmapBytes = $nullBitmapBytes
  VariableMetadataBytes = $variableMetadataBytes
  ManagementBytes = $managementBytes
  VariablePayloadBytes = $variableBytes
  EstimatedInlineBytes = $estimatedBytes
  LimitBytes = 8060
  RemainingBytes = 8060 - $estimatedBytes
  InlineScenarioFits = $estimatedBytes -le 8060
}
