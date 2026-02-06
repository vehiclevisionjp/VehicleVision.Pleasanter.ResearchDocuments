# コントリビューションガイド

このリポジトリへの貢献に関するガイドラインです。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [ドキュメントの追加](#ドキュメントの追加)
- [ドキュメント作成規約](#ドキュメント作成規約)
- [コミット前のチェック](#コミット前のチェック)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## ドキュメントの追加

1. `docs/` ディレクトリに新しいMarkdownファイルを作成
2. [リサーチガイドライン](docs/contributing/research-guidelines.md)に従ってドキュメントを作成
3. `npm run toc:all` で目次とフォーマットを更新
4. `docs/Home.md` のドキュメント一覧に追記
5. プルリクエストを作成

## ドキュメント作成規約

詳細は [docs/contributing/research-guidelines.md](docs/contributing/research-guidelines.md) を参照してください。

### ファイル命名規則

```text
pleasanter-{調査対象}-{調査内容}.md
```

### 必須セクション

- タイトル（H1）
- 概要説明
- doctoc マーカー
- 調査情報（テーブル形式）
- 調査目的
- 調査内容
- 結論

## コミット前のチェック

```bash
# 目次とフォーマットの更新
npm run toc:all

# 構文チェック
npm run lint:md
```
