# VehicleVision.Pleasanter.ResearchDocuments

プリザンター（Pleasanter）の内部実装に関する調査ドキュメントを管理するリポジトリです。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [目的](#目的)
- [ドキュメント構成](#ドキュメント構成)
- [使い方](#使い方)
    - [初期セットアップ](#初期セットアップ)
    - [サブモジュール管理](#サブモジュール管理)
    - [目次の更新](#目次の更新)
    - [Markdownの構文チェック](#markdownの構文チェック)
    - [PDF生成](#pdf生成)
    - [SQL Serverの行サイズ簡易計算](#sql-serverの行サイズ簡易計算)
    - [SQL Serverの現状診断](#sql-serverの現状診断)
- [関連リポジトリ](#関連リポジトリ)
- [ライセンス](#ライセンス)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 目的

- プリザンター本体の内部実装に関する知見を蓄積する
- API の動作仕様や制約事項を明確にする
- 既知の問題点や注意事項を文書化する
- 実装方針を決定する際の根拠となる調査結果を残す

## ドキュメント構成

| ディレクトリ         | 説明                            |
| -------------------- | ------------------------------- |
| `docs/`              | 調査ドキュメント本体            |
| `docs/contributing/` | ドキュメント作成ガイドライン    |
| `docs/script/`       | PDF生成・目次更新等のスクリプト |

詳細な一覧は [docs/Home.md](docs/Home.md) を参照してください。

## 使い方

### 初期セットアップ

```bash
# サブモジュールの初期化と依存パッケージのインストールを一括実行
npm run setup
```

または個別に実行：

```bash
# サブモジュール（プリザンター本体リポジトリ）を初期化
npm run submodule:init

# 依存パッケージをインストール
npm install
```

### サブモジュール管理

```bash
# サブモジュールを最新版に更新
npm run submodule:update

# サブモジュールのステータス確認
npm run submodule:status
```

### 目次の更新

```bash
npm run toc:all
```

### Markdownの構文チェック

```bash
npm run lint:md
```

### PDF生成

```bash
npm run pdf
```

### SQL Serverの行サイズ簡易計算

PowerShell 7以降で、項目数と想定データ量から**1行の固定長・可変長・管理領域と、8,060バイトまでの余裕**を計算できます。
この手入力スクリプトはDBへの接続・変更を行いません。通常のディスクベース・非圧縮テーブルを対象とし、
**可変長データをすべて行内に置いた場合の概算**です。行外化後のサイズや保存可否を自動判定するツールではありません。

リポジトリのルートで実行します。

```powershell
& "$PWD/docs/script/Measure-SqlServerRowSize.ps1" `
  -NumCount 10 -NumPrecision 18 -DateCount 10 -CheckCount 8 `
  -ClassCount 20 -ClassBytesPerColumn 40 `
  -DescriptionCount 2 -DescriptionBytesPerColumn 200 `
  -AttachmentCount 1 -AttachmentBytesPerColumn 300
```

この例は固定長171、可変長1,500、管理領域61、合計**1,732バイト**、余裕**6,328バイト**です。
説明用の項目構成であり、Pleasanterの標準列のサイズは含んでいません。

| 引数                                             | 指定内容                                                                  |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| `NumCount` / `NumPrecision`                      | 数値列数／DBのdecimal精度。精度の初期値18は仮定であり、実DDLで確認する    |
| `DateCount`                                      | datetime列数（1列8バイト）                                                |
| `CheckCount`                                     | 標準列を含む全bit列数。8列ごとに1バイト                                   |
| `ClassCount` / `ClassBytesPerColumn`             | 分類列数／1列あたりの保存文字列の想定バイト数                             |
| `DescriptionCount` / `DescriptionBytesPerColumn` | 説明列数／1列あたりの保存文字列の想定バイト数                             |
| `AttachmentCount` / `AttachmentBytesPerColumn`   | 添付列数／1列あたりの保存JSON等の想定バイト数。ファイル本体の容量ではない |
| `OtherFixedCount` / `OtherFixedBytes`            | 上記に含めなかった固定長列数／そのデータサイズの**合計**                  |
| `OtherVariableCount` / `OtherVariableBytes`      | 上記に含めなかった可変長列数／そのデータサイズの**合計**                  |

列数の初期値は0です。文字列・その他の列数を指定した場合は、対応するバイト数も明示してください。
NULLや空文字列ならデータ部分は0ですが、列数には含めます。
固定長列はNULLでも原則として領域を消費します。その他の固定長領域にbitを混ぜず、`CheckCount`にまとめてください。
異なるdecimal精度やdatetime2などは、該当列を`OtherFixedCount`／`OtherFixedBytes`で計上できます。
列数・データ量は二重計上せず、管理領域を入力値に加えないでください。

**計算式と出力**

`EstimatedInlineBytes = FixedBytes + ManagementBytes + VariablePayloadBytes`

- 固定長：decimalの精度1～9は5、10～19は9、20～28は13、29～38は17バイト／列。datetimeは8バイト／列。
- 管理領域：行ヘッダー4＋列数情報2＋NULLビットマップ`ceil(全列数/8)`。
  可変長列があれば、さらに列数情報2＋オフセット配列`2×可変長列数`を加算。
- `RemainingBytes`：8,060から概算を引いた値。負なら、その行内格納の仮定では超過。
- `InlineScenarioFits`：上記の仮定だけで8,060以内かどうか。`True`でも実運用の安全性は保証しない。

末尾のNULLによる管理領域の省略は見込まず、全列を数えます。
圧縮、SPARSE列、行バージョン情報等の追加メタデータや特殊な行形式は扱いません。
8,060バイトぎりぎりの設計は避けてください。

**分類・説明・添付ファイルの見積もり**

| 対象                        | 行内／行外の考え方                                                                                                                         |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 分類の`nvarchar(n)`         | 最大`2n`バイトを常に消費するのではなく、実際の保存文字列で計上する。ROW_OVERFLOWに退避した列は行内に24バイトの参照を残す（オフセットは別） |
| 説明・添付の`nvarchar(max)` | 小さい値は行内に残ることがあり、大きい値などはLOB_DATAに退避する。行内に残るLOB参照構造は格納方式によるため、一律24バイトとはしない        |
| 添付ファイル本体            | `Binaries`や設定された保存先で別に評価する。親レコードでは識別子・ファイル名等の保存文字列を数える                                         |

通常の日本語は概ね1文字2バイトですが、絵文字等は4バイトになる場合があります。
入力値には`LEN`ではなく`DATALENGTH`で調べたバイト数を使い、分類の複数選択では表示ラベルではなく保存値を評価します。
`DATALENGTH`は行外データも含むデータ全体の長さであり、実際の行内占有量ではありません。
列ごとに長さが異なる場合、各グループの最大値を1列あたりの値に指定すれば保守的な見積もりになります。
NULL・空文字列・`[]`は区別し、`[]`はnvarcharで4バイトの非NULLデータです。

ツールはROW_OVERFLOWへの退避を模擬しません。例えば分類100列をすべて行外化できたとしても、
参照2,400＋オフセット200＋NULLビットマップ増加12～13バイト程度が追加で残ります
（元のテーブルに可変長列がなければ列数情報2バイトも必要）。
固定長の数値・日付列は通常のROW_OVERFLOWでは退避できません。
また、非NULLのmax列には**ソート時に1列24バイトの追加固定領域**が必要となる場合があり、
永続化される行のLOB参照と混同できません。この作業領域もツールの計算対象外です。

**Pleasanterで使う際の確認**

1. `sys.columns`／`sys.types`で実DDLを確認し、ID・タイトル・本文・コメント・更新日時等の標準列を含めて入力する。
   画面で非表示にしても物理列はなくならず、画面の小数点表示設定ではdecimalの格納サイズは変わらない。
2. サイトごとに独立した物理テーブルと考えず、`Results`、`Issues`、対応する`_history`／`_deleted`等を個別に評価する。
3. 通常時と最大入力時の両方で計算し、説明の入力上限、分類の最大選択数、添付件数・長いファイル名を考慮する。
4. 本番相当の検証環境で登録・更新・履歴作成・削除・復元・一覧ソート・エクスポートを確認する。
   CodeDefinerの列追加成功だけでは、将来のデータ登録や操作の成功は保証されない。

不足する場合は拡張列数・入力上限の削減や関連テーブルへの分割を検討します。
型変更や行外格納設定だけに頼らず、Pleasanter／CodeDefinerとの整合性も確認してください。

参考：[ROW_OVERFLOW](https://learn.microsoft.com/en-us/sql/relational-databases/pages-and-extents-architecture-guide#large-row-support)、
[nvarcharとmax列の注意事項](https://learn.microsoft.com/en-us/sql/t-sql/data-types/nchar-and-nvarchar-transact-sql)、
[decimalの格納サイズ](https://learn.microsoft.com/en-us/sql/t-sql/data-types/decimal-and-numeric-transact-sql)。

### SQL Serverの現状診断

手入力の代わりに、PowerShell 7以降の`Get-SqlServerRowDiagnostics.ps1`で、SQL Server 2016以降を対象に
**実DBの列定義・保存データ量・行外領域の使用状況**を確認できます。
既存の簡易計算とは別のスクリプトです。SQL Serverへの問い合わせは読み取りのみで、
テーブル変更や設定変更は行いません。取得結果に業務データ本文は出力しません。

リポジトリのルートで、接続先・DB・対象の物理テーブルを指定します。

```powershell
$report = & "$PWD/docs/script/Get-SqlServerRowDiagnostics.ps1" `
  -Server "sqlserver.example.local" -Database "Pleasanter" `
  -Schema "dbo" -Table "Results" -IncludeRelated
$report | ConvertTo-Json -Depth 8
```

SQL Server認証を使用する場合は、パスワードをコマンドに直書きせず対話入力します。

```powershell
$credential = Get-Credential
$report = & "$PWD/docs/script/Get-SqlServerRowDiagnostics.ps1" `
  -Server "sqlserver.example.local" -Database "Pleasanter" `
  -Table "Issues" -Credential $credential
$report | ConvertTo-Json -Depth 8
```

| 引数                            | 内容                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------- |
| `Server` / `Database` / `Table` | 必須。接続先、DB名、物理テーブル名。`Table`にはスキーマを含めない                           |
| `Schema`                        | スキーマ名。初期値`dbo`                                                                     |
| `Credential`                    | SQL Server認証用の`PSCredential`。省略時は統合認証。Windows以外では統合認証の事前設定が必要 |
| `IncludeRelated`                | 指定テーブルと同じスキーマの`_history`・`_deleted`も個別に診断                              |
| `SampleRows`                    | 軽量確認の取得行数上限。初期値1,000、指定範囲1～100,000                                     |
| `Detailed`                      | データの全行集計と、物理レコードサイズ統計の詳細取得を行う                                  |
| `CommandTimeout`                | 各問い合わせのタイムアウト秒数。初期値30、指定範囲1～600                                    |

接続は暗号化し、サーバー証明書を検証します。サーバー名と証明書が一致し、
実行端末で証明書チェーンを信頼できる状態にしてください。検証を無効化するオプションはありません。
接続タイムアウトは15秒です。既存の.NET SQLクライアントを使用し、追加PowerShellモジュールは不要です。

**軽量確認と詳細確認**

| 内容                                              | 通常実行（軽量）   | `-Detailed`                                        |
| ------------------------------------------------- | ------------------ | -------------------------------------------------- |
| 列定義・固定長／管理領域の概算                    | 取得               | 取得                                               |
| 行数の概数、IN_ROW／ROW_OVERFLOW／LOBの使用ページ | DMVから取得        | DMVから取得                                        |
| 可変長データの`DATALENGTH`集計                    | 最大`SampleRows`行 | 全行                                               |
| 物理レコードサイズの統計                          | 取得しない         | `sys.dm_db_index_physical_stats`の`DETAILED`で取得 |

通常実行の抽出はランダムサンプルではありません。サンプル外の長いデータを見落とすため、
サンプルの最大値をテーブル全体の最大値として扱わないでください。
行数の上限は読み取りバイト数・I/Oの上限ではなく、大きいLOBを持つ行では軽量確認でも負荷がかかります。
詳細確認は全行・物理ページを走査するため、まず検証環境で実行し、本番では低負荷時間帯に限定してください。
読み取りでもロック待ちや、可用性グループのセカンダリでREDOを妨げる可能性があります。

**結果の読み方**

テーブルごとに1つのオブジェクトを返します。各セクションは`Status`・`Reason`・`Data`を持ち、
`Columns`のみ列定義の配列です。

| 出力                   | 確認する内容                                                                   |
| ---------------------- | ------------------------------------------------------------------------------ |
| `Metadata` / `Columns` | テーブルの格納形式、各列の実型・長さ・精度・NULL可否等                         |
| `Budget`               | 列定義から求めた固定長・管理領域。可変長の宣言最大長まで行内に置く仮定の概算   |
| `Allocation`           | パーティション別と合計の行数概数、行内・ROW_OVERFLOW・LOBの使用ページ数        |
| `Payload`              | 対象行数、行ごとの可変長データ合計の平均・最大、列ごとの非NULL件数・平均・最大 |
| `PhysicalStats`        | 詳細確認時のパーティション別の物理レコード件数と最小・平均・最大サイズ         |

- 実際の型・精度と格納対象列から固定長部分と管理領域を算出します。
  通常の行形式で計算できない型・圧縮等では、概算を不明として理由を示します。
- `nvarchar(max)`等があっても、通常の行形式なら固定長・管理領域は表示します。
  可変長全体の宣言最大長が確定しないため、この場合の`Budget.Status`は`Partial`、
  合計サイズ・残りバイト数・収まるかの判定は未確定です。
  固定長と管理領域だけの値には、可変長データや行外参照を一切含めません。
- 行外領域はヒープ／クラスタ化インデックスを対象とし、非クラスタ化インデックス分は合算しません。
  使用ページが正ならその領域の使用が確認できますが、行外化した列・行の特定や正確な件数を示す値ではありません。
- `DATALENGTH`は行外部分も含む保存データ量であり、行内占有量ではありません。
  添付項目の保存JSONは対象ですが、別テーブルやファイルストレージの添付本体は含みません。
  計測対象は格納される可変長文字列・バイナリ列です。行合計ではNULLを0とし、列ごとの平均ではNULLを除外します。
  行の最大値は同一行の合計から算出し、各列の最大値を足した値とは区別します。
  計測対象に暗号化列や動的データマスキング列がある場合、誤ったサイズを表示しないよう`Payload`を取得不可とします。
  テーブル内にマスキング列があり、計測対象に永続化された計算列がある場合も、マスキングの継承を考慮して取得不可とします。
  マスキング列は`UNMASK`権限の有無にかかわらず対象外です。
- 詳細確認の物理統計はパーティション別の結果として確認します。
  格納済みレコードの大きさであって、将来の入力やソート時の作業領域を保証するものではありません。
- 権限不足・タイムアウト等は「取得不可」として扱い、0バイトや行外格納なしとは判定しません。
  指定テーブルが見えない場合はエラー、任意の履歴・削除テーブルが見えない場合は警告になります。
- 空テーブルはデータの最大値・平均値が未定義です。軽量モードの物理統計も未取得として区別します。

**必要な権限と制約**

対象テーブルの`SELECT`と列定義の参照権限が必要です。DMVには別途参照権限が必要で、
`sys.dm_db_partition_stats`はSQL Server 2019以前では`VIEW DATABASE STATE`と`VIEW DEFINITION`、
SQL Server 2022以降では`VIEW DATABASE PERFORMANCE STATE`と`VIEW SECURITY DEFINITION`を要求します。
物理統計の必要権限はSQL Serverのバージョン・対象範囲によって異なります。
DB管理者に必要最小限の権限を確認し、管理者権限や書き込み権限を安易に付与しないでください。

問い合わせは一括したスナップショットではないため、更新中のDBでは各結果の取得時点が異なります。
保存データの集計対象は実行ユーザーに見える行です。行レベルセキュリティで除外された行は詳細確認でも含まれず、
パーティション全体の行数・物理統計とは範囲が異なる場合があります。
列削除後の物理領域、行バージョン情報等は列定義ベースの概算に反映されない場合があります。
**「現状を確認する」診断であり、「あと何項目まで安全に追加できるか」を保証するものではありません。**
項目拡張前には最大入力時と登録・更新・履歴・削除・復元・一覧ソート等の動作も検証してください。

参考：[パーティション使用状況と権限](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-partition-stats-transact-sql)、
[物理レコード統計と負荷・権限](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-index-physical-stats-transact-sql)。

## 関連リポジトリ

- [Implem.Pleasanter](https://github.com/Implem/Implem.Pleasanter) - プリザンター本体

## ライセンス

本リポジトリのドキュメントはデュアルライセンスで提供されています。

- **非商用利用**: CC BY-NC-SA 4.0（改変可能）
- **商用利用**: 改変禁止、要事前連絡

詳細は [LICENSE.md](LICENSE.md) を参照してください。

Copyright (c) 2024 PMC Co., Ltd.
