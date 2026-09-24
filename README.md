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
DBへの接続・変更は行いません。通常のディスクベース・非圧縮テーブルを対象とし、
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

## 関連リポジトリ

- [Implem.Pleasanter](https://github.com/Implem/Implem.Pleasanter) - プリザンター本体

## ライセンス

本リポジトリのドキュメントはデュアルライセンスで提供されています。

- **非商用利用**: CC BY-NC-SA 4.0（改変可能）
- **商用利用**: 改変禁止、要事前連絡

詳細は [LICENSE.md](LICENSE.md) を参照してください。

Copyright (c) 2024 PMC Co., Ltd.
