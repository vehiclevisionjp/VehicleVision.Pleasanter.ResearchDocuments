# VehicleVision.Pleasanter.ResearchDocuments

プリザンター（Pleasanter）の内部実装に関する調査ドキュメントを管理するリポジトリです。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [VehicleVision.Pleasanter.ResearchDocuments](#vehiclevisionpleasanterresearchdocuments)
  - [目的](#目的)
  - [ドキュメント構成](#ドキュメント構成)
  - [使い方](#使い方)
    - [初期セットアップ](#初期セットアップ)
    - [サブモジュール管理](#サブモジュール管理)
    - [目次の更新](#目次の更新)
    - [Markdownの構文チェック](#markdownの構文チェック)
    - [PDF生成](#pdf生成)
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

## 関連リポジトリ

- [Implem.Pleasanter](https://github.com/Implem/Implem.Pleasanter) - プリザンター本体

## ライセンス

本リポジトリのドキュメントはデュアルライセンスで提供されています。

- **非商用利用**: CC BY-NC-SA 4.0（改変可能）
- **商用利用**: 改変禁止、要事前連絡

詳細は [LICENSE.md](LICENSE.md) を参照してください。

Copyright (c) 2024 PMC Co., Ltd.
