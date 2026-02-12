# 拡張SQL 実行権限・外部DB接続

拡張SQL（ExtendedSql）の実行権限設定と、各DBMS（SQL Server / PostgreSQL / MySQL）での外部データベース接続方法をまとめる。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [第1章 拡張SQLの基礎](#第1章-拡張sqlの基礎)
    - [1.1 概要](#11-概要)
    - [1.2 設定プロパティ（ExtendedSqlクラス）](#12-設定プロパティextendedsqlクラス)
    - [1.3 プレースホルダー](#13-プレースホルダー)
    - [1.4 設定サンプル](#14-設定サンプル)
- [第2章 拡張SQLの実行権限](#第2章-拡張sqlの実行権限)
    - [2.1 DbUserプロパティ](#21-dbuserプロパティ)
    - [2.2 拡張SQL実行時の権限処理](#22-拡張sql実行時の権限処理)
- [第3章 プリザンターのDB権限構成](#第3章-プリザンターのdb権限構成)
    - [3.1 CodeDefinerによる権限設定の処理フロー](#31-codedefinerによる権限設定の処理フロー)
    - [3.2 SQL Server用のSQL定義](#32-sql-server用のsql定義)
    - [3.3 PostgreSQL用のSQL定義](#33-postgresql用のsql定義)
    - [3.4 MySQL用のSQL定義](#34-mysql用のsql定義)
    - [3.5 Owner/Userの権限差異（SQL Server）](#35-owneruserの権限差異sql-server)
    - [3.6 権限差異の影響](#36-権限差異の影響)
    - [3.7 CodeDefiner作成ユーザーの制限事項](#37-codedefiner作成ユーザーの制限事項)
- [第4章 外部データベース接続](#第4章-外部データベース接続)
    - [4.1 DBMS別 外部DB接続機能の比較](#41-dbms別-外部db接続機能の比較)
    - [4.2 SQL Server（Linked Server）](#42-sql-serverlinked-server)
    - [4.3 PostgreSQL（Foreign Data Wrapper）](#43-postgresqlforeign-data-wrapper)
    - [4.4 MySQL（FEDERATEDエンジン）](#44-mysqlfederatedエンジン)
- [第5章 外部DB接続時の注意点](#第5章-外部db接続時の注意点)
    - [5.1 セキュリティ](#51-セキュリティ)
    - [5.2 パフォーマンス](#52-パフォーマンス)
    - [5.3 OPENQUERYの使用例（SQL Server）](#53-openqueryの使用例sql-server)
    - [5.4 エラーハンドリング](#54-エラーハンドリング)
    - [5.5 RPCオプションの有効化（SQL Server）](#55-rpcオプションの有効化sql-server)
    - [5.6 分散トランザクション (MSDTC) の考慮](#56-分散トランザクション-msdtc-の考慮)
- [まとめ](#まとめ)
- [関連ソースコード](#関連ソースコード)
- [関連リンク](#関連リンク)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

---

## 調査情報

| 項目             | 内容                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------- |
| 調査日           | 2026-02-06                                                                                    |
| 対象バージョン   | プリザンター main ブランチ commit `8c261c0a8`                                                 |
| 対象ファイル     | ExtendedSql.cs, Rds.cs, ExtensionUtilities.cs, UsersConfigurator.cs, PrivilegeConfigurator.cs |
| 関連ドキュメント | [公式マニュアル - 拡張SQL](https://pleasanter.org/manual/extended-sql)                        |

---

## 調査目的

- 拡張SQLの実行権限オプション（`DbUser`プロパティ）の仕組みを理解する
- 各DBMS（SQL Server / PostgreSQL / MySQL）での外部データベース接続方法を明確にする
- 外部DB接続時の権限設定・注意点を整理する

---

## 第1章 拡張SQLの基礎

### 1.1 概要

プリザンターの拡張SQL（ExtendedSql）は、`App_Data/Parameters/ExtendedSqls/` ディレクトリにJSON形式で配置することで、任意のSQLを実行できる機能である。

**設定ファイルの配置場所**:

```text
Implem.Pleasanter/App_Data/Parameters/ExtendedSqls/{任意の名前}.json
```

### 1.2 設定プロパティ（ExtendedSqlクラス）

**ファイル**: `Implem.ParameterAccessor/Parts/ExtendedSql.cs`

```csharp
public class ExtendedSql : ExtendedBase
{
    public bool Api;                  // API経由での実行を許可
    public string DbUser;             // 実行時のDBユーザー（権限レベル）
    public bool Html;                 // HTML出力用
    public bool OnCreating;           // レコード作成前に実行
    public bool OnCreated;            // レコード作成後に実行
    public bool OnUpdating;           // レコード更新前に実行
    public bool OnUpdated;            // レコード更新後に実行
    public bool OnUpdatingByGrid;     // グリッド更新前に実行
    public bool OnUpdatedByGrid;      // グリッド更新後に実行
    public bool OnDeleting;           // レコード削除前に実行
    public bool OnDeleted;            // レコード削除後に実行
    public bool OnBulkUpdating;       // 一括更新前に実行
    public bool OnBulkUpdated;        // 一括更新後に実行
    public bool OnBulkDeleting;       // 一括削除前に実行
    public bool OnBulkDeleted;        // 一括削除後に実行
    public bool OnImporting;          // インポート前に実行
    public bool OnImported;           // インポート後に実行
    public bool OnSelectingColumn;    // カラム選択時に実行
    public bool OnSelectingWhere;     // WHERE句に追加
    public bool OnSelectingWherePermissionsDepts;   // 部署権限WHERE句
    public bool OnSelectingWherePermissionsGroups;  // グループ権限WHERE句
    public bool OnSelectingWherePermissionsUsers;   // ユーザー権限WHERE句
    public List<string> OnSelectingWhereParams;     // WHERE句パラメータ
    public bool OnSelectingOrderBy;   // ORDER BY句に追加
    public List<string> OnSelectingOrderByParams;   // ORDER BY句パラメータ
    public bool OnUseSecondaryAuthentication;       // 二次認証時に実行
    public string CommandText;        // 実行するSQL文
}
```

### 1.3 プレースホルダー

拡張SQL内で使用可能なプレースホルダー：

| プレースホルダー | 説明             | 例                    |
| ---------------- | ---------------- | --------------------- |
| `{{SiteId}}`     | 現在のサイトID   | 123                   |
| `{{Id}}`         | 現在のレコードID | 456                   |
| `{{Timestamp}}`  | タイムスタンプ   | 2026/2/6 12:00:00.000 |

### 1.4 設定サンプル

#### API用クエリ

```json
{
    "Name": "FetchExternalMasterData",
    "SpecifyByName": true,
    "Description": "外部マスタDBからデータを取得",
    "Api": true,
    "DbUser": "Owner",
    "SiteIdList": [1, 2, 3],
    "CommandText": "SELECT Code, Name FROM [ExternalMasterDB].[dbo].[MasterTable] WHERE Category = @Category"
}
```

#### トリガー型実行（レコード作成時）

```json
{
    "Name": "SyncToExternalSystem",
    "Description": "外部システムへデータ同期",
    "DbUser": "Owner",
    "OnCreated": true,
    "SiteIdList": [100],
    "CommandText": "INSERT INTO [ExternalDB].[dbo].[SyncTable] (SourceId, Title) VALUES ({{Id}}, @Title)"
}
```

---

## 第2章 拡張SQLの実行権限

### 2.1 DbUserプロパティ

#### 利用可能な値

| DbUser値            | 接続文字列              | 説明                           |
| ------------------- | ----------------------- | ------------------------------ |
| `null` または未指定 | `UserConnectionString`  | 通常ユーザー権限（デフォルト） |
| `"Owner"`           | `OwnerConnectionString` | オーナー権限（管理者権限）     |

#### 接続文字列の定義

**ファイル**: `Implem.ParameterAccessor/Parts/Rds.cs`

```csharp
public class Rds
{
    public string Dbms;                  // データベース種別（SQLServer/PostgreSQL/MySQL）
    public string Provider;              // プロバイダー
    public string SaConnectionString;    // SA（sysadmin）権限接続
    public string OwnerConnectionString; // オーナー権限接続
    public string UserConnectionString;  // ユーザー権限接続
    public int SqlCommandTimeOut;        // SQLコマンドタイムアウト
    // ...
}
```

#### 権限レベルの使い分け

| 権限レベル         | 用途                   | 推奨シナリオ                  |
| ------------------ | ---------------------- | ----------------------------- |
| User（デフォルト） | 通常のデータ操作       | 参照・更新クエリ              |
| Owner              | 管理者権限が必要な操作 | DDL実行、Userに権限がない操作 |

> **注意**: 外部DB接続（DBリンク/FDW等）経由のクエリを実行する場合、使用する接続文字列（User/Owner）のSQLユーザーに外部DB接続へのアクセス権限が付与されている必要がある。権限構成によっては`DbUser`の指定変更が必要となる。

### 2.2 拡張SQL実行時の権限処理

**ファイル**: `Implem.Pleasanter/Models/Extensions/ExtensionUtilities.cs`

```csharp
private static DataSet ExecuteDataSet(
    Context context,
    string name,
    Dictionary<string, object> _params)
{
    var extendedSql = Parameters.ExtendedSqls
        ?.Where(o => o.Api)
        .Where(o => o.Name == name)
        .ExtensionWhere<ParameterAccessor.Parts.ExtendedSql>(context: context)
        .FirstOrDefault();
    if (extendedSql == null)
    {
        return null;
    }
    string connectionString;
    switch (extendedSql.DbUser)
    {
        case "Owner":
            connectionString = Parameters.Rds.OwnerConnectionString;
            break;
        default:
            connectionString = null;  // UserConnectionStringを使用
            break;
    }
    // ...SQL実行処理
}
```

---

## 第3章 プリザンターのDB権限構成

プリザンターのセットアップツール（CodeDefiner）は、データベース初期化時にSQLユーザーを作成し、適切なロールを付与する。この権限設定がOwner/Userの実行可能範囲を決定する。

### 3.1 CodeDefinerによる権限設定の処理フロー

**関連ファイル**:

- `Implem.CodeDefiner/Functions/Rds/UsersConfigurator.cs` - ユーザー作成
- `Implem.CodeDefiner/Functions/Rds/PrivilegeConfigurator.cs` - 権限付与

```csharp
// UsersConfigurator.cs - ユーザー名に応じてSQL定義を切り替え
private static string CreateUserCommandText(string uid, string pwd, string host)
{
    return uid.EndsWith("_Owner")
        ? Def.Sql.CreateLoginAdmin    // Ownerユーザー用
        : Def.Sql.CreateLoginUser;    // 通常ユーザー用
}
```

### 3.2 SQL Server用のSQL定義

**Owner用（CreateLoginAdmin.sql）**:

```sql
use "#ServiceName#";
if not exists(select * from syslogins where name='#Uid#')
begin
    create login [#Uid#] with password='#Pwd#', default_database=[#ServiceName#],
        check_expiration=off, check_policy=off;
end;
alter login "#Uid#" enable;
create user "#Uid#" for login "#Uid#";
alter role "db_owner" add member "#Uid#";  -- フル権限
```

**User用（CreateLoginUser.sql）**:

```sql
use "#ServiceName#";
if not exists(select * from syslogins where name='#Uid#')
begin
    create login [#Uid#] with password='#Pwd#', default_database=[#ServiceName#],
        check_expiration=off, check_policy=off;
end;
alter login "#Uid#" enable;
create user "#Uid#" for login "#Uid#";
-- ロール付与なし（後続のGrantPrivilegeUser.sqlで付与）
```

**User用権限付与（GrantPrivilegeUser.sql）**:

```sql
use "#ServiceName#";
alter role "db_datareader" add member "#Uid#";
alter role "db_datawriter" add member "#Uid#";
```

### 3.3 PostgreSQL用のSQL定義

PostgreSQLでは、ユーザー作成はCodeDefiner外部で事前に行う必要がある（`CreateLoginAdmin.sql`、`CreateLoginUser.sql`は空ファイル）。

**User用権限付与（GrantPrivilegeUser.sql）**:

```sql
do
$$
declare
    r record;
begin
    for r in select schemaname, tablename from pg_tables
             where tableowner='#Oid#' and schemaname='#SchemaName#'
    loop
        execute 'grant select, insert, update, delete on table "'
                || r.schemaname || '"."' || r.tablename || '" to "#Uid#"';
    end loop;
end
$$;
```

> **注意**: PostgreSQLではOwner（`#Oid#`）が所有するテーブルへの権限のみが付与される。FDW関連の権限（`USAGE ON FOREIGN SERVER`、`USER MAPPING`）は含まれない。

### 3.4 MySQL用のSQL定義

**Owner用（CreateLoginAdmin.sql）**:

```sql
create user "#Uid#"@"#MySqlConnectingHost#" identified by '#Pwd#';
grant create, alter, index, drop on "#ServiceName#".* to "#Uid#"@"#MySqlConnectingHost#";
grant select, insert, update, delete, create routine, alter routine
    on "#ServiceName#".* to "#Uid#"@"#MySqlConnectingHost#" with grant option;
```

**User用（CreateLoginUser.sql）**:

```sql
create user "#Uid#"@"#MySqlConnectingHost#" identified by '#Pwd#';
```

**User用権限付与（GrantPrivilegeUser.sql）**:

```sql
grant select, insert, update, delete, create routine, alter routine
    on "#ServiceName#".* to "#Uid#"@"#MySqlConnectingHost#";
```

> **注意**: MySQLではプリザンターデータベース（`#ServiceName#`）への権限のみが付与される。FEDERATEDテーブル作成やCREATE SERVER（SUPER権限）は含まれない。

### 3.5 Owner/Userの権限差異（SQL Server）

| 項目                        | Owner（db_owner）       | User（db_datareader/db_datawriter） |
| --------------------------- | ----------------------- | ----------------------------------- |
| SELECT/INSERT/UPDATE/DELETE | ○                       | ○                                   |
| DDL（CREATE/ALTER/DROP）    | ○                       | ×                                   |
| IDENTITY_INSERT             | ○                       | ×（ALTER TABLE権限が必要）          |
| EXECUTE権限（ストアド等）   | ○                       | 個別付与が必要                      |
| 外部DB接続（DBリンク等）    | ○（権限付与済みの場合） | 個別付与が必要                      |

### 3.6 権限差異の影響

この権限設定により、以下の動作が決まる：

1. **通常のCRUD操作**: `UserConnectionString`（db_datareader/db_datawriter）で実行可能
2. **レコードのRestore操作**: `IDENTITY_INSERT`が必要なため`OwnerConnectionString`を使用
3. **拡張SQLでの外部DB接続**: Userに権限がなければ`DbUser: "Owner"`が必要

### 3.7 CodeDefiner作成ユーザーの制限事項

> **重要**: CodeDefinerで作成されるDBユーザーは、**プリザンターデータベース専用**である。外部データベースへのアクセス権限は一切含まれない。

| DBMS       | CodeDefinerで付与される権限                                     | 外部DBアクセスに必要な追加設定              |
| ---------- | --------------------------------------------------------------- | ------------------------------------------- |
| SQL Server | プリザンターDB内の`db_owner`または`db_datareader/db_datawriter` | Linked Serverログインマッピング（masterDB） |
| PostgreSQL | プリザンターDB内テーブルへのSELECT/INSERT/UPDATE/DELETE         | FDWサーバーUSAGE権限、ユーザーマッピング    |
| MySQL      | プリザンターDB内のDML/DDL権限                                   | FEDERATEDテーブル作成権限、接続情報設定     |

拡張SQLで外部DBにアクセスする場合は、**DBAが第4章の設定を別途実施する必要がある**。CodeDefiner実行後、自動的に外部DBへアクセスできるわけではない点に注意すること。

---

## 第4章 外部データベース接続

### 4.1 DBMS別 外部DB接続機能の比較

| 項目               | SQL Server (Linked Server) | PostgreSQL (FDW)         | MySQL (FEDERATED) |
| ------------------ | -------------------------- | ------------------------ | ----------------- |
| 設定単位           | サーバー単位               | サーバー＋テーブル単位   | テーブル単位      |
| 対応DBMS           | 多種（OLE DB対応）         | 多種（FDW拡張依存）      | MySQL同士のみ     |
| クエリ構文         | 4部構成名 / OPENQUERY      | 通常のSELECT             | 通常のSELECT      |
| トランザクション   | 分散トランザクション対応   | 対応                     | 非対応            |
| 権限管理           | サーバーレベル             | サーバー＋テーブルレベル | テーブルレベル    |
| 設定の複雑さ       | 中                         | 高                       | 低                |
| パフォーマンス調整 | OPENQUERY推奨              | fetch_size等のオプション | 制限あり          |

---

### 4.2 SQL Server（Linked Server）

#### 4.2.1 設定手順

##### Linked Serverの作成

SQL Server Management Studio（SSMS）またはT-SQLで設定する。

```sql
-- リンクサーバーの作成
EXEC sp_addlinkedserver
    @server = N'RemoteServer',           -- リンクサーバー名
    @srvproduct = N'',
    @provider = N'SQLNCLI11',            -- SQL Serverの場合
    @datasrc = N'remote-server-name';    -- リモートサーバー名/IP
```

##### プリザンターの接続ユーザーへの権限付与

まず、プリザンターが使用しているSQLログイン名を特定する（`App_Data/Parameters/Rds.json`の`Uid`プロパティを確認）。

```sql
-- ローカルログインとリモートログインのマッピングを設定
EXEC sp_addlinkedsrvlogin
    @rmtsrvname = N'RemoteServer',
    @useself = N'False',
    @locallogin = N'pleasanter_owner',
    @rmtuser = N'remote_user',
    @rmtpassword = N'password';
```

##### デフォルトマッピング（全ユーザー向け）

`@locallogin = NULL`を指定すると、個別マッピングがない全てのローカルログインに適用されるデフォルトマッピングを設定できる。

```sql
-- 全ログイン向けのデフォルトマッピング
EXEC sp_addlinkedsrvlogin
    @rmtsrvname = N'RemoteServer',
    @useself = N'False',
    @locallogin = NULL,              -- NULLで全ユーザーに適用
    @rmtuser = N'remote_user',
    @rmtpassword = N'password';
```

> **注意**: デフォルトマッピングは便利だが、全ユーザーがリモートサーバーにアクセス可能になるため、セキュリティ上のリスクがある。プリザンター用には`pleasanter_owner`と`pleasanter_user`のみに個別マッピングを設定することを推奨。

##### 拡張SQLの設定例

**ファイル**: `App_Data/Parameters/ExtendedSqls/remote-data-access.json`

```json
{
    "Name": "GetRemoteData",
    "Description": "リモートDBからデータを取得",
    "Api": true,
    "DbUser": "Owner",
    "CommandText": "SELECT * FROM [RemoteServer].[RemoteDB].[dbo].[TableName] WHERE Id = @Id"
}
```

#### 4.2.2 必要な権限

| 権限カテゴリ                    | 必要な権限                     | 付与先                 | 備考                           |
| ------------------------------- | ------------------------------ | ---------------------- | ------------------------------ |
| Linked Serverログインマッピング | sp_addlinkedsrvloginでの設定   | SQL Serverインスタンス | リモートサーバーへの認証情報   |
| OPENQUERYの実行権限             | (ログインマッピングに含まれる) | -                      | OPENQUERY構文使用時            |
| リモートDB側の権限              | SELECT/INSERT等の必要な権限    | リモートデータベース   | リモート側で接続ユーザーに付与 |

> **重要**: `db_owner`や`db_datareader`はプリザンターのデータベース内の権限であり、Linked Serverへの接続権限は**masterデータベース**で別途付与が必要。

#### 4.2.3 ロールと権限の整理

DBリンクを使用するために必要なのは**データベースロールではなく、サーバーレベルの権限**である。

| 操作                        | 必要なロール/権限              | 種別           | 備考                     |
| --------------------------- | ------------------------------ | -------------- | ------------------------ |
| Linked Server**作成・管理** | `sysadmin` または `setupadmin` | サーバーロール | DBAが実施                |
| Linked Server**使用**       | 特定ロール不要                 | 個別設定       | ログインマッピングで制御 |

**よくある誤解**:

| 誤解                                         | 実際                                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------------------- |
| `db_owner`があればDBリンクが使える           | ×：db_ownerはDB内の権限、DBリンクはサーバーレベル                                   |
| 特定のサーバーロールがあればDBリンクが使える | △：sysadminは全権限を持つため可能だが、通常ユーザーはログインマッピングで許可される |
| データベースロールでDBリンク権限を制御できる | ×：DBリンクはサーバーオブジェクトのため、サーバーレベルで制御                       |

#### 4.2.4 権限の調査方法

##### Linked Serverの存在確認

```sql
SELECT name, provider, data_source, is_linked
FROM sys.servers
WHERE is_linked = 1;
```

##### 現在のユーザーの権限確認

```sql
USE master;

SELECT
        s.name AS LinkedServerName,
        sp.name AS LocalLogin,
        ll.uses_self_credential,
        ll.remote_name
FROM sys.linked_logins ll
JOIN sys.servers s ON ll.server_id = s.server_id
LEFT JOIN sys.server_principals sp ON ll.local_principal_id = sp.principal_id
WHERE s.is_linked = 1
    AND (ll.local_principal_id = SUSER_ID() OR ll.local_principal_id IS NULL);
```

##### ログインマッピング確認

```sql
SELECT
    s.name AS LinkedServerName,
    ll.local_principal_id,
    sp.name AS LocalLogin,
    ll.uses_self_credential,
    ll.remote_name
FROM sys.linked_logins ll
JOIN sys.servers s ON ll.server_id = s.server_id
LEFT JOIN sys.server_principals sp ON ll.local_principal_id = sp.principal_id
WHERE s.is_linked = 1;
```

##### 接続テスト

```sql
-- 実際にLinked Serverへ接続できるかテスト
EXEC sp_testlinkedserver N'RemoteServer';

-- クエリ実行テスト（4部構成名）
SELECT TOP 1 * FROM [RemoteServer].[RemoteDB].[dbo].[TableName];

-- クエリ実行テスト（OPENQUERY）
SELECT TOP 1 * FROM OPENQUERY([RemoteServer], 'SELECT * FROM [RemoteDB].[dbo].[TableName]');
```

#### 4.2.5 権限不足時のエラーと対処

| エラーメッセージ                                          | 原因                     | 対処方法                                  |
| --------------------------------------------------------- | ------------------------ | ----------------------------------------- |
| "サーバー 'X' へのアクセスが拒否されました"               | ログインマッピング未設定 | `sp_addlinkedsrvlogin`で設定              |
| "リンク サーバー 'X' の OLE DB プロバイダー ... でエラー" | ログインマッピング未設定 | `sp_addlinkedsrvlogin`で設定              |
| "リモート サーバーでログインに失敗しました"               | リモート側の認証エラー   | リモートサーバーのログイン/パスワード確認 |
| "オブジェクト 'X' に対する SELECT 権限が拒否されました"   | リモートDB側の権限不足   | リモートサーバーで権限付与                |

---

### 4.3 PostgreSQL（Foreign Data Wrapper）

PostgreSQLでは**Foreign Data Wrapper（FDW）**を使用して外部データベースに接続する。

#### 4.3.1 概要

| 項目                  | 内容                                         |
| --------------------- | -------------------------------------------- |
| 機能名                | Foreign Data Wrapper（FDW）                  |
| PostgreSQL→PostgreSQL | `postgres_fdw`拡張を使用                     |
| PostgreSQL→他DBMS     | `mysql_fdw`、`oracle_fdw`、`tds_fdw`等を使用 |
| 標準機能              | SQL/MED標準に準拠                            |

#### 4.3.2 設定手順

##### 拡張機能の有効化

```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
```

##### 外部サーバーの定義

```sql
CREATE SERVER remote_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (
        host 'remote-host',
        port '5432',
        dbname 'remote_db'
    );
```

##### ユーザーマッピングの設定

```sql
CREATE USER MAPPING FOR pleasanter_owner
    SERVER remote_server
    OPTIONS (
        user 'remote_user',
        password 'password'
    );
```

##### 外部テーブルの定義

```sql
-- 個別テーブル定義
CREATE FOREIGN TABLE remote_table (
    id integer,
    name text,
    created_at timestamp
) SERVER remote_server
OPTIONS (
    schema_name 'public',
    table_name 'source_table'
);

-- または、スキーマ全体をインポート
IMPORT FOREIGN SCHEMA public
    FROM SERVER remote_server
    INTO local_schema;
```

#### 4.3.3 必要な権限

| 権限カテゴリ       | 必要な権限                           | 付与先               | 備考                             |
| ------------------ | ------------------------------------ | -------------------- | -------------------------------- |
| 拡張機能作成       | `CREATE`権限 または スーパーユーザー | データベース         | `CREATE EXTENSION`実行に必要     |
| 外部サーバー作成   | `CREATE`権限 または スーパーユーザー | データベース         | `CREATE SERVER`実行に必要        |
| ユーザーマッピング | 外部サーバーの`USAGE`権限            | 外部サーバー         | 他ユーザー用は要スーパーユーザー |
| 外部テーブル作成   | スキーマへの`CREATE`権限             | スキーマ             | `CREATE FOREIGN TABLE`実行に必要 |
| 外部テーブル使用   | 外部テーブルへの`SELECT`等           | 外部テーブル         | 通常のテーブル権限と同様         |
| リモートDB側の権限 | SELECT/INSERT等の必要な権限          | リモートデータベース | リモート側で接続ユーザーに付与   |

#### 4.3.4 権限の調査方法

##### 外部サーバーの確認

```sql
SELECT
    srvname AS server_name,
    srvowner::regrole AS owner,
    fdwname AS fdw_name,
    srvoptions AS options
FROM pg_foreign_server fs
JOIN pg_foreign_data_wrapper fdw ON fs.srvfdw = fdw.oid;
```

##### ユーザーマッピングの確認

```sql
SELECT
    um.umid,
    srv.srvname AS server_name,
    rol.rolname AS local_user,
    um.umoptions AS options
FROM pg_user_mapping um
JOIN pg_foreign_server srv ON um.umserver = srv.oid
LEFT JOIN pg_roles rol ON um.umuser = rol.oid;
```

##### 権限確認

```sql
SELECT
    srvname,
    has_server_privilege('pleasanter_owner', srvname, 'USAGE') AS can_use
FROM pg_foreign_server;
```

#### 4.3.5 拡張SQLでの使用例

```json
{
    "Name": "GetRemoteDataPostgres",
    "Description": "リモートPostgreSQLからデータを取得",
    "Api": true,
    "DbUser": "Owner",
    "CommandText": "SELECT id, name FROM remote_table WHERE category = @Category"
}
```

---

### 4.4 MySQL（FEDERATEDエンジン）

MySQLでは**FEDERATEDストレージエンジン**を使用して外部データベースに接続する。

#### 4.4.1 概要

| 項目     | 内容                                         |
| -------- | -------------------------------------------- |
| 機能名   | FEDERATEDストレージエンジン                  |
| 対象     | MySQL→MySQL間の接続                          |
| 特徴     | リモートテーブルをローカルテーブルとして参照 |
| 制限事項 | トランザクション非対応、インデックス制限あり |

#### 4.4.2 設定手順

##### FEDERATEDエンジンの有効化確認

```sql
SHOW ENGINES;

-- 無効の場合、my.cnfに以下を追加してMySQL再起動
-- [mysqld]
-- federated
```

##### FEDERATEDテーブルの作成

```sql
-- 方法1: CONNECTION文字列を使用
CREATE TABLE remote_table (
    id INT NOT NULL,
    name VARCHAR(100),
    created_at DATETIME,
    PRIMARY KEY (id)
) ENGINE=FEDERATED
CONNECTION='mysql://remote_user:password@remote-host:3306/remote_db/source_table';

-- 方法2: CREATE SERVERを使用
CREATE SERVER remote_server
FOREIGN DATA WRAPPER mysql
OPTIONS (
    HOST 'remote-host',
    PORT 3306,
    DATABASE 'remote_db',
    USER 'remote_user',
    PASSWORD 'password'
);

CREATE TABLE remote_table (
    id INT NOT NULL,
    name VARCHAR(100),
    PRIMARY KEY (id)
) ENGINE=FEDERATED
CONNECTION='remote_server/source_table';
```

#### 4.4.3 必要な権限

| 権限カテゴリ          | 必要な権限                  | 付与先               | 備考                           |
| --------------------- | --------------------------- | -------------------- | ------------------------------ |
| FEDERATEDテーブル作成 | `CREATE`権限                | ローカルデータベース | ENGINE=FEDERATEDでテーブル作成 |
| CREATE SERVER         | `SUPER`権限                 | グローバル           | サーバー定義を作成する場合     |
| FEDERATEDテーブル使用 | `SELECT`/`INSERT`等         | FEDERATEDテーブル    | 通常のテーブル権限と同様       |
| リモートDB側の権限    | SELECT/INSERT等の必要な権限 | リモートデータベース | リモート側で接続ユーザーに付与 |

> **MySQL 8.0.3以降の注意**: MySQL 8.0.3以降では、`SUPER`権限の代わりに動的権限`FEDERATED_ADMIN`が導入された。CREATE SERVERの実行にはSUPERまたはFEDERATED_ADMIN権限が必要。
>
> ```sql
> -- MySQL 8.0.3以降でのFEDERATED_ADMIN付与
> GRANT FEDERATED_ADMIN ON *.* TO 'pleasanter_owner'@'%';
> ```

#### 4.4.4 権限の調査方法

##### FEDERATEDエンジンの有効確認

```sql
SELECT ENGINE, SUPPORT FROM information_schema.ENGINES WHERE ENGINE = 'FEDERATED';
```

##### サーバー定義の確認

```sql
SELECT * FROM mysql.servers;
```

##### FEDERATEDテーブルの確認

```sql
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    ENGINE,
    CREATE_OPTIONS
FROM information_schema.TABLES
WHERE ENGINE = 'FEDERATED';
```

#### 4.4.5 制限事項

| 制限事項         | 内容                                         | 回避策                         |
| ---------------- | -------------------------------------------- | ------------------------------ |
| トランザクション | 非対応（リモートでの変更は即座にコミット）   | 重要データは別途同期処理を検討 |
| インデックス     | ローカルインデックスは使用されない           | リモート側のインデックスに依存 |
| ALTER TABLE      | 一部の変更が制限される                       | DROP→CREATE で対応             |
| パフォーマンス   | 大量データ取得時に遅延                       | WHERE句で絞り込み              |
| 接続エラー       | リモートサーバー停止時にテーブルアクセス不可 | エラーハンドリングを実装       |

#### 4.4.6 拡張SQLでの使用例

```json
{
    "Name": "GetRemoteDataMySQL",
    "Description": "リモートMySQLからデータを取得",
    "Api": true,
    "DbUser": "Owner",
    "CommandText": "SELECT id, name FROM remote_table WHERE category = @Category"
}
```

---

## 第5章 外部DB接続時の注意点

### 5.1 セキュリティ

| 項目           | 注意点                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------- |
| 認証情報の管理 | パスワードは各DBMS内に暗号化または平文で保存される（SQL Serverは暗号化、FEDERATEDは平文）   |
| 権限の最小化   | リモートサーバーへのアクセス権限は必要最小限に留める                                        |
| DbUser設定     | 使用する接続文字列のSQLユーザーに外部DB接続権限が必要（権限構成に応じて`DbUser`を設定する） |

### 5.2 パフォーマンス

| 項目            | 注意点                                   | 対策                                |
| --------------- | ---------------------------------------- | ----------------------------------- |
| 分散クエリ      | ネットワーク越しの実行でレイテンシが発生 | データ量を最小化するWHERE句の適用   |
| ロック競合      | リモートトランザクションでのロック       | タイムアウト設定の調整              |
| OPENQUERYの活用 | リモートでクエリを実行し結果のみ転送     | 大量データ取得時は`OPENQUERY`を使用 |

### 5.3 OPENQUERYの使用例（SQL Server）

```sql
-- 非効率（ローカルでフィルタリング）
SELECT * FROM [RemoteServer].[RemoteDB].[dbo].[TableName] WHERE Status = 'Active'

-- 効率的（リモートでフィルタリング）
SELECT * FROM OPENQUERY([RemoteServer],
    'SELECT * FROM [RemoteDB].[dbo].[TableName] WHERE Status = ''Active''')
```

### 5.4 エラーハンドリング

| エラー                           | 原因                              | 対処                                             |
| -------------------------------- | --------------------------------- | ------------------------------------------------ |
| "ログインできませんでした"       | 認証情報が正しくない              | `sp_addlinkedsrvlogin`の設定を確認               |
| "リンクサーバーが見つかりません" | リンクサーバーが未設定            | `sp_addlinkedserver`で作成                       |
| "権限がありません"               | マッピング未設定/リモート権限不足 | `sp_addlinkedsrvlogin`設定やリモート側の権限付与 |
| "RPC要求が無効です"              | RPCが無効                         | `sp_serveroption`でRPCを有効化                   |

### 5.5 RPCオプションの有効化（SQL Server）

```sql
EXEC sp_serveroption 'RemoteServer', 'rpc', 'true';
EXEC sp_serveroption 'RemoteServer', 'rpc out', 'true';
```

### 5.6 分散トランザクション (MSDTC) の考慮

SQL ServerでLinked Serverを使用する場合、書き込み操作を含むクエリは分散トランザクションとして処理される可能性がある。

#### MSDTCが必要となるケース

| ケース                                              | MSDTC必要 |
| --------------------------------------------------- | --------- |
| ローカルトランザクション内でLinked Serverに書き込み | ○         |
| Linked Serverへの単純なSELECT                       | ×         |
| OPENQUERY経由のSELECT                               | ×         |
| 明示的な`BEGIN DISTRIBUTED TRANSACTION`             | ○         |

#### 設定確認

```sql
-- Linked Serverの分散トランザクション設定確認
SELECT
    s.name AS server_name,
    s.is_remote_login_enabled,
    s.is_rpc_out_enabled,
    s.is_data_access_enabled
FROM sys.servers s
WHERE s.is_linked = 1;
```

#### MSDTC設定手順（Windows）

1. **コンポーネントサービス**を開く（`dcomcnfg`）
2. **コンポーネントサービス** → **コンピューター** → **マイコンピューター** → **分散トランザクションコーディネーター**
3. **ローカルDTC**を右クリック → **プロパティ**
4. **セキュリティ**タブで以下を設定：
    - ネットワークDTCアクセス: 有効
    - リモートクライアントを許可: 有効
    - リモート管理を許可: 有効
    - 受信を許可/送信を許可: 有効

#### MSDTCを回避する方法

分散トランザクションを回避したい場合は、以下のアプローチを検討する：

```sql
-- OPENQUERYを使用してリモートで完結させる（INSERT/UPDATE/DELETE）
EXEC ('INSERT INTO RemoteTable (Col1) VALUES (''Value'')') AT [RemoteServer];

-- または、トランザクション外で実行
SET XACT_ABORT OFF;
-- Linked Server操作
SET XACT_ABORT ON;
```

> **注意**: プリザンターの拡張SQLは、基本的にプリザンター側のトランザクション内で実行される。`OnCreated`や`OnUpdated`等のイベントで外部DBへの書き込みを行う場合、MSDTCの設定が必要になる可能性がある。SELECTのみの場合は通常不要。

---

## まとめ

| 項目               | 内容                                                                                    |
| ------------------ | --------------------------------------------------------------------------------------- |
| 拡張SQLの権限設定  | `DbUser`プロパティで`null`（User権限）または`"Owner"`（Owner権限）を指定                |
| 外部DB接続時の権限 | 使用する接続文字列のSQLユーザーに外部DB接続権限が必要（権限構成に応じて`DbUser`を設定） |
| SQL Server         | Linked Server（`sp_addlinkedserver`） - サーバーレベル権限が必要                        |
| PostgreSQL         | Foreign Data Wrapper（`postgres_fdw`） - USAGE権限＋ユーザーマッピングが必要            |
| MySQL              | FEDERATEDエンジン - CREATE権限＋リモートへの接続情報が必要                              |
| パフォーマンス対策 | `OPENQUERY`の活用、必要最小限のデータ取得                                               |
| セキュリティ対策   | 権限の最小化、接続情報の適切な管理                                                      |

---

## 関連ソースコード

| ファイル                                                                       | 説明                   |
| ------------------------------------------------------------------------------ | ---------------------- |
| `Implem.ParameterAccessor/Parts/ExtendedSql.cs`                                | 拡張SQL設定クラス      |
| `Implem.ParameterAccessor/Parts/Rds.cs`                                        | RDS接続設定クラス      |
| `Implem.Pleasanter/Models/Extensions/ExtensionUtilities.cs`                    | 拡張SQL実行ロジック    |
| `Implem.CodeDefiner/Functions/Rds/UsersConfigurator.cs`                        | DBユーザー作成処理     |
| `Implem.CodeDefiner/Functions/Rds/PrivilegeConfigurator.cs`                    | DB権限付与処理         |
| `Implem.Pleasanter/App_Data/Definitions/Sqls/SQLServer/CreateLoginAdmin.sql`   | Owner用ログイン作成SQL |
| `Implem.Pleasanter/App_Data/Definitions/Sqls/SQLServer/CreateLoginUser.sql`    | User用ログイン作成SQL  |
| `Implem.Pleasanter/App_Data/Definitions/Sqls/SQLServer/GrantPrivilegeUser.sql` | User用権限付与SQL      |
| `Implem.Pleasanter/App_Data/Parameters/ExtendedSqls/Sample.json.txt`           | サンプル設定ファイル   |

---

## 関連リンク

- [プリザンター公式マニュアル - 拡張SQL](https://pleasanter.org/manual/extended-sql)
- [Microsoft Docs - リンクサーバー](https://docs.microsoft.com/ja-jp/sql/relational-databases/linked-servers/linked-servers-database-engine)
- [PostgreSQL Documentation - Foreign Data Wrappers](https://www.postgresql.org/docs/current/postgres-fdw.html)
- [PostgreSQL Documentation - CREATE SERVER](https://www.postgresql.org/docs/current/sql-createserver.html)
- [MySQL Documentation - FEDERATED Storage Engine](https://dev.mysql.com/doc/refman/8.0/en/federated-storage-engine.html)
- [MySQL Documentation - CREATE SERVER](https://dev.mysql.com/doc/refman/8.0/en/create-server.html)
