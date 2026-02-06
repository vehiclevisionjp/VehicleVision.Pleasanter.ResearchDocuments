# Copilot Instructions

このリポジトリは **VehicleVision.Pleasanter.ResearchDocuments** - プリザンター内部実装に関する調査ドキュメントを管理するリポジトリです。

## プロジェクト情報

- **目的**: プリザンター本体の内部実装に関する知見を蓄積
- **形式**: Markdown ドキュメント
- **言語**: 日本語

## コントリビューションガイドライン

ドキュメントを作成・変更する際は、以下のガイドラインを必ず参照すること：

| ガイドライン | パス                                                      | 内容                               |
| ------------ | --------------------------------------------------------- | ---------------------------------- |
| リサーチ     | [research-guidelines.md](docs/contributing/research-guidelines.md) | 調査ドキュメントの構成、命名規則 |

## ドキュメント作成時のルール

- 新しいドキュメントを追加した場合は、`docs/Home.md` のドキュメント一覧も併せて更新すること
- `npm run toc:all` で目次とフォーマットを更新すること
- ファイル名は `pleasanter-{調査対象}-{調査内容}.md` の形式にすること

## プリザンター本体コードの参照

プリザンター本体のコードを参照する必要がある場合は、以下の順序で参照すること：

1. **ローカルリポジトリ**: `local.config.json` で指定されたパス、またはワークスペースに `Implem.Pleasanter` フォルダが存在する場合はそちらを優先
2. **公式GitHubリポジトリ**: [Implem/Implem.Pleasanter](https://github.com/Implem/Implem.Pleasanter)

### ローカルリポジトリの設定

リポジトリルートに `local.config.json` を作成し、以下の形式で指定する（`.gitignore` に追加済みのためコミットされない）：

```json
{
    "pleasanterRepoPath": "D:\\repos\\Implem.Pleasanter"
}
```

## 出力ルール

- 優先順位や処理の都合上、指示されたタスクの一部を実行しない・できない場合は、その旨を明示的にPromptで出力すること
- 省略した内容と理由を簡潔に説明し、必要に応じて後続の対応を提案すること
