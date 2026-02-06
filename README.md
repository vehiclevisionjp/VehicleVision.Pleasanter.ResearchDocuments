# VehicleVision.Pleasanter.ResearchDocuments

プリザンター（Pleasanter）の内部実装に関する調査ドキュメントを管理するリポジトリです。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [目的](#目的)
- [ドキュメント構成](#ドキュメント構成)
- [使い方](#使い方)
- [関連リポジトリ](#関連リポジトリ)
- [ライセンス](#ライセンス)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 目的

- プリザンター本体の内部実装に関する知見を蓄積する
- API の動作仕様や制約事項を明確にする
- 既知の問題点や注意事項を文書化する
- 実装方針を決定する際の根拠となる調査結果を残す

## ドキュメント構成

| ディレクトリ       | 説明                               |
| ------------------ | ---------------------------------- |
| `docs/`            | 調査ドキュメント本体               |
| `docs/contributing/` | ドキュメント作成ガイドライン       |
| `docs/script/`     | PDF生成・目次更新等のスクリプト    |

詳細な一覧は [docs/Home.md](docs/Home.md) を参照してください。

## 使い方

### 初期セットアップ

```bash
npm install
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

- [PleasanterDeveloperCommunity.DotNet.Client](https://github.com/pleasanter-developer-community/PleasanterDeveloperCommunity.DotNet.Client) - プリザンター API の .NET クライアントライブラリ
- [Implem.Pleasanter](https://github.com/Implem/Implem.Pleasanter) - プリザンター本体

## ライセンス

MIT License

Copyright (c) 2026 VehicleVision Japan
