#Requires -Version 7.0
<#
.SYNOPSIS
Reads SQL Server table definitions, allocations, and row payload diagnostics.
.DESCRIPTION
Requires SQL Server 2016 or later and the existing System.Data.SqlClient assembly.
Uses encrypted, certificate-validated connections. Windows/integrated authentication
is the default; Credential selects SQL authentication without a password in the
connection string. Queries are read-only and do not change database/session settings.

Returns one object per existing table. Metadata, Budget, Allocation, Payload and
PhysicalStats have Status, Reason and Data properties. Columns contains catalog
metadata, including nonpersisted computed columns (excluded from storage estimates).
Optional query failures are warnings and Unavailable sections, never zero estimates.

Budget is an uncompressed, all-declared-variable-bytes-inline definition scenario.
It is NOT measured physical storage, a saving guarantee, or a worktable estimate.
It excludes slot arrays, version tags, dropped-column remnants and other internal
record overhead. Unsupported layouts have no budget. MAX string/binary columns
produce a Partial budget: fixed/management bytes remain known, but the declared
variable total, inline total, remaining bytes and fit result are NULL.

Default payload queries inspect at most SampleRows rows with TOP and no ordering;
the cap does not bound bytes, I/O, or runtime. This is not a random or representative
sample, and its maximum is not a table-wide maximum. DATALENGTH includes off-row payload,
NOT physical row bytes or LOB/overflow pointers. Only stored variable string/binary
columns are measured. Per-column averages exclude NULL; row sums treat NULL as zero.
The row maximum is a maximum of sums from individual rows, not a sum of maxima.
Empty sets have RowCount 0 and NULL totals, averages and maxima.
Payload statistics are unavailable when a selected variable column is encrypted or
dynamically masked, even with UNMASK permission; masking can alter derived lengths.

Detailed removes the sample limit and requests DETAILED physical statistics for
the base heap/clustered index. It can be expensive and can block or be blocked.
Allocation counts are approximate, and separate queries are not a consistent snapshot.
No cell values, credentials, or connection strings are written to output.
.PARAMETER Server
SQL Server instance/address, at most 128 characters.
.PARAMETER Database
Exact database name, at most 128 characters.
.PARAMETER Table
Exact unqualified table name, at most 128 characters. Do not supply bracket quoting.
.PARAMETER Schema
Exact schema name; defaults to dbo.
.PARAMETER Credential
SQL authentication credentials; omitted for integrated authentication.
.PARAMETER IncludeRelated
Also inspect exact Table_history and Table_deleted names in the same schema.
.PARAMETER Detailed
Scan all rows for payload aggregates and request DETAILED physical statistics.
.PARAMETER SampleRows
Maximum rows inspected in default mode, from 1 to 100000; defaults to 1000.
.PARAMETER CommandTimeout
Per-command timeout in seconds, from 1 to 600; defaults to 30.
.EXAMPLE
./Get-SqlServerRowDiagnostics.ps1 -Server localhost -Database Pleasanter -Table Results
.EXAMPLE
$credential = Get-Credential
./Get-SqlServerRowDiagnostics.ps1 -Server sql.example.com -Database Pleasanter `
  -Table Results -Credential $credential -IncludeRelated -Detailed
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -le 128 })]
  [string]$Server,

  [Parameter(Mandatory)]
  [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -le 128 })]
  [string]$Database,

  [Parameter(Mandatory)]
  [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -le 128 })]
  [string]$Table,

  [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -le 128 })]
  [string]$Schema = 'dbo',

  [System.Management.Automation.PSCredential]$Credential,
  [switch]$IncludeRelated,
  [switch]$Detailed,

  [ValidateRange(1, 100000)]
  [int]$SampleRows = 1000,

  [ValidateRange(1, 600)]
  [int]$CommandTimeout = 30
)

function New-DiagnosticSection {
  param([string]$Status, [object]$Data = $null, [string]$Reason = $null)
  [pscustomobject]@{ Status = $Status; Reason = $Reason; Data = $Data }
}

function ConvertTo-SqlIdentifier {
  param([string]$Name)
  '[' + $Name.Replace(']', ']]') + ']'
}

function Invoke-DiagnosticQuery {
  param($Connection, [string]$Sql, [hashtable]$Parameters = @{})
  $command = $null
  $reader = $null
  try {
    $command = $Connection.CreateCommand()
    $command.CommandText = $Sql
    $command.CommandTimeout = $CommandTimeout
    foreach ($name in $Parameters.Keys) {
      $value = $Parameters[$name]
      if ($value -is [int]) {
        $parameter = $command.Parameters.Add($name, [System.Data.SqlDbType]::Int)
      }
      else {
        $parameter = $command.Parameters.Add($name, [System.Data.SqlDbType]::NVarChar, 128)
      }
      $parameter.Value = $value
    }
    $reader = $command.ExecuteReader()
    while ($reader.Read()) {
      $row = [ordered]@{}
      for ($i = 0; $i -lt $reader.FieldCount; $i++) {
        $row[$reader.GetName($i)] = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
      }
      [pscustomobject]$row
    }
  }
  finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $command) { $command.Dispose() }
  }
}

function Get-DefinitionBudget {
  param($Metadata, [object[]]$Columns)
  $reasons = [System.Collections.Generic.List[string]]::new()
  if ($Metadata.IsMemoryOptimized) { $reasons.Add('Memory-optimized table.') }
  if ($Metadata.HasColumnstore) { $reasons.Add('Columnstore index present.') }
  if ($Metadata.HasCompression) { $reasons.Add('Base rowstore partition compression enabled.') }
  if ($Metadata.HasNonuniqueClusteredIndex) { $reasons.Add('Nonunique clustered index can add a hidden uniqueifier.') }
  if ($Metadata.IsFileTable) { $reasons.Add('FileTable layout.') }
  if ($Metadata.IsExternal) { $reasons.Add('External table layout.') }
  $stored = @($Columns | Where-Object { -not $_.IsComputed -or $_.IsPersisted })
  if ($stored.Count -lt 1 -or $stored.Count -gt 1024) { $reasons.Add('Unsupported stored column count.') }
  [long]$fixedBytes = 0
  [long]$variableBytes = 0
  [int]$variableCount = 0
  [int]$maxColumnCount = 0
  [int]$bitCount = 0
  foreach ($column in $stored) {
    if ($column.IsSparse -or $column.IsColumnSet) { $reasons.Add('Sparse columns or column set present.') }
    if ($column.IsFileStream) { $reasons.Add('FILESTREAM column present.') }
    if ($null -ne $column.EncryptionType) { $reasons.Add('Encrypted column present.') }
    switch ($column.BaseType) {
      'bit' { $bitCount++; break }
      { $_ -in 'decimal', 'numeric' } {
        $fixedBytes += if ($column.Precision -le 9) { 5 }
        elseif ($column.Precision -le 19) { 9 }
        elseif ($column.Precision -le 28) { 13 }
        else { 17 }
        break
      }
      'date' { $fixedBytes += 3; break }
      { $_ -in 'time', 'datetime2', 'datetimeoffset' } {
        $timeBytes = if ($column.Scale -le 2) { 3 } elseif ($column.Scale -le 4) { 4 } else { 5 }
        $fixedBytes += $timeBytes
        if ($_ -in 'datetime2', 'datetimeoffset') { $fixedBytes += 3 }
        if ($_ -eq 'datetimeoffset') { $fixedBytes += 2 }
        break
      }
      { $_ -in 'tinyint', 'smallint', 'int', 'bigint', 'real', 'float',
        'money', 'smallmoney', 'datetime', 'smalldatetime', 'uniqueidentifier',
        'char', 'nchar', 'binary', 'timestamp' } {
        $fixedBytes += $column.MaxLength
        break
      }
      { $_ -in 'varchar', 'nvarchar', 'varbinary' } {
        $variableCount++
        if ($column.MaxLength -eq -1) { $maxColumnCount++ }
        else { $variableBytes += $column.MaxLength }
        break
      }
      default { $reasons.Add("Unsupported storage type: $($column.BaseType).") }
    }
  }
  if ($reasons.Count -gt 0) {
    return New-DiagnosticSection -Status Unavailable -Reason (($reasons | Select-Object -Unique) -join ' ')
  }
  [long]$bitBytes = [math]::Ceiling($bitCount / 8.0)
  $fixedBytes += $bitBytes
  [long]$nullBytes = 2 + [math]::Ceiling($stored.Count / 8.0)
  [long]$variableMetadata = if ($variableCount -gt 0) { 2 + 2 * $variableCount } else { 0 }
  [long]$managementBytes = 4 + $nullBytes + $variableMetadata
  [long]$fixedAndManagementBytes = $fixedBytes + $managementBytes
  $estimatedBytes = if ($maxColumnCount -eq 0) { $fixedAndManagementBytes + $variableBytes } else { $null }
  $status = if ($maxColumnCount -gt 0) { 'Partial' } else { 'Available' }
  $reason = if ($maxColumnCount -gt 0) {
    'MAX columns have no bounded inline definition budget. FixedAndManagementBytes excludes ALL variable payload and off-row references; the overall row size and fit are unknown.'
  } else { $null }
  New-DiagnosticSection -Status $status -Reason $reason -Data ([pscustomobject]@{
    Scenario = 'Uncompressed declared maximum variable payload entirely in-row'
    StoredColumnCount = $stored.Count
    VariableColumnCount = $variableCount
    MaxColumnCount = $maxColumnCount
    BitBytes = $bitBytes
    FixedBytes = $fixedBytes
    RowHeaderBytes = 4
    NullBitmapBytes = $nullBytes
    VariableMetadataBytes = $variableMetadata
    ManagementBytes = $managementBytes
    FixedAndManagementBytes = $fixedAndManagementBytes
    DeclaredVariablePayloadBytes = if ($maxColumnCount -eq 0) { $variableBytes } else { $null }
    EstimatedInlineBytes = $estimatedBytes
    LimitBytes = 8060
    RemainingBytes = if ($maxColumnCount -eq 0) { 8060 - $estimatedBytes } else { $null }
    InlineScenarioFits = if ($maxColumnCount -eq 0) { $estimatedBytes -le 8060 } else { $null }
    Caveat = 'Definition scenario only: not physical row size or a guarantee that writes/operations succeed. Excludes off-row pointers, version tags, dropped-column remnants, slot arrays and other internal overhead.'
  })
}

function New-PayloadQuery {
  param([string]$QualifiedName, [object[]]$Columns, [bool]$FullScan)
  $lengths = [System.Collections.Generic.List[string]]::new()
  $sums = [System.Collections.Generic.List[string]]::new()
  $aggregates = [System.Collections.Generic.List[string]]::new()
  foreach ($column in $Columns) {
    $alias = ConvertTo-SqlIdentifier "c$($column.ColumnId)"
    $identifier = ConvertTo-SqlIdentifier $column.Name
    $lengths.Add("CONVERT(bigint, DATALENGTH($identifier)) AS $alias")
    $sums.Add("COALESCE($alias, CONVERT(bigint, 0))")
    $id = [int]$column.ColumnId
    $aggregates.Add("COUNT_BIG($alias) AS [NonNull$id], SUM($alias) AS [Total$id], MAX($alias) AS [Maximum$id]")
  }
  $top = if ($FullScan) { '' } else { 'TOP (@SampleRows) ' }
  $lengthSql = if ($lengths.Count) { $lengths -join ",`n    " } else { 'CONVERT(bigint, 0) AS [NoVariablePayload]' }
  $sumSql = if ($sums.Count) { $sums -join ' + ' } else { 'CONVERT(bigint, 0)' }
  $columnSql = if ($aggregates.Count) { ",`n  " + ($aggregates -join ",`n  ") } else { '' }
  @"
WITH [Sample] AS (
  SELECT $top$lengthSql
  FROM $QualifiedName
), [PayloadRows] AS (
  SELECT *, $sumSql AS [RowPayloadBytes] FROM [Sample]
)
SELECT COUNT_BIG(*) AS [RowCount],
  SUM([RowPayloadBytes]) AS [TotalRowPayloadBytes],
  AVG(CONVERT(decimal(38,4), [RowPayloadBytes])) AS [AverageRowPayloadBytes],
  MAX([RowPayloadBytes]) AS [MaxRowPayloadBytes]$columnSql
FROM [PayloadRows];
"@
}

function Get-TableDiagnostics {
  param($Connection, [string]$RequestedTable, [bool]$Required)
  $tableSql = @'
SELECT t.object_id AS ObjectId, s.name AS SchemaName, t.name AS TableName,
  t.is_memory_optimized AS IsMemoryOptimized, t.is_filetable AS IsFileTable,
  t.is_external AS IsExternal,
  CONVERT(bit, CASE WHEN EXISTS (
    SELECT 1 FROM sys.indexes i WHERE i.object_id = t.object_id AND i.type IN (5, 6)
  ) THEN 1 ELSE 0 END) AS HasColumnstore,
  CONVERT(bit, CASE WHEN EXISTS (
    SELECT 1 FROM sys.partitions p
    WHERE p.object_id = t.object_id AND p.index_id IN (0, 1) AND p.data_compression <> 0
  ) THEN 1 ELSE 0 END) AS HasCompression,
  CONVERT(bit, CASE WHEN EXISTS (
    SELECT 1 FROM sys.indexes i
    WHERE i.object_id = t.object_id AND i.index_id = 1 AND i.is_unique = 0
  ) THEN 1 ELSE 0 END) AS HasNonuniqueClusteredIndex,
  (SELECT MIN(i.index_id) FROM sys.indexes i
    WHERE i.object_id = t.object_id AND i.index_id IN (0, 1)) AS BaseIndexId
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = @Schema AND t.name = @Table;
'@
  $columnSql = @'
SELECT c.column_id AS ColumnId, c.name AS Name, ts.name AS TypeSchema,
  ut.name AS ActualType, COALESCE(bt.name, ut.name) AS BaseType,
  c.max_length AS MaxLength, c.precision AS Precision, c.scale AS Scale,
  c.is_nullable AS IsNullable, c.is_computed AS IsComputed,
  CONVERT(bit, COALESCE(cc.is_persisted, 0)) AS IsPersisted,
  c.is_sparse AS IsSparse, c.is_column_set AS IsColumnSet,
  c.is_filestream AS IsFileStream, c.encryption_type AS EncryptionType,
  c.is_hidden AS IsHidden, CONVERT(bit, COALESCE(mc.is_masked, 0)) AS IsMasked
FROM sys.columns c
JOIN sys.types ut ON ut.user_type_id = c.user_type_id
JOIN sys.schemas ts ON ts.schema_id = ut.schema_id
LEFT JOIN sys.types bt ON bt.user_type_id = c.system_type_id AND bt.system_type_id = bt.user_type_id
LEFT JOIN sys.computed_columns cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
LEFT JOIN sys.masked_columns mc ON mc.object_id = c.object_id AND mc.column_id = c.column_id
WHERE c.object_id = @ObjectId
ORDER BY c.column_id;
'@
  try {
    $tables = @(Invoke-DiagnosticQuery $Connection $tableSql @{ '@Schema' = $Schema; '@Table' = $RequestedTable })
    if ($tables.Count -eq 0) {
      if ($Required) { throw 'Base table is absent or its metadata is inaccessible.' }
      Write-Warning "Related table '$RequestedTable' is absent or its metadata is inaccessible; skipped."
      return
    }
    $metadata = $tables[0]
    $columns = @(Invoke-DiagnosticQuery $Connection $columnSql @{ '@ObjectId' = [int]$metadata.ObjectId })
    if ($columns.Count -eq 0) { throw 'No visible column metadata.' }
  }
  catch {
    if ($Required) { throw 'Base table definition unavailable: table not found, metadata permission denied, or unsupported SQL Server version.' }
    Write-Warning "Related table '$RequestedTable' definition unavailable; skipped."
    return
  }
  $qualifiedName = (ConvertTo-SqlIdentifier $metadata.SchemaName) + '.' + (ConvertTo-SqlIdentifier $metadata.TableName)
  $budget = Get-DefinitionBudget $metadata $columns
  $allocationSql = @'
SELECT partition_number AS PartitionNumber, index_id AS IndexId,
  row_count AS ApproximateRows, in_row_used_page_count AS InRowUsedPages,
  row_overflow_used_page_count AS RowOverflowUsedPages,
  lob_used_page_count AS LobUsedPages, used_page_count AS UsedPages,
  reserved_page_count AS ReservedPages
FROM sys.dm_db_partition_stats
WHERE object_id = @ObjectId AND index_id IN (0, 1)
ORDER BY partition_number;
'@
  try {
    $partitions = @(Invoke-DiagnosticQuery $Connection $allocationSql @{ '@ObjectId' = [int]$metadata.ObjectId })
    if ($partitions.Count -eq 0) { throw 'No allocation statistics returned.' }
    $allocation = New-DiagnosticSection -Status Available -Data ([pscustomobject]@{
      Partitions = $partitions
      ApproximateRows = [long]($partitions | Measure-Object ApproximateRows -Sum).Sum
      InRowUsedPages = [long]($partitions | Measure-Object InRowUsedPages -Sum).Sum
      RowOverflowUsedPages = [long]($partitions | Measure-Object RowOverflowUsedPages -Sum).Sum
      LobUsedPages = [long]($partitions | Measure-Object LobUsedPages -Sum).Sum
      UsedPages = [long]($partitions | Measure-Object UsedPages -Sum).Sum
      ReservedPages = [long]($partitions | Measure-Object ReservedPages -Sum).Sum
      PageBytes = 8192
      Scope = 'Base heap/clustered index only; approximate, not a transactionally consistent snapshot.'
    })
  }
  catch {
    $allocation = New-DiagnosticSection -Status Unavailable -Reason 'Allocation statistics unavailable (permission, timeout, unsupported storage, or query failure).'
    Write-Warning "$qualifiedName allocation statistics unavailable."
  }
  $payloadColumns = @($columns | Where-Object {
    (-not $_.IsComputed -or $_.IsPersisted) -and
    $_.BaseType -in 'varchar', 'nvarchar', 'varbinary', 'text', 'ntext', 'image'
  })
  $payloadFailureReason = 'Payload statistics unavailable (permission, timeout, or query failure).'
  try {
    if (@($payloadColumns | Where-Object { $_.IsMasked }).Count) {
      $payloadFailureReason = 'Payload statistics unavailable: dynamic data masking is not supported, even with UNMASK permission, because derived lengths can be masked.'
      throw 'Masked variable columns are not supported.'
    }
    if (@($payloadColumns | Where-Object { $null -ne $_.EncryptionType }).Count) {
      $payloadFailureReason = 'Payload statistics unavailable: encrypted variable columns are not supported.'
      throw 'Encrypted variable columns are not supported.'
    }
    $payloadSql = New-PayloadQuery $qualifiedName $payloadColumns ([bool]$Detailed)
    $payloadParameters = if ($Detailed) { @{} } else { @{ '@SampleRows' = $SampleRows } }
    $payloadRows = @(Invoke-DiagnosticQuery $Connection $payloadSql $payloadParameters)
    if ($payloadRows.Count -ne 1) { throw 'Payload aggregate missing.' }
    $row = $payloadRows[0]
    $columnStats = @(
      foreach ($column in $payloadColumns) {
        $id = $column.ColumnId
        [pscustomobject]@{
          ColumnId = $id
          Name = $column.Name
          NonNullCount = $row."NonNull$id"
          NullCount = $row.RowCount - $row."NonNull$id"
          TotalBytes = $row."Total$id"
          AverageBytes = if ($row."NonNull$id" -gt 0) {
            [decimal]$row."Total$id" / [decimal]$row."NonNull$id"
          } else { $null }
          MaxBytes = $row."Maximum$id"
        }
      }
    )
    $payload = New-DiagnosticSection -Status Available -Data ([pscustomobject]@{
      Mode = if ($Detailed) { 'FullScan' } else { 'BoundedSample' }
      SampleLimit = if ($Detailed) { $null } else { $SampleRows }
      RowCount = $row.RowCount
      TotalRowPayloadBytes = $row.TotalRowPayloadBytes
      AverageRowPayloadBytes = $row.AverageRowPayloadBytes
      MaxRowPayloadBytes = $row.MaxRowPayloadBytes
      Columns = $columnStats
      Scope = 'Stored variable strings/binary only; DATALENGTH includes off-row bytes, not physical row storage. Per-column averages exclude NULL; row sums treat NULL as zero. TOP is unordered, not representative.'
    })
  }
  catch {
    $payload = New-DiagnosticSection -Status Unavailable -Reason $payloadFailureReason
    Write-Warning "$qualifiedName payload statistics unavailable."
  }
  $physical = New-DiagnosticSection -Status NotRequested -Reason 'Use -Detailed to request the expensive physical statistics scan.'
  if ($Detailed) {
    try {
      if ($metadata.IsMemoryOptimized -or $metadata.HasColumnstore -or $metadata.IsExternal -or $null -eq $metadata.BaseIndexId) {
        throw 'Physical rowstore statistics are not supported for this layout.'
      }
      $physicalSql = @'
SELECT partition_number AS PartitionNumber, index_id AS IndexId,
  alloc_unit_type_desc AS AllocationUnitType, page_count AS PageCount,
  record_count AS RecordCount,
  CASE WHEN record_count > 0 THEN avg_record_size_in_bytes END AS AverageRecordBytes,
  CASE WHEN record_count > 0 THEN min_record_size_in_bytes END AS MinRecordBytes,
  CASE WHEN record_count > 0 THEN max_record_size_in_bytes END AS MaxRecordBytes
FROM sys.dm_db_index_physical_stats(DB_ID(), @ObjectId, @IndexId, NULL, 'DETAILED')
WHERE index_id IN (0, 1) AND index_level = 0 AND alloc_unit_type_desc = 'IN_ROW_DATA'
ORDER BY partition_number;
'@
      $physicalRows = @(Invoke-DiagnosticQuery $Connection $physicalSql @{
        '@ObjectId' = [int]$metadata.ObjectId
        '@IndexId' = [int]$metadata.BaseIndexId
      })
      if ($physicalRows.Count -eq 0) { throw 'No physical statistics returned.' }
      $physical = New-DiagnosticSection -Status Available -Data ([pscustomobject]@{
        Mode = 'DETAILED'
        Partitions = $physicalRows
        Scope = 'Base heap/clustered index leaf IN_ROW_DATA records only; excludes off-row payload. RecordCount is not necessarily the logical row count.'
      })
    }
    catch {
      $physical = New-DiagnosticSection -Status Unavailable -Reason 'Physical statistics unavailable (permission, timeout, unsupported storage, or query failure).'
      Write-Warning "$qualifiedName physical statistics unavailable."
    }
  }
  [pscustomobject]@{
    Server = $Server
    Database = $Database
    Schema = $metadata.SchemaName
    Table = $metadata.TableName
    ObjectId = $metadata.ObjectId
    Metadata = New-DiagnosticSection -Status Available -Data $metadata
    Columns = $columns
    Budget = $budget
    Allocation = $allocation
    Payload = $payload
    PhysicalStats = $physical
  }
}

try {
  $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
}
catch {
  throw 'System.Data.SqlClient is required but unavailable in this PowerShell installation.'
}
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = $Database
$builder['Encrypt'] = $true
$builder['TrustServerCertificate'] = $false
$builder['Connect Timeout'] = 15
$builder['Persist Security Info'] = $false
$builder['Application Name'] = 'Get-SqlServerRowDiagnostics'
$builder['Integrated Security'] = $null -eq $Credential
$connection = $null
$password = $null
try {
  $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
  if ($null -ne $Credential) {
    $password = $Credential.Password.Copy()
    $password.MakeReadOnly()
    $connection.Credential = [System.Data.SqlClient.SqlCredential]::new($Credential.UserName, $password)
  }
  try { $connection.Open() }
  catch { throw 'SQL Server connection failed. Check connectivity, authentication, and the server certificate trust/name; connection details are not logged.' }
  Get-TableDiagnostics $connection $Table $true
  if ($IncludeRelated) {
    foreach ($suffix in '_history', '_deleted') {
      $related = $Table + $suffix
      if ($related.Length -gt 128) {
        Write-Warning "Related table name exceeds 128 characters for suffix '$suffix'; skipped."
        continue
      }
      Get-TableDiagnostics $connection $related $false
    }
  }
}
finally {
  if ($null -ne $connection) { $connection.Dispose() }
  if ($null -ne $password) { $password.Dispose() }
}
