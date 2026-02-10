# プリザンター CodeDefiner データベース作成・更新ロジック調査

CodeDefiner がデータベースを作成・更新する処理フローと、RDBMS 毎の差違吸収メカニズムについて調査した。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [CodeDefiner の概要](#codedefiner-の概要)
    - [起動と主要コマンド](#起動と主要コマンド)
    - [主要オプション](#主要オプション)
- [データベース構成処理の全体フロー](#データベース構成処理の全体フロー)
    - [フェーズ別の詳細](#フェーズ別の詳細)
- [RDBMS差違吸収のアーキテクチャ](#rdbms差違吸収のアーキテクチャ)
    - [層1: Abstract Factory パターン（`ISqlObjectFactory`）](#層1-abstract-factory-パターンisqlobjectfactory)
    - [層2: SQL定義ファイル（RDBMS毎のSQLテンプレート）](#層2-sql定義ファイルrdbms毎のsqlテンプレート)
    - [層3: コード内の分岐処理](#層3-コード内の分岐処理)
    - [データ型の変換](#データ型の変換)
    - [RDBMS固有の設定値（ISqlDefinitionSetting）](#rdbms固有の設定値isqldefinitionsetting)
    - [SQL方言の差異（ISqls）](#sql方言の差異isqls)
- [接続方式と権限レベル](#接続方式と権限レベル)
- [マイグレーションチェックモード](#マイグレーションチェックモード)
- [テーブルの追加・削除に関するロジック](#テーブルの追加削除に関するロジック)
    - [処理対象テーブル一覧の決定](#処理対象テーブル一覧の決定)
    - [テーブルの新規追加](#テーブルの新規追加)
    - [テーブルの削除（未実装）](#テーブルの削除未実装)
    - [テーブルバリエーションの生成](#テーブルバリエーションの生成)
    - [Quartz テーブルの条件付きスキップ](#quartz-テーブルの条件付きスキップ)
- [テーブル構造変更の判断ロジック](#テーブル構造変更の判断ロジック)
    - [全体の判断フロー](#全体の判断フロー)
    - [HasChanges の判定構造](#haschanges-の判定構造)
    - [(1) カラム数の比較](#1-カラム数の比較)
    - [(2) カラム属性の比較（Columns.HasChanges）](#2-カラム属性の比較columnshaschanges)
    - [(3) デフォルト値制約の比較（Constraints.HasChanges）](#3-デフォルト値制約の比較constraintshaschanges)
    - [(4) インデックス構成の比較（Indexes.HasChanges）](#4-インデックス構成の比較indexeshaschanges)
    - [カラムフィルタリング条件](#カラムフィルタリング条件)
    - [マイグレーションの実行方式](#マイグレーションの実行方式)
- [テーブル定義ファイル（Definition_Column）](#テーブル定義ファイルdefinition_column)
    - [格納場所](#格納場所)
    - [ファイル命名規則](#ファイル命名規則)
    - [テーブル一覧と定義ファイル数](#テーブル一覧と定義ファイル数)
    - [JSON ファイルの構造](#json-ファイルの構造)
    - [読み込みの仕組み](#読み込みの仕組み)
- [結論](#結論)
- [関連ソースコード](#関連ソースコード)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

---

## 調査情報

| 調査日        | リポジトリ | ブランチ           | タグ/バージョン | コミット    | 備考     |
| ------------- | ---------- | ------------------ | --------------- | ----------- | -------- |
| 2026年2月10日 | Pleasanter | Pleasanter_1.5.0.0 |                 | `34f162a43` | 初回調査 |

## 調査目的

CodeDefiner はプリザンターの初期セットアップおよびバージョンアップ時にデータベーススキーマを管理するツールである。
データベースの新規作成・テーブルのマイグレーション・インデックス管理・権限設定などがどのようなロジックで実行されるのか、
また SQL Server / PostgreSQL / MySQL の3種類の RDBMS を
1つのコードベースでどのように差違吸収しているのかを明らかにする。

---

## CodeDefiner の概要

### 起動と主要コマンド

CodeDefiner はコマンドラインツール（`Implem.CodeDefiner`）として動作する。`Starter.Main()` がエントリーポイントであり、第一引数でアクションを指定する。

**ファイル**: `Implem.CodeDefiner/Starter.cs`

| アクション    | 説明                                                  |
| ------------- | ----------------------------------------------------- |
| `rds`         | DB構成 + DefinitionAccessorコード生成 + MVCコード生成 |
| `_rds`        | DB構成のみ（コード生成なし）                          |
| `_def`        | DefinitionAccessorコード生成のみ                      |
| `def`         | DefinitionAccessorコード生成 + MVCコード生成          |
| `mvc`         | MVCコード生成のみ                                     |
| `backup`      | ソリューションバックアップ                            |
| `migrate`     | 他DBMSからの移行（SQL Server → PostgreSQL/MySQLなど） |
| `trial`       | トライアルライセンス用DB構成                          |
| `ConvertTime` | 日時データの変換                                      |
| `merge`       | パラメータファイルのマージ（バージョンアップ時）      |

### 主要オプション

| オプション | 説明                                           |
| ---------- | ---------------------------------------------- |
| `/p`       | パラメータファイルのパス指定                   |
| `/f`       | カラム削減チェックを強制スキップ               |
| `/y`       | ユーザー入力確認をスキップ                     |
| `/c`       | マイグレーションチェックモード（変更確認のみ） |
| `/l`       | 言語設定                                       |
| `/z`       | タイムゾーン設定                               |
| `/s`       | SA パスワード設定                              |
| `/r`       | ランダムパスワード設定                         |

---

## データベース構成処理の全体フロー

`rds` または `_rds` コマンド実行時に、以下の順序でデータベース構成が行われる。

```mermaid
flowchart TD
    A[Starter.ConfigureDatabase] --> B{RdsProvider == Local?}
    B -->|Yes| C[UsersConfigurator.KillTask]
    C --> D[RdsConfigurator.Configure]
    D --> E[UsersConfigurator.Configure]
    E --> F[SchemaConfigurator.Configure]
    B -->|No| G[CheckColumnsShrinkage]
    F --> G
    G -->|OK| H[TablesConfigurator.Configure]
    H --> I{RdsProvider == Local?}
    I -->|Yes| J[PrivilegeConfigurator.Configure]
    I -->|No| K[完了]
    J --> K
    G -->|NG| L[中断]
```

### フェーズ別の詳細

各Configuratorクラスは `Implem.CodeDefiner/Functions/Rds/` に配置されている。

#### フェーズ1: プロセス停止（KillTask）

**クラス**: `UsersConfigurator.KillTask()`

データベースに接続中のプロセスを切断し、スキーマ変更の競合を防止する。

#### フェーズ2: データベース作成/更新（RdsConfigurator）

**クラス**: `RdsConfigurator`（`Functions/Rds/RdsConfigurator.cs`）

```mermaid
flowchart TD
    A[RdsConfigurator.Configure] --> B{DB存在チェック<br/>Exists}
    B -->|存在しない| C[CreateDatabase]
    B -->|存在する| D[UpdateDatabase]
    C --> E[CreateDatabase SQL実行]
    C --> F[CreateUserForPostgres SQL実行]
    C --> G[CreateDatabaseForPostgres SQL実行]
    D --> H[CreateUserForPostgres SQL実行]
    D --> I[ChangeDatabaseOwnerForPostgres SQL実行]
```

- **Exists()**: `Def.Sql.ExistsDatabase` を実行し、データベースの存在を確認する。同時にスキーマの存在もチェックし、`SchemaName` と `IsCreatingDb` フラグを設定する。
- **CreateDatabase()**: SA権限（`SqlIoBySa`）でデータベース作成 → ユーザー作成 → PostgreSQL固有のDB設定を実行する。
- **UpdateDatabase()**: 既存DBに対して、ユーザー情報の更新とオーナー変更を実行する。

#### フェーズ3: ユーザー作成/更新（UsersConfigurator）

**クラス**: `UsersConfigurator`（`Functions/Rds/UsersConfigurator.cs`）

Owner ユーザーと一般ユーザーの2つのロールを作成・更新する。

```mermaid
flowchart TD
    A[UsersConfigurator.Configure] --> B[OwnerConnectionString]
    A --> C[UserConnectionString]
    B --> D{ユーザー存在?}
    C --> D
    D -->|Yes| E[AlterLoginRole<br/>パスワード更新]
    D -->|No| F{Owner?}
    F -->|Yes| G[CreateLoginAdmin]
    F -->|No| H[CreateLoginUser]
```

- ユーザー名の末尾が `_Owner` かどうかで、管理者用（`CreateLoginAdmin`）と一般用（`CreateLoginUser`）を使い分ける。
- MySQL の場合は `MySqlConnectingHost` によるホスト指定にも対応する。

#### フェーズ4: スキーマ設定（SchemaConfigurator）

**クラス**: `SchemaConfigurator`（`Functions/Rds/SchemaConfigurator.cs`）

- **新規作成時**（`IsCreatingDb == true`）: `CreateSchema` SQL を実行。PostgreSQL ではスキーマ作成、`pg_trgm` / `pgcrypto` 拡張のインストールが行われる。
- **更新時**: `GrantDatabaseForPostgres` SQL を実行。既存スキーマに対する権限付与のみ。

#### フェーズ5: カラム削減チェック（CheckColumnsShrinkage）

Issues テーブルと Results テーブルに対し、定義ファイルのカラム一覧と現在DBのカラム一覧を比較する。カラムが減少している場合は、データ損失の危険があるため処理を停止する（`/f` オプションで強制スキップ可能）。

#### フェーズ6: テーブル構成（TablesConfigurator）

**クラス**: `TablesConfigurator`（`Functions/Rds/TablesConfigurator.cs`）

全テーブルに対して以下を実行する。

```mermaid
flowchart TD
    A[TablesConfigurator.Configure] --> B[Def.TableNameCollection<br/>全テーブル名取得]
    B --> C[各テーブルに対してConfigureTableSet]
    C --> D["通常テーブル: sourceTableName"]
    C --> E["削除テーブル: sourceTableName_deleted"]
    C --> F["履歴テーブル: sourceTableName_history"]
    D --> G[ConfigureTablePart]
    E --> G
    F --> G
    G --> H{テーブル存在?}
    H -->|No| I[Tables.CreateTable]
    H -->|Yes| J{変更あり?}
    J -->|Yes| K[Tables.MigrateTable]
    J -->|No| L[スキップ]
```

##### テーブル作成（CreateTable）

**ファイル**: `Functions/Rds/Parts/Tables.cs`

`SqlStatement` を構築し、以下のプレースホルダを順番に置換する:

1. **`#Columns#`**: カラム定義（型、サイズ、NULL制約、IDENTITY）
2. **`#Pks#`**: 主キー制約
3. **`#Defaults#`**（SQLServer/PostgreSQL）/ **`#ModifyColumn#`**（MySQL）: デフォルト値制約
4. **`#DropConstraint#`**: インデックスの再作成
5. **`#TableName#`**: テーブル名

##### テーブルマイグレーション（MigrateTable）

テーブル構造に変更がある場合のマイグレーション手順:

```mermaid
sequenceDiagram
    participant CD as CodeDefiner
    participant DB as Database
    CD->>DB: (1) 新構造のテンポラリテーブル作成<br/>（タイムスタンプ_テーブル名）
    CD->>DB: (2) 旧テーブルからデータ移行<br/>INSERT INTO...SELECT FROM
    CD->>DB: (3) 旧テーブルをリネーム<br/>→ _Migrated_タイムスタンプ_テーブル名
    CD->>DB: (4) 新テーブルをリネーム<br/>→ 元のテーブル名
    Note over CD,DB: IDENTITYカラムがある場合は<br/>追加処理あり（RDBMS毎に異なる）
```

**変更検知のロジック**（`Tables.HasChanges`）:

| チェック項目       | 検知方法                                                       |
| ------------------ | -------------------------------------------------------------- |
| カラム数の変化     | 定義カラム数 vs 現行カラム数                                   |
| カラム名の変化     | `ColumnName` の一致確認                                        |
| データ型の変化     | `TypeName`（`ConvertBack` で正規化して比較）                   |
| カラムサイズの変化 | `ColumnSize.HasChanges`（RDBMS毎に専用ロジック）               |
| NULL制約の変化     | `is_nullable` の一致確認                                       |
| IDENTITY属性の変化 | `is_identity` の一致確認（`_history`/`_deleted` テーブル除外） |
| デフォルト値の変化 | `Constraints.HasChanges`                                       |
| インデックスの変化 | `Indexes.HasChanges`                                           |

##### フルテキストインデックス

テーブル構成完了後、RDBMS毎に異なるフルテキストインデックスを設定する:

| RDBMS      | 方式                                            | 対象テーブル    |
| ---------- | ----------------------------------------------- | --------------- |
| SQLServer  | `FULLTEXT CATALOG` + `FULLTEXT INDEX`（日本語） | Items, Binaries |
| PostgreSQL | `GIN` インデックス（`pg_trgm` 拡張）            | Items           |
| MySQL      | `FULLTEXT INDEX`（`ngram` パーサー）            | Items           |

#### フェーズ7: 権限設定（PrivilegeConfigurator）

**クラス**: `PrivilegeConfigurator`（`Functions/Rds/PrivilegeConfigurator.cs`）

Owner ユーザーと一般ユーザーに対して、RDBMS毎の権限付与を実行する。

| ユーザー種別 | SQLServer              | PostgreSQL                    | MySQL                               |
| ------------ | ---------------------- | ----------------------------- | ----------------------------------- |
| Owner        | `db_owner` ロール付与  | `ALTER ROLE` のみ             | CREATE, ALTER, INDEX, DROP等のGRANT |
| User         | `db_datareader/writer` | テーブル単位のSELECT/INSERT等 | SELECT, INSERT, UPDATE, DELETE等    |

---

## RDBMS差違吸収のアーキテクチャ

プリザンターは3つの RDBMS（SQL Server, PostgreSQL, MySQL）をサポートしており、以下の3層構造で差違を吸収している。

### 層1: Abstract Factory パターン（`ISqlObjectFactory`）

**ファイル**: `Rds/Implem.IRds/ISqlObjectFactory.cs`, `Implem.Factory/RdsFactory.cs`

```mermaid
classDiagram
    class ISqlObjectFactory {
        <<interface>>
        +CreateSqlCommand() ISqlCommand
        +CreateSqlConnection(string) ISqlConnection
        +CreateSqlParameter() ISqlParameter
        +CreateSqlDataAdapter(ISqlCommand) ISqlDataAdapter
        +Sqls ISqls
        +SqlCommandText ISqlCommandText
        +SqlResult ISqlResult
        +SqlErrors ISqlErrors
        +SqlDataType ISqlDataType
        +SqlDefinitionSetting ISqlDefinitionSetting
    }
    class SqlServerObjectFactory {
        SqlServerSqls sqls
        SqlServerDataType sqlDataTypes
        SqlServerDefinitionSetting sqlDefinitionSetting
    }
    class PostgreSqlObjectFactory {
        PostgreSqlSqls sqls
        PostgreSqlDataType sqlDataTypes
        PostgreSqlDefinitionSetting sqlDefinitionSetting
    }
    class MySqlObjectFactory {
        MySqlSqls sqls
        MySqlDataType sqlDataTypes
        MySqlDefinitionSetting sqlDefinitionSetting
    }
    ISqlObjectFactory <|.. SqlServerObjectFactory
    ISqlObjectFactory <|.. PostgreSqlObjectFactory
    ISqlObjectFactory <|.. MySqlObjectFactory
```

`RdsFactory.Create()` が `Parameters.Rds.Dbms` の値（`"SQLServer"`, `"PostgreSQL"`, `"MySQL"`）に応じて適切なファクトリを生成する。

### 層2: SQL定義ファイル（RDBMS毎のSQLテンプレート）

**ディレクトリ**: `Implem.Pleasanter/App_Data/Definitions/Sqls/{SQLServer|PostgreSQL|MySQL}/`

各ディレクトリに同名の `.sql` ファイルが55個配置されており、RDBMS固有のSQL構文が記述されている。`Def.Sql.*` フィールドに読み込まれ、`#プレースホルダ#` を `String.Replace()` で実行時に置換する方式をとる。

#### 代表的なSQL定義の差異

| SQL定義                    | SQLServer                                          | PostgreSQL                                               | MySQL                                            |
| -------------------------- | -------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------ |
| `CreateDatabase`           | `CREATE DATABASE ... COLLATE japanese_90_ci_as_ks` | `SELECT 1`（ダミー）→ `CreateDatabaseForPostgres` で実行 | `CREATE DATABASE ... COLLATE utf8mb4_general_ci` |
| `CreateTable`              | `"dbo"."#TableName#"` スキーマ付き                 | `"#TableName#"` スキーマなし                             | `"#TableName#"` スキーマなし                     |
| `ExistsDatabase`           | `sys.databases`                                    | `pg_database`                                            | `SHOW DATABASES`                                 |
| `ExistsTable`              | `dbo.sysobjects`                                   | `information_schema.tables`（スキーマ指定あり）          | `information_schema.tables`                      |
| `MigrateTableWithIdentity` | `SET IDENTITY_INSERT ON/OFF`                       | `setval(pg_get_serial_sequence(...))`                    | 追加処理なし                                     |
| `CreateFullText`           | `FULLTEXT CATALOG` + `FULLTEXT INDEX`              | `GIN` + `pg_trgm`                                        | `FULLTEXT INDEX` + `ngram`                       |
| `ExistsUser`               | `sysusers`                                         | `pg_user`                                                | `mysql.user`（ホスト指定あり）                   |
| `CreateLoginAdmin`         | `CREATE LOGIN` + `db_owner`                        | 空（`CreateUserForPostgres` で一括処理）                 | `CREATE USER` + `GRANT`                          |

### 層3: コード内の分岐処理

SQL定義ファイルだけではカバーできない差異は、C# コード内で `Parameters.Rds.Dbms` に基づく `switch` 文で分岐する。

#### カラム作成（Columns.CreateColumn）

**ファイル**: `Functions/Rds/Parts/Columns.cs`

```csharp
switch (Parameters.Rds.Dbms)
{
    case "SQLServer":
        // Columns.Sql_Create()
        break;
    case "PostgreSQL":
        // PostgreSqlColumns.Sql_Create()
        break;
    case "MySQL":
        // MySqlColumns.Sql_Create()
        break;
}
```

#### インデックス構成（Indexes.IndexInfoCollection）

**ファイル**: `Functions/Rds/Parts/Indexes.cs`

SQLServer / PostgreSQL は共通ロジックを使用し、MySQL のみ `MySqlIndexes` クラスで別処理を行う。

#### デフォルト値制約（Constraints.CreateDefault）

**ファイル**: `Functions/Rds/Parts/Constraints.cs`

SQLServer / PostgreSQL は `CREATE DEFAULT` 方式、MySQL は `MODIFY COLUMN` 方式で処理する。

#### カラムサイズ比較

SQLServer / PostgreSQL は `ColumnSize.HasChanges()`、MySQL は `MySqlColumnSize.HasChanges()` を使用する。

### データ型の変換

**インターフェース**: `ISqlDataType`

CodeDefiner の定義ファイルは SQL Server 形式のデータ型名で統一されており、
PostgreSQL / MySQL では `ISqlDataType.Convert()` でテーブル作成時に変換し、
`ConvertBack()` で現行DB情報との比較時に逆変換する。

| 定義上の型名（SQLServer基準） | PostgreSQL 変換先 | MySQL 変換先  |
| ----------------------------- | ----------------- | ------------- |
| `nchar`                       | `char`            | `char`        |
| `nvarchar(max)`               | `text`            | `longtext`    |
| `nvarchar`                    | `varchar`         | `varchar`     |
| `bit`                         | `boolean`         | `tinyint(1)`  |
| `varbinary`                   | `bytea`           | `blob`        |
| `image`                       | `bytea`           | `longblob`    |
| `datetime`                    | `timestamp(3)`    | `datetime(3)` |

### RDBMS固有の設定値（ISqlDefinitionSetting）

| 設定項目                                 | SQLServer     | PostgreSQL | MySQL     |
| ---------------------------------------- | ------------- | ---------- | --------- |
| `IdentifierPostfixLength`                | 64            | 32         | 32        |
| `NationalCharacterStoredSizeCoefficient` | 2             | 4          | 4         |
| `ReducedVarcharLength`                   | 0             | 0          | 760       |
| `SchemaName`（可変）                     | 空（dbo固定） | 動的設定   | 空        |
| `IsCreatingDb`（可変）                   | false固定     | 動的設定   | false固定 |

### SQL方言の差異（ISqls）

| 項目         | SQLServer        | PostgreSQL                         | MySQL                  |
| ------------ | ---------------- | ---------------------------------- | ---------------------- |
| Boolean真    | `1`              | `true`                             | `1`                    |
| Boolean偽    | `0`              | `false`                            | `0`                    |
| 現在日時     | `getdate()`      | `CURRENT_TIMESTAMP`                | `CURRENT_TIMESTAMP(3)` |
| LIKE演算子   | `like`           | `ilike`（大小無視）                | `like`                 |
| NULL置換関数 | `isnull`         | `coalesce`                         | `ifnull`               |
| IDENTITY生成 | `identity(n, 1)` | `generated by default as identity` | なし（AUTO_INCREMENT） |

---

## 接続方式と権限レベル

CodeDefiner は2種類の接続を使い分ける。

| 接続方式           | メソッド             | 接続文字列                             | 用途                           |
| ------------------ | -------------------- | -------------------------------------- | ------------------------------ |
| SA接続             | `Def.SqlIoBySa()`    | `Parameters.Rds.SaConnectionString`    | DB作成、ユーザー作成、権限設定 |
| Admin（Owner）接続 | `Def.SqlIoByAdmin()` | `Parameters.Rds.OwnerConnectionString` | テーブル操作、マイグレーション |

`RdsProvider == "Local"` の場合のみ、DB作成・ユーザー管理・スキーマ設定・権限設定が実行される。Azure Database 等のマネージドサービス（`RdsProvider != "Local"`）では、これらのフェーズはスキップされ、テーブル構成のみが実行される。

---

## マイグレーションチェックモード

`_rds /c` コマンドで実行されるマイグレーションチェックモードでは、
実際のDB変更を行わず、以下の確認のみを行う:

1. データベースの存在確認
2. テーブル構成の変更有無の確認
   （`TablesConfigurator.Configure(checkMigration: true)`）
3. `checkMigration == true` の場合、
   `CreateTable` / `MigrateTable` は実際のSQL実行をスキップする

---

## テーブルの追加・削除に関するロジック

### 処理対象テーブル一覧の決定

CodeDefiner が管理するテーブル一覧はハードコーディングされておらず、
`Def.TableNameCollection()` によりカラム定義ファイルから動的に導出される。

**ファイル**: `Implem.DefinitionAccessor/Def.cs`

```csharp
public static IEnumerable<string> TableNameCollection(...)
{
    return ColumnDefinitionCollection
        .Where(o => !o.ModelName.StartsWith("_Base"))  // ベース定義を除外
        .OrderBy(o => o["No"])
        .Select(o => o.TableName)
        .Distinct();  // テーブル名の重複排除
}
```

つまり、`Definition_Column/` に `{テーブル名}_{カラム名}.json` を
追加すれば新テーブルが自動的に管理対象となり、
削除すればテーブルが管理対象から外れる
（ただし実DBからの削除は行われない — 後述）。

### テーブルの新規追加

`ConfigureTablePart()` で `Tables.Exists()` が `false` を返した場合、
`Tables.CreateTable()` が呼び出されてテーブルが新規作成される。

```mermaid
flowchart TD
    A["TablesConfigurator.Configure()"] --> B["Def.TableNameCollection()<br/>定義ファイルからテーブル一覧を取得"]
    B --> C["テーブル毎に ConfigureTableSet()"]
    C --> D{"Tables.Exists()?<br/>実DBにテーブルが存在する?"}
    D -->|No| E["Tables.CreateTable()<br/>テーブル新規作成"]
    D -->|Yes| F["HasChanges 判定へ"]
```

新規テーブル追加時に必要なのは定義ファイルの配置のみであり、
CodeDefiner 側のコード変更は不要である。

### テーブルの削除（未実装）

CodeDefiner には**テーブルを削除するロジックが存在しない**。
定義ファイルからテーブル定義を削除しても、
`TableNameCollection()` から除外されるだけで、
実DB上のテーブルは残り続ける。

`DROP TABLE` に相当する SQL テンプレートも存在しない。

同様に、マイグレーション時の旧テーブルも削除されない。
旧テーブルは `_Migrated_{datetime}_{テーブル名}` にリネームされ、
DB上に保持される。

| RDBMS      | リネーム方法                                    |
| ---------- | ----------------------------------------------- |
| SQL Server | `sp_rename N'{旧}', N'_Migrated_{新}'`          |
| PostgreSQL | `ALTER TABLE "{旧}" RENAME TO "_Migrated_{新}"` |
| MySQL      | `ALTER TABLE "{旧}" RENAME TO "_Migrated_{新}"` |

### テーブルバリエーションの生成

1つの定義テーブルに対して、最大3種類の物理テーブルが作成される。

**ファイル**: `Functions/Rds/TablesConfigurator.cs`（`ConfigureTableSet`）

| バリエーション         | 物理テーブル名         | 作成条件                         |
| ---------------------- | ---------------------- | -------------------------------- |
| 通常テーブル           | `{テーブル名}`         | 常に作成                         |
| 削除レコード用テーブル | `{テーブル名}_deleted` | `History > 0` のカラムがある場合 |
| 履歴テーブル           | `{テーブル名}_history` | `History > 0` のカラムがある場合 |

`_deleted` テーブルには通常テーブルと同じカラム構成が使用される。
`_history` テーブルには `History > 0` のカラムのみが使用され、
`History` プロパティの値順にソートされる。

`_history` / `_deleted` テーブルでは IDENTITY 属性が付与されない
（`noIdentity: true`）。

### Quartz テーブルの条件付きスキップ

Quartz.NET のスケジューラ用テーブル（`QRTZ_*`）は、
クラスタリング設定に基づいて作成がスキップされる。

**ファイル**: `Functions/Rds/TablesConfigurator.cs`

```csharp
private static bool IsSkipQuartzTable(string tableName)
{
    var enableClustering =
        Parameters.Quartz?.Clustering?.Enabled ?? false;
    return !enableClustering && Tables.IsQuartzTable(tableName);
}
```

| 条件                                      | 動作                      |
| ----------------------------------------- | ------------------------- |
| `Quartz.Clustering.Enabled == true`       | Quartz テーブルを作成     |
| `Quartz.Clustering.Enabled == false/null` | Quartz テーブルをスキップ |

また、PostgreSQL では Quartz テーブルのテーブル名・カラム名が
小文字に正規化される（`NormalizeTableName` / `ColumnName.ToLower()`）。

---

## テーブル構造変更の判断ロジック

### 全体の判断フロー

`ConfigureTablePart()` がテーブル単位の作成・更新を判断する。
テーブルは `{テーブル名}` / `{テーブル名}_deleted` / `{テーブル名}_history`
の最大3種類のバリエーションに対してそれぞれ判定される。

**ファイル**: `Functions/Rds/TablesConfigurator.cs`

```mermaid
flowchart TD
    A["ConfigureTablePart()"] --> B{"Tables.Exists()?"}
    B -->|No| C["Tables.CreateTable()<br/>テーブル新規作成"]
    B -->|Yes| D{"Tables.HasChanges()?"}
    D -->|No| E["変更なし → スキップ"]
    D -->|Yes| F["Tables.MigrateTable()<br/>マイグレーション実行"]
```

### HasChanges の判定構造

`Tables.HasChanges()` は以下の4種類のチェックを順に行い、
いずれか1つでも差異があれば `true`（要マイグレーション）と判定する。

**ファイル**: `Functions/Rds/Parts/Tables.cs`

```mermaid
flowchart TD
    A["Tables.HasChanges()"] --> B{"(1) カラム数の比較<br/>定義と実DBのカラム数が異なる?"}
    B -->|Yes| Z["true → 要マイグレーション"]
    B -->|No| C{"(2) Columns.HasChanges()<br/>各カラムの属性が異なる?"}
    C -->|Yes| Z
    C -->|No| D{"(3) Constraints.HasChanges()<br/>デフォルト値制約が異なる?"}
    D -->|Yes| Z
    D -->|No| E{"(4) Indexes.HasChanges()<br/>インデックス構成が異なる?"}
    E -->|Yes| Z
    E -->|No| F["false → 変更なし"]
```

### (1) カラム数の比較

最も軽量なチェック。定義ファイル上のカラム数と
実DBから取得したカラム数を単純比較する。

```csharp
// Tables.cs
private static bool HasChanges(
    IEnumerable<ColumnDefinition> columnDefinitionCollection,
    EnumerableRowCollection<DataRow> rdsColumnCollection)
{
    return rdsColumnCollection.Count() != columnDefinitionCollection.Count();
}
```

カラムの追加・削除がある場合、この時点で即座にマイグレーション対象となる。

### (2) カラム属性の比較（Columns.HasChanges）

各カラムを定義順に1つずつ比較し、以下の属性をチェックする。

**ファイル**: `Functions/Rds/Parts/Columns.cs`

| チェック項目 | 比較内容                                                   |
| ------------ | ---------------------------------------------------------- |
| カラム名     | `rdsColumn["ColumnName"]` vs `columnDefinition.ColumnName` |
| データ型     | `ConvertBack(rdsColumn["TypeName"])` vs `TypeName`         |
| カラムサイズ | 型に応じた詳細比較（後述）                                 |
| NULL許可     | `rdsColumn["is_nullable"]` vs `Nullable`                   |
| IDENTITY属性 | `rdsColumn["is_identity"]` vs `Identity`                   |

**IDENTITY属性の例外**: `_history` / `_deleted` テーブルでは
IDENTITY チェックをスキップする
（これらのテーブルでは IDENTITY を付与しないため）。

**データ型の比較**: `ISqlDataType.ConvertBack()` により、
実DBの型名を定義ファイルの SQL Server 基準の型名に逆変換してから比較する。
これにより RDBMS 間の型名の差異を吸収している。

#### カラムサイズの比較

カラムサイズの判定は RDBMS によってロジックが異なる。

**SQL Server / PostgreSQL**（`ColumnSize.HasChanges`）:

| データ型            | 比較方法                                                             |
| ------------------- | -------------------------------------------------------------------- |
| `char`, `varchar`   | `max_length` vs `MaxLength × 1`                                      |
| `nchar`, `nvarchar` | `max_length` vs `MaxLength × NationalCharacterStoredSizeCoefficient` |
| `decimal`           | `Size` 文字列の完全一致（例: `"18,4"`）                              |
| その他              | サイズ比較なし（常に `false`）                                       |

`MaxLength == -1`（max指定）の場合、
実DB側も `-1` であれば変更なしと判定する。

`NationalCharacterStoredSizeCoefficient` は
SQL Server では `2`、PostgreSQL では `4` が設定されている。

**MySQL**（`MySqlColumnSize.HasChanges`）:

MySQL では `nvarchar` の扱いが特殊で、
`MaxLength` の値に応じて以下のように判定が分岐する。

| 条件                  | 期待されるDB上の型              | 判定基準                 |
| --------------------- | ------------------------------- | ------------------------ |
| `MaxLength == -1`     | `longtext`                      | `TypeName != "longtext"` |
| `MaxLength < 1024`    | `varchar(MaxLength × 係数)`     | 通常のサイズ比較         |
| `NeedReduceByDefault` | `varchar(760 × 係数)`           | 縮小済みかどうか         |
| それ以外              | `varchar(760 × 係数)` or `text` | インデックス有無で分岐   |

MySQL ではインデックス対象カラムの `varchar` サイズに上限があるため、
`ReducedVarcharLength`（デフォルト `760`）への縮小処理が行われる。

### (3) デフォルト値制約の比較（Constraints.HasChanges）

定義ファイル上の `Default` プロパティと、
実DBのデフォルト値制約を文字列として比較する。

**ファイル**: `Functions/Rds/Parts/Constraints.cs`

比較方法:

1. 定義側: `Default` が設定されているカラムを `ColumnName` 順にソートし、
   `"{ColumnName},{DefaultValue}"` 形式の文字列に変換
2. DB側: `Def.Sql.Defaults` で取得したデフォルト値情報を同様にソートして文字列化
3. 両者を改行区切りで結合した文字列を完全一致比較

`_history` テーブルの `Ver` カラムは比較対象から除外される。

デフォルト値は型に応じて以下のように変換される:

| C# 型サマリ    | デフォルト値の表現                                |
| -------------- | ------------------------------------------------- |
| `CsString`     | `'{Default}'`（シングルクォート囲み）             |
| `CsDateTime`   | `now` → `getdate()` / `CURRENT_TIMESTAMP` 等      |
| `CsBool`       | RDBMS固有のBoolean値（`1`/`0` or `true`/`false`） |
| その他（数値） | そのまま                                          |

### (4) インデックス構成の比較（Indexes.HasChanges）

定義ファイル上のインデックス名一覧と、
実DBのインデックス名一覧を文字列比較する。

**ファイル**: `Functions/Rds/Parts/Indexes.cs`

#### SQL Server / PostgreSQL

定義側の `IndexInfoCollection` から生成したインデックス名と、
`Def.Sql.Indexes` で取得した実DBのインデックス名を
カンマ区切りで結合して完全一致比較する。
PostgreSQL では全文検索インデックス（`ftx`）を比較対象から除外する。

#### MySQL

MySQL では PK とそれ以外のインデックスを分離して比較する。

- **PK**: 定義側の PK 情報と `PRIMARY` キーの列構成を比較
- **IX**: 定義側のインデックス名一覧と
  DB側のインデックス名一覧（`PRIMARY`/`ftx` 除外）を比較

MySQL 固有の処理として、`PkMySql` プロパティが設定されている場合、
通常の `Pk` の代わりにこちらが PK 構成として使用される。

#### DisableIndexChangeDetection パラメータ

`Parameters.Rds.DisableIndexChangeDetection`（デフォルト: `true`）が有効な場合、
インデックスの変更検知は**完全にスキップ**される。
これにより、インデックス変更のみの差異ではマイグレーションが発生しない。

### カラムフィルタリング条件

`ConfigureTableSet()` で比較対象となるカラム定義には、
以下のフィルタリング条件が適用される。

**ファイル**: `Functions/Rds/TablesConfigurator.cs`

| フィルタ条件            | 除外されるカラム                                   |
| ----------------------- | -------------------------------------------------- |
| `!o.NotUpdate`          | `NotUpdate == true` のカラム（テーブル構成対象外） |
| `JoinTableName` が空    | JOIN用のカラム（実テーブルには存在しない）         |
| `Calc` が空             | 計算列（実テーブルには存在しない）                 |
| `!o.LowSchemaVersion()` | スキーマバージョン制限を超えるカラム               |
| `ShouldIncludeColumn()` | `ExcludeBaseColumns` による除外                    |

#### LowSchemaVersion

**ファイル**: `Implem.DefinitionAccessor/Extensions.cs`

`SysLogs` テーブルのみに適用される。
`columnDefinition.SchemaVersion > Parameters.Rds.SysLogsSchemaVersion`
の場合、そのカラムは構成対象から除外される。
これにより SysLogs テーブルのスキーマを段階的にアップグレードできる。

#### ExcludeBaseColumns

テーブル固有カラムの全てに `ExcludeBaseColumns == true` が設定されている場合、
\_Base 継承で追加されたカラムがそのテーブルの構成から除外される。

### マイグレーションの実行方式

変更が検知された場合、`MigrateTable()` は
「テーブル再作成 + データ移行」方式でマイグレーションを実行する。

**ファイル**: `Functions/Rds/Parts/Tables.cs`

```mermaid
flowchart TD
    A["MigrateTable()"] --> B["(1) 新定義で一時テーブル作成<br/>{datetime}_{テーブル名}"]
    B --> C{"IDENTITY列あり?<br/>(history/deleted以外)"}
    C -->|Yes| D["MigrateTableWithIdentity<br/>IDENTITY_INSERT ON → データコピー → OFF"]
    C -->|No| E["MigrateTable<br/>通常のINSERT INTO...SELECT"]
    D --> F["(2) 旧テーブル削除 + 一時テーブルをRENAME"]
    E --> F
```

#### データ移行時のカラムマッピング

既存テーブルから新テーブルへのデータコピー時、
各カラムは以下のルールでマッピングされる。

| 条件                                       | マッピング方法                           |
| ------------------------------------------ | ---------------------------------------- |
| 旧テーブルに同名カラムが存在する           | そのままコピー                           |
| 旧テーブルになく `OldColumnName` が設定    | 旧カラム名からコピー（リネーム対応）     |
| 旧テーブルになく `Default` もなく NOT NULL | 型に応じたデフォルト値を補完             |
| 上記以外（新規追加 or NULL許可）           | コピー対象外（NULL or DEFAULT で初期化） |

**型に応じたデフォルト値の補完**:

| 型サマリ       | 補完値                               |
| -------------- | ------------------------------------ |
| `CsString`     | `''`（空文字列）                     |
| `CsDateTime`   | `getdate()` / `CURRENT_TIMESTAMP` 等 |
| `CsBool`       | RDBMS固有のBoolean値                 |
| その他（数値） | `0`                                  |

---

## テーブル定義ファイル（Definition_Column）

### 格納場所

テーブル・カラムの定義は以下のディレクトリに JSON ファイルとして格納されている。

```text
Implem.Pleasanter/App_Data/Definitions/Definition_Column/
├── __ColumnSettings.json        ← カラムスキーマ定義（全プロパティ名と型の一覧）
├── _Bases_Ver.json              ← 共通ベースカラム（全テーブルに継承）
├── _Bases_CreatedTime.json
├── _BaseItems_Body.json         ← アイテム系テーブル共通カラム
├── _BaseItems_Title.json
├── Items_ReferenceId.json       ← テーブル固有カラム
├── Issues_IssueId.json
├── Sites_SiteId.json
├── Users_UserId.json
├── QRTZ_JOB_DETAILS_JOB_NAME.json  ← Quartzテーブル定義
└── ...（計427ファイル + __ColumnSettings.json）
```

### ファイル命名規則

```text
{テーブル名}_{カラム名}.json
```

1カラムにつき1つの JSON ファイルが存在する。
ファイル名がそのまま `{TableName}_{ColumnName}` となる。

### テーブル一覧と定義ファイル数

| テーブル名               | カラム定義数 | 説明                         |
| ------------------------ | -----------: | ---------------------------- |
| `_Bases`                 |            8 | 全テーブル共通ベースカラム   |
| `_BaseItems`             |            5 | アイテム系テーブル共通カラム |
| `Users`                  |           62 | ユーザー管理                 |
| `SysLogs`                |           48 | システムログ                 |
| `Sites`                  |           32 | サイト管理                   |
| `Tenants`                |           21 | テナント管理                 |
| `Binaries`               |           15 | バイナリデータ               |
| `OutgoingMails`          |           15 | 送信メール                   |
| `Registrations`          |           15 | ユーザー登録                 |
| `Groups`                 |           14 | グループ管理                 |
| `Issues`                 |           11 | 期限付きテーブル             |
| `Items`                  |            8 | アイテム管理                 |
| `Results`                |            7 | 結果テーブル                 |
| `QRTZ_*`（複数テーブル） |           80 | Quartz.NET スケジューラ用    |
| その他                   |           86 | セッション、権限、リンク等   |

### JSON ファイルの構造

各 JSON ファイルは、`__ColumnSettings.json` で定義されたスキーマに従う
フラットなキーバリュー形式である。

**スキーマ定義ファイル**: `__ColumnSettings.json`（139項目）

```json
{
    "Id": "string",
    "ModelName": "string",
    "TableName": "string",
    "ColumnName": "string",
    "TypeName": "string",
    "MaxLength": "int",
    "Pk": "int",
    "Nullable": "bool",
    "Identity": "bool",
    "Default": "string",
    ...
}
```

**カラム定義ファイルの例**（`Issues_IssueId.json`）:

```json
{
    "Id": "Issues_IssueId",
    "ModelName": "Issue",
    "TableName": "Issues",
    "Label": "期限付きテーブル",
    "ColumnName": "IssueId",
    "LabelText": "ID",
    "No": "4",
    "TypeName": "bigint",
    "Pk": "10",
    "PkHistory": "2",
    "Ix1": "1",
    "Unique": "1",
    "Identity": "0",
    "ItemId": "20",
    ...
}
```

#### DB構成に関わる主要プロパティ

| プロパティ      | 型       | 説明                                |
| --------------- | -------- | ----------------------------------- |
| `TableName`     | `string` | 作成先テーブル名                    |
| `ColumnName`    | `string` | カラム名                            |
| `TypeName`      | `string` | データ型（SQL Server 基準名）       |
| `MaxLength`     | `int`    | 最大長（`-1` = max / text）         |
| `Size`          | `string` | decimal等のサイズ指定（例: `18,4`） |
| `Pk`            | `int`    | 主キー順序（>0 で PK構成列）        |
| `PkOrderBy`     | `string` | PK のソート順（`asc`/`desc`）       |
| `PkHistory`     | `int`    | 履歴テーブル用PK順序                |
| `Ix1`〜`Ix5`    | `int`    | インデックス1〜5の構成列順序        |
| `Nullable`      | `bool`   | NULL許可                            |
| `Identity`      | `bool`   | IDENTITY（自動採番）属性            |
| `Seed`          | `int`    | IDENTITYの初期値                    |
| `Unique`        | `bool`   | ユニーク制約                        |
| `Default`       | `string` | デフォルト値                        |
| `NotUpdate`     | `bool`   | テーブル構成対象外フラグ            |
| `History`       | `int`    | 履歴テーブル構成列順序（>0 で対象） |
| `OldColumnName` | `string` | マイグレーション用の旧カラム名      |

### 読み込みの仕組み

```mermaid
flowchart TD
    A["Initializer.DefinitionFile('Column')"] --> B["XlsIo コンストラクタ"]
    B --> C{"__ColumnSettings.json<br/>が存在?"}
    C -->|Yes| D["(i) カラムスキーマとして読込<br/>→ XlsSheet.Columns に設定"]
    D --> E["(ii) 各 JSON ファイルを走査<br/>→ XlsRow として追加"]
    E --> F["SetColumnDefinitionAdditional"]
    F --> G["(iii) _Base カラムの継承展開"]
    G --> H["Def.SetColumnDefinition()"]
    H --> I["(iv) XlsSheet → ColumnDefinition に変換<br/>→ Def.ColumnDefinitionCollection に格納"]
```

#### (i) スキーマ読み込み

`__ColumnSettings.json` を最初に読み込み、
全プロパティ名のリストを `XlsSheet.Columns` として保持する。
これが以降の各 JSON ファイル読み込み時の「列名一覧」となる。

#### (ii) 個別ファイル読み込み

`Definition_Column/` 内の全 `.json` ファイル
（`__ColumnSettings.json` 以外）を走査し、
各ファイルを `Dictionary<string, string>` にデシリアライズして
`XlsRow` として `XlsSheet` に追加する。

**ファイル**: `Implem.Libraries/Classes/XlsIo.cs`（`ReadDefinitionFiles` メソッド）

#### (iii) \_Base カラムの継承展開

`SetColumnDefinitionAdditional()` により、
`_Base` / `_BaseItem` の共通カラム定義が各テーブルにコピーされる。

```mermaid
flowchart LR
    A["_Bases_Ver.json<br/>(Base=true)"] --> B["Issues_Ver"]
    A --> C["Results_Ver"]
    A --> D["Sites_Ver"]
    A --> E["Users_Ver"]
    A --> F["...全テーブルへコピー"]
    G["_BaseItems_Body.json<br/>(Base=true, ItemId>0)"] --> H["Issues_Body"]
    G --> I["Results_Body"]
```

- `Base == true` のカラム定義が、`Base == false` の全テーブルに対してコピーされる
- コピー時に `ModelName`, `TableName`, `Label` を対象テーブルの値に書き換える
- `ItemId > 0` の `_BaseItem` カラムは、
  `ItemId > 0` のテーブル（Issues, Results 等）にのみ展開される
- 既に同名カラムが存在する場合はコピーをスキップする

#### (iv) ColumnDefinition への変換

`Def.SetColumnDefinition()` で `XlsSheet` の各行を
`ColumnDefinition` オブジェクトに変換し、
`Def.ColumnDefinitionCollection` に格納する。
CodeDefiner の `TablesConfigurator` はこのコレクションを参照して
テーブルの作成・更新を行う。

---

## 結論

| 項目             | 内容                                                                                                  |
| ---------------- | ----------------------------------------------------------------------------------------------------- |
| 処理フロー       | KillTask → DB作成/更新 → ユーザー設定 → スキーマ設定 → カラム削減チェック → テーブル構成 → 権限設定   |
| テーブル更新方式 | 新テーブル作成 → データ移行 → リネーム方式（データロスを最小化）                                      |
| 変更検知         | カラム数・カラム名・データ型・サイズ・NULL制約・IDENTITY・デフォルト値・インデックスの8項目で差分検知 |
| RDBMS差異吸収層1 | Abstract Factory パターン（`ISqlObjectFactory` と各RDBMS実装クラス）                                  |
| RDBMS差異吸収層2 | SQL定義ファイル（`App_Data/Definitions/Sqls/{RDBMS}/` に55個ずつ同名ファイルを配置）                  |
| RDBMS差異吸収層3 | C# コード内 `switch` 分岐（カラム作成・インデックス・制約設定など）                                   |
| データ型統一     | 定義ファイルは SQL Server 型名で統一、`ISqlDataType.Convert/ConvertBack` で実行時に変換               |
| 接続権限         | SA接続（サーバーレベル操作）と Admin接続（DB内操作）の2段階                                           |
| マネージド対応   | `RdsProvider` フラグで、DB/ユーザー/スキーマ/権限の管理をスキップ可能                                 |

---

## 関連ソースコード

| ファイル                                                       | 役割                                             |
| -------------------------------------------------------------- | ------------------------------------------------ |
| `Implem.CodeDefiner/Starter.cs`                                | エントリーポイント、コマンドディスパッチ         |
| `Implem.CodeDefiner/Functions/Rds/Configurator.cs`             | DB構成のオーケストレーション                     |
| `Implem.CodeDefiner/Functions/Rds/RdsConfigurator.cs`          | データベース作成・更新                           |
| `Implem.CodeDefiner/Functions/Rds/UsersConfigurator.cs`        | ユーザー作成・更新                               |
| `Implem.CodeDefiner/Functions/Rds/SchemaConfigurator.cs`       | スキーマ設定                                     |
| `Implem.CodeDefiner/Functions/Rds/TablesConfigurator.cs`       | テーブル構成（作成・マイグレーション）           |
| `Implem.CodeDefiner/Functions/Rds/PrivilegeConfigurator.cs`    | 権限設定                                         |
| `Implem.CodeDefiner/Functions/Rds/Parts/Tables.cs`             | テーブル操作（作成・マイグレーション・存在確認） |
| `Implem.CodeDefiner/Functions/Rds/Parts/Columns.cs`            | カラム定義生成・変更検知                         |
| `Implem.CodeDefiner/Functions/Rds/Parts/Indexes.cs`            | インデックス定義・変更検知                       |
| `Implem.CodeDefiner/Functions/Rds/Parts/Constraints.cs`        | デフォルト値制約                                 |
| `Implem.Factory/RdsFactory.cs`                                 | Abstract Factoryの生成                           |
| `Rds/Implem.IRds/ISqlObjectFactory.cs`                         | 抽象ファクトリインターフェース                   |
| `Rds/Implem.IRds/ISqls.cs`                                     | SQL方言インターフェース                          |
| `Rds/Implem.IRds/ISqlDataTypes.cs`                             | データ型変換インターフェース                     |
| `Rds/Implem.IRds/ISqlDefinitionSetting.cs`                     | RDBMS固有設定インターフェース                    |
| `Rds/Implem.SqlServer/SqlServerObjectFactory.cs`               | SQL Server ファクトリ実装                        |
| `Rds/Implem.PostgreSql/PostgreSqlObjectFactory.cs`             | PostgreSQL ファクトリ実装                        |
| `Rds/Implem.MySql/MySqlObjectFactory.cs`                       | MySQL ファクトリ実装                             |
| `App_Data/Definitions/Sqls/SQLServer/*.sql`                    | SQL Server 用SQLテンプレート（55個）             |
| `App_Data/Definitions/Sqls/PostgreSQL/*.sql`                   | PostgreSQL 用SQLテンプレート（55個）             |
| `App_Data/Definitions/Sqls/MySQL/*.sql`                        | MySQL 用SQLテンプレート（55個）                  |
| `App_Data/Definitions/Definition_Column/*.json`                | カラム定義ファイル（427個）                      |
| `App_Data/Definitions/Definition_Column/__ColumnSettings.json` | カラムスキーマ定義                               |
| `Implem.DefinitionAccessor/Def.cs`                             | 定義コレクション管理・変換処理                   |
| `Implem.DefinitionAccessor/Initializer.cs`                     | 定義ファイル読込・\_Base継承展開                 |
| `Implem.Libraries/Classes/XlsIo.cs`                            | JSON定義ファイルローダー                         |
