# Markdown 実装

プリザンターにおける Markdown の実装を網羅的に調査した結果をまとめる。サーバーサイド（C#）とクライアントサイド（TypeScript/JavaScript）の両面から、使用ライブラリ・変換フロー・セキュリティ対策・設定項目を整理する。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [アーキテクチャ概要](#アーキテクチャ概要)
- [使用ライブラリ](#使用ライブラリ)
    - [クライアントサイド](#クライアントサイド)
    - [サーバーサイド](#サーバーサイド)
- [主要クラス・ファイル一覧](#主要クラスファイル一覧)
    - [サーバーサイド（C# — HTML 構造の生成）](#サーバーサイドc--html-構造の生成)
    - [クライアントサイド（TypeScript — Markdown 変換の実処理）](#クライアントサイドtypescript--markdown-変換の実処理)
- [Markdown 変換フロー](#markdown-変換フロー)
    - [サーバーサイド：HTML 構造の生成](#サーバーサイドhtml-構造の生成)
    - [クライアントサイド：Markdown から HTML への変換](#クライアントサイドmarkdown-から-html-への変換)
- [`[md]` プレフィックスの仕組み](#md-プレフィックスの仕組み)
- [サポート構文](#サポート構文)
    - [`[md]` モード（Markdown フルレンダリング）](#md-モードmarkdown-フルレンダリング)
    - [Notes モード（`[md]` プレフィックスなし）](#notes-モードmd-プレフィックスなし)
    - [特殊リンク処理](#特殊リンク処理)
- [サニタイズ / セキュリティ対策](#サニタイズ--セキュリティ対策)
    - [クライアントサイド](#クライアントサイド-1)
    - [サーバーサイド](#サーバーサイド-1)
- [Markdown が使われる場面](#markdown-が使われる場面)
    - [フィールド / 画面での使用箇所](#フィールド--画面での使用箇所)
    - [ControlType のフロー](#controltype-のフロー)
- [設定項目](#設定項目)
    - [Column クラスの Markdown 関連設定](#column-クラスの-markdown-関連設定)
    - [ViewerSwitchingTypes（ビューア切替モード）](#viewerswitchingtypesビューア切替モード)
    - [data 属性によるクライアント設定](#data-属性によるクライアント設定)
- [コードブロックのシンタックスハイライト](#コードブロックのシンタックスハイライト)
- [画像アップロード](#画像アップロード)
- [GitHub Flavored Markdown（GFM）との機能差分](#github-flavored-markdowngfmとの機能差分)
    - [前提条件](#前提条件)
    - [差分一覧](#差分一覧)
    - [移行時の注意点](#移行時の注意点)
    - [差分の概念図](#差分の概念図)
- [Mermaid.js 対応の詳細調査](#mermaidjs-対応の詳細調査)
    - [Mermaid.js の配置場所](#mermaidjs-の配置場所)
    - [Mermaid.js の実際の利用箇所](#mermaidjs-の実際の利用箇所)
    - [サーバーサイドの Mermaid テキスト生成](#サーバーサイドの-mermaid-テキスト生成)
    - [PleasanterExtensions パラメータ](#pleasanterextensions-パラメータ)
    - [Markdown フィールドとの関係](#markdown-フィールドとの関係)
    - [アーキテクチャ図](#アーキテクチャ図)
    - [結論（Mermaid 対応）](#結論mermaid-対応)
- [結論](#結論)
- [関連ソースコード](#関連ソースコード)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 調査情報

| 調査日        | リポジトリ | ブランチ | タグ/バージョン    | コミット   | 備考     |
| ------------- | ---------- | -------- | ------------------ | ---------- | -------- |
| 2026年2月23日 | Pleasanter | main     | Pleasanter_1.5.1.0 | `34f162a4` | 初回調査 |

## 調査目的

プリザンター上で Markdown がどのように処理されるかを把握し、以下を明確にする。

- Markdown 変換に使用されるライブラリ（サーバー・クライアント双方）
- 変換フローとアーキテクチャ
- サポート構文と非サポート構文
- サニタイズ・セキュリティ対策
- カスタマイズ可能な設定項目

---

## アーキテクチャ概要

プリザンターの Markdown 処理は**クライアントサイド中心**のアーキテクチャである。

```mermaid
sequenceDiagram
    participant Server as サーバーサイド (C#)
    participant Browser as ブラウザ
    participant WC as markdown-field<br>(Web Component)
    participant Marked as marked.js
    participant DOMPurify as DOMPurify

    Server->>Browser: HTML レスポンス<br>（&lt;markdown-field&gt; + &lt;textarea&gt;）
    Browser->>WC: Custom Element 初期化
    WC->>WC: テキスト値を取得
    WC->>Marked: Markdown パース
    Marked-->>WC: HTML 文字列
    WC->>DOMPurify: サニタイズ
    DOMPurify-->>WC: 安全な HTML
    WC->>Browser: innerHTML にセット（プレビュー表示）
```

**重要な特徴**:

- サーバーサイドには Markdig 等の Markdown パーサーライブラリは**含まれていない**
- サーバーは `<markdown-field>` カスタム HTML タグと `<textarea>` を生成するのみ
- Markdown → HTML 変換はすべて**クライアントサイド**（ブラウザ上）で実行される

---

## 使用ライブラリ

### クライアントサイド

| ライブラリ       | 用途                                   | インポート元                        |
| ---------------- | -------------------------------------- | ----------------------------------- |
| **marked**       | Markdown → HTML 変換                   | `import { Marked } from 'marked'`   |
| **DOMPurify**    | HTML サニタイズ（XSS 対策）            | `import DOMPurify from 'dompurify'` |
| **highlight.js** | コードブロックのシンタックスハイライト | `import hljs from 'highlight.js'`   |

> **補足**: `wwwroot/Extensions/mermaid-11.9.0.min.js`（Mermaid.js v11.9.0）が配置されているが、
> これは Site Visualizer（サイト設定可視化ツール）の ER 図描画専用であり、
> Markdown フィールドの `markdownField.ts` からは参照・使用されていない。
> 詳細は「[Mermaid.js 対応の詳細調査](#mermaidjs-対応の詳細調査)」を参照。

### サーバーサイド

**Markdown 変換ライブラリは使用していない。**

`Implem.Pleasanter.csproj` の NuGet パッケージに Markdig やその他の Markdown パーサーは含まれていない。サーバーサイドは HTML 構造の生成のみを担当する。

---

## 主要クラス・ファイル一覧

### サーバーサイド（C# — HTML 構造の生成）

| クラス / メソッド            | ファイルパス                                            | 役割                                                                    |
| ---------------------------- | ------------------------------------------------------- | ----------------------------------------------------------------------- |
| `HtmlTags.MarkdownField()`   | `Implem.Pleasanter/Libraries/HtmlParts/HtmlTags.cs`     | `<markdown-field>` カスタムタグを出力                                   |
| `HtmlControls.MarkDown()`    | `Implem.Pleasanter/Libraries/HtmlParts/HtmlControls.cs` | Markdown フィールドの `<textarea>` と属性を組み立て                     |
| `HtmlFields.FieldMarkDown()` | `Implem.Pleasanter/Libraries/HtmlParts/HtmlFields.cs`   | ラベル付き Markdown フィールドをレンダリング                            |
| `HtmlComments`               | `Implem.Pleasanter/Libraries/HtmlParts/HtmlComments.cs` | コメント欄の Markdown フィールド生成                                    |
| `HtmlGuides`                 | `Implem.Pleasanter/Libraries/HtmlParts/HtmlGuides.cs`   | ガイド（説明文）の Markdown 表示                                        |
| `Column`                     | `Implem.Pleasanter/Libraries/Settings/Column.cs`        | `FieldCss`, `ControlType`, `ViewerSwitchingType`, `AllowImage` 等の設定 |
| 各モデル `*Utilities.cs`     | `Implem.Pleasanter/Models/*/`                           | Body フィールドの `ControlType` を `"MarkDown"` に設定                  |

### クライアントサイド（TypeScript — Markdown 変換の実処理）

| クラス / ファイル      | パス                                                                                     | 役割                                                                                  |
| ---------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `MarkdownFieldElement` | `Implem.PleasanterFrontend/wwwroot/src/scripts/modules/markdownField/markdownField.ts`   | **中核**: Web Component として `<markdown-field>` を定義し、Markdown 変換・表示を担当 |
| `markdownField.scss`   | `Implem.PleasanterFrontend/wwwroot/src/scripts/modules/markdownField/markdownField.scss` | Markdown フィールドのスタイル定義                                                     |

---

## Markdown 変換フロー

### サーバーサイド：HTML 構造の生成

サーバーサイドでは、Markdown の変換は行わず、HTML の骨格を生成する。

**ファイル**: `Implem.Pleasanter/Libraries/HtmlParts/HtmlTags.cs`（行番号: 834-848）

```csharp
public static HtmlBuilder MarkdownField(
    this HtmlBuilder hb,
    HtmlAttributes attributes = null,
    string text = null,
    bool _using = true,
    Action action = null)
{
    return _using
        ? hb.Append(
            tag: "markdown-field",
            attributes: (attributes ?? new HtmlAttributes()),
            action: action)
        : hb;
}
```

`HtmlControls.MarkDown()` メソッドが `MarkdownField()` を呼び出し、内部に `<textarea>` を配置する。

**ファイル**: `Implem.Pleasanter/Libraries/HtmlParts/HtmlControls.cs`（行番号: 273-340）

```csharp
public static HtmlBuilder MarkDown(
    this HtmlBuilder hb,
    Context context,
    SiteSettings ss,
    string controlId = null,
    string controlCss = null,
    string text = null,
    // ... 省略
    Action action = null)
{
    // ...
    hb.MarkdownField(
        action: () => {
            action?.Invoke();
            hb.TextArea(
                // ...
                attributes: new HtmlAttributes()
                    .Id(controlId)
                    .Name(controlId)
                    .Class(Css.Class("control-markdown" + ...))
                    .DataViewerType(viewerTypesValue)
                    .DataComment(comment)
                    .DataReadOnly(readOnly)
                    // ...
            );
        }
    );
    return hb;
}
```

生成される HTML の基本構造:

```html
<markdown-field>
    <textarea id="Body" class="control-markdown upload-image" data-viewer-type="auto" data-enablelightbox="1">
    (Markdownテキスト)
  </textarea
    >
</markdown-field>
```

### クライアントサイド：Markdown から HTML への変換

`MarkdownFieldElement` クラスが Web Component として `<markdown-field>` を定義し、以下の処理を行う。

**ファイル**: `Implem.PleasanterFrontend/wwwroot/src/scripts/modules/markdownField/markdownField.ts`

#### 1. marked.js の初期化（行番号: 155-168）

```typescript
private viewerMarked? = new Marked({
    gfm: true,
    breaks: true,
    renderer: {
        html: token => this.escapeHtml(token.text),
        link: token => this.mdRenderLink(token),
        image: token => this.mdRenderImage(token),
        code: token => this.mdRenderCode(token)
    }
});
```

- **GFM（GitHub Flavored Markdown）** が有効
- **改行の自動変換**（`breaks: true`）が有効
- `html` レンダラーは HTML タグをエスケープ（生 HTML は無効化）
- カスタムレンダラーでリンク・画像・コードブロックの出力をカスタマイズ

#### 2. 表示モード切替と `[md]` プレフィックス（行番号: 305-322）

```typescript
public showViewer() {
    if (this.controller.value || this.isReadonly || this.isComment) {
        let md = this.controller.value;
        md = this.encodeCustomSchemeLink(md);
        if (md.indexOf('[md]') === 0) {
            md = md.split('\n').slice(1).join('\n');
            md = String(this.viewerMarked!.parse(md));
        } else {
            const tokens = this.viewerMarked?.lexer(this.escapeMarkdown(md));
            md = tokens!.map(token => this.notesRender(token)).join('');
            md = `<div class="notes">${md}<br></div>`;
        }
        md = this.createCustomSchemeLink(md);
        md = md.replace(/&amp;#(\d+);/g, '&#$1;');
        md = DOMPurify.sanitize(md, {
            ADD_ATTR: ['target']
        });
        this.viewerElem!.innerHTML = md;
        this.finalizeViewerDom();
    }
}
```

**2 つのレンダリングモード**:

| モード                         | 条件                       | 処理                                                                      |
| ------------------------------ | -------------------------- | ------------------------------------------------------------------------- |
| **Markdown モード**            | テキストが `[md]` で始まる | 2行目以降を `marked.parse()` で完全な Markdown として変換                 |
| **Notes モード**（デフォルト） | `[md]` プレフィックスなし  | Markdown 構文をエスケープした上で簡易レンダリング（リンク・画像のみ処理） |

---

## `[md]` プレフィックスの仕組み

プリザンターでは、テキストフィールドの先頭に `[md]` と記述することで、Markdown のフルレンダリングが有効になる。

| 入力テキスト                       | レンダリング結果                       |
| ---------------------------------- | -------------------------------------- |
| `通常のテキスト`                   | プレーンテキスト表示（リンクのみ処理） |
| `[md]`<br>`# 見出し`<br>`**太字**` | Markdown として変換・表示              |

`[md]` がない場合は「Notes モード」となり、Markdown 構文文字（`#`, `*`, `_`, `` ` `` 等）はエスケープされるため、Markdown として解釈されない。

---

## サポート構文

### `[md]` モード（Markdown フルレンダリング）

`marked.js` の GFM モードが有効なため、以下の構文がサポートされる。

| 構文                              | サポート | 備考                                          |
| --------------------------------- | :------: | --------------------------------------------- |
| 見出し (`#`, `##`, ...)           |   Yes    |                                               |
| 太字・斜体 (`**`, `*`, `__`, `_`) |   Yes    |                                               |
| 取り消し線 (`~~`)                 |   Yes    | GFM                                           |
| リンク (`[text](url)`)            |   Yes    | カスタムレンダラーで処理                      |
| 画像 (`![alt](url)`)              |   Yes    | サムネイル表示（`?thumbnail=1`）              |
| コードブロック (` ``` `)          |   Yes    | highlight.js によるシンタックスハイライト付き |
| インラインコード (`` ` ``)        |   Yes    |                                               |
| 箇条書き（番号なし）              |   Yes    |                                               |
| 箇条書き（番号付き）              |   Yes    |                                               |
| テーブル                          |   Yes    | GFM                                           |
| 引用 (`>`)                        |   Yes    |                                               |
| 水平線 (`---`)                    |   Yes    |                                               |
| タスクリスト (`- [ ]`, `- [x]`)   |   Yes    | GFM                                           |
| 改行（通常の改行）                |   Yes    | `breaks: true` 設定により                     |
| **生の HTML**                     |  **No**  | `html` レンダラーでエスケープ                 |

### Notes モード（`[md]` プレフィックスなし）

| 構文                        | サポート | 備考                                  |
| --------------------------- | :------: | ------------------------------------- |
| リンク (`[text](url)`)      |   Yes    |                                       |
| 画像 (`![alt](url)`)        |   Yes    |                                       |
| UNC パス (`\\server\share`) |   Yes    | `file://` リンクに変換                |
| Notes リンク (`notes://`)   |   Yes    | IBM Notes プロトコル                  |
| その他の Markdown 構文      |  **No**  | `escapeMarkdown()` でエスケープされる |

### 特殊リンク処理

`MarkdownFieldElement` は以下の特殊なリンク形式を処理する。

| リンク形式                       | 処理                                        |
| -------------------------------- | ------------------------------------------- |
| UNC パス (`\\server\share\path`) | `file://` スキームに変換して `<a>` タグ生成 |
| Notes リンク (`notes://xxx`)     | そのまま `<a>` タグ生成                     |
| 通常の URL                       | 標準的な `<a href="...">` を生成            |

---

## サニタイズ / セキュリティ対策

### クライアントサイド

プリザンターの Markdown 処理には**多層のセキュリティ対策**がある。

#### 1. HTML タグの無効化（marked.js レンダラー）

```typescript
renderer: {
    html: token => this.escapeHtml(token.text),
}
```

`marked.js` の `html` レンダラーをオーバーライドし、HTML タグは `escapeHtml()` でエスケープされる。これにより Markdown 内の生 HTML（`<script>` 等）は無害化される。

#### 2. `escapeHtml()` によるエスケープ

```typescript
private escapeHtml(str: string): string {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}
```

#### 3. DOMPurify による最終サニタイズ

```typescript
md = DOMPurify.sanitize(md, {
    ADD_ATTR: ['target'],
});
```

`marked.js` の出力に対して `DOMPurify.sanitize()` を適用。`target` 属性のみ追加許可。

#### 4. Notes モードの `escapeMarkdown()`

Notes モード（`[md]` なし）では、Markdown 構文文字を事前にエスケープすることで、意図しない HTML 変換を防止する。

#### 5. `finalizeViewerDom()` による後処理

コードブロック内のリンクをテキストノードに置換し、コードブロック内でリンクが有効にならないようにする。

### サーバーサイド

| 対策                         | 内容                                                                          |
| ---------------------------- | ----------------------------------------------------------------------------- |
| X-XSS-Protection ヘッダー    | `Startup.cs` で `X-Xss-Protection: 1; mode=block` を設定                      |
| サーバー側 Markdown 変換なし | サーバーは Markdown を HTML に変換しないため、サーバー側での XSS リスクは低い |

---

## Markdown が使われる場面

### フィールド / 画面での使用箇所

| 使用箇所                 | 説明                                               | ControlType                                        |
| ------------------------ | -------------------------------------------------- | -------------------------------------------------- |
| **Body フィールド**      | Issues / Results / Wiki のメインテキスト           | `FieldCss == "field-markdown"` の場合 `"MarkDown"` |
| **Description 型カラム** | カスタムの説明フィールド                           | `FieldCss` の設定次第                              |
| **コメント欄**           | レコードのコメント入力                             | `control-markdown` クラス                          |
| **ガイド（説明文）**     | `GridGuide` / `EditorGuide` / `CalendarGuide` 等   | `HtmlGuides` で Markdown フィールドとして表示      |
| **サイト設定の各種説明** | `AddressBook`, `MailToDefault`, `MailCcDefault` 等 | `FieldMarkDown()` で表示                           |
| **TitleBody**            | タイトルと本文の複合表示                           | `ControlType` が `"MarkDown"` or `"RTEditor"`      |
| **ダッシュボード**       | ダッシュボードのカスタムコンテンツ                 | `.MarkDown()` で表示                               |

### ControlType のフロー

エディタタイプの決定ロジック:

```mermaid
flowchart TD
    A[カラムの FieldCss を確認] --> B{FieldCss の値}
    B -->|field-markdown| C[ControlType = MarkDown]
    B -->|field-rte| D[ControlType = RTEditor]
    B -->|field-wide| E[ControlType = Normal（幅広テキスト）]
    B -->|field-normal / 空| F[ControlType = Normal]
    C --> G[MarkdownFieldElement で表示]
    D --> H[RichTextEditor で表示]
```

---

## 設定項目

### Column クラスの Markdown 関連設定

**ファイル**: `Implem.Pleasanter/Libraries/Settings/Column.cs`

| プロパティ            | 型                      | 説明                                                                        |
| --------------------- | ----------------------- | --------------------------------------------------------------------------- |
| `FieldCss`            | `string`                | `"field-markdown"` で Markdown モード、`"field-rte"` でリッチテキストモード |
| `ControlType`         | `string`                | `"MarkDown"` / `"RTEditor"` / `"Normal"` 等                                 |
| `ViewerSwitchingType` | `ViewerSwitchingTypes?` | ビューア切替の動作モード                                                    |
| `AllowImage`          | `bool?`                 | 画像アップロードの許可                                                      |

### ViewerSwitchingTypes（ビューア切替モード）

**ファイル**: `Implem.Pleasanter/Libraries/Settings/Column.cs`（行番号: 31-35）

```csharp
public enum ViewerSwitchingTypes
{
    Auto = 1,
    Manual = 2,
    Disabled = 3
}
```

| 値         | 動作                                                       |
| ---------- | ---------------------------------------------------------- |
| `Auto`     | エディタからフォーカスが外れると自動でプレビュー表示に切替 |
| `Manual`   | ビューア切替ボタンをクリックして手動で切替                 |
| `Disabled` | プレビュー表示を無効化し、常にエディタ表示                 |

### data 属性によるクライアント設定

サーバーが `<textarea>` に付与する data 属性:

| data 属性                  | 説明                                                      |
| -------------------------- | --------------------------------------------------------- |
| `data-viewer-type`         | `"auto"` / `"manual"` / `"disabled"` — ビューア切替モード |
| `data-readonly`            | 読み取り専用フラグ                                        |
| `data-comment`             | コメント欄フラグ                                          |
| `data-camera-disabled`     | カメラ（写真撮影）の無効化                                |
| `data-enablelightbox`      | 画像のライトボックス表示の有効/無効                       |
| `data-validate-max-length` | 最大文字数バリデーション                                  |
| `data-validate-required`   | 必須入力バリデーション                                    |
| `data-validate-regex`      | 正規表現バリデーション                                    |

---

## コードブロックのシンタックスハイライト

`markdownField.ts` の `mdRenderCode()` メソッドで highlight.js を使用。

```typescript
private mdRenderCode = (token: Tokens.Code) => {
    const lang = (token.lang || '').trim();
    let highlighted: string;
    if (lang && hljs.getLanguage(lang)) {
        highlighted = hljs.highlight(token.text, { language: lang }).value;
    } else {
        highlighted = hljs.highlightAuto(token.text).value;
    }
    // コピーボタン付きのコードブロック HTML を生成
};
```

- 言語指定があれば指定言語でハイライト
- 言語指定がなければ自動検出（`highlightAuto`）
- コピーボタンが付与される

---

## 画像アップロード

Markdown フィールドでは、以下の方法で画像を挿入できる。

| 方法                   | 説明                                                          |
| ---------------------- | ------------------------------------------------------------- |
| ファイル選択ボタン     | ファイルダイアログから画像選択                                |
| クリップボード貼り付け | `Ctrl+V` で画像を直接貼り付け                                 |
| カメラ撮影             | モバイルカメラで撮影（`EnableMobileCamera` パラメータで制御） |

許可される画像形式:

```typescript
static ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'];
```

画像は `binaries/uploadimage` または `formbinaries/uploadimage` エンドポイントにアップロードされ、Markdown の `![alt](url)` 形式でテキストに挿入される。

表示時には URL に `?thumbnail=1` パラメータが付与され、サムネイル画像が表示される。

---

## GitHub Flavored Markdown（GFM）との機能差分

GitHub.com で使用される Markdown と、プリザンターの `[md]` モードでの Markdown 実装を比較する。プリザンターは `marked.js` の GFM モードを使用しているため、GFM 仕様の多くを踏襲しているが、カスタムレンダラーやセキュリティ対策により差異が生じている。

### 前提条件

| 項目       | GitHub.com                            | Pleasanter (v1.5.1.0)                   |
| ---------- | ------------------------------------- | --------------------------------------- |
| パーサー   | 独自実装（cmark-gfm 派生）            | marked.js v17（クライアントサイド）     |
| ベース仕様 | GFM 仕様（CommonMark スーパーセット） | `gfm: true` / `breaks: true`            |
| サニタイズ | サーバーサイドで独自サニタイズ        | DOMPurify + `html` レンダラーエスケープ |
| 動作環境   | サーバーサイドレンダリング            | クライアントサイドレンダリング          |
| 有効化方法 | 常に Markdown として処理              | `[md]` プレフィックス必須               |

### 差分一覧

#### 基本構文（CommonMark / GFM 共通）

| 構文                            | GitHub |   Pleasanter    | 差異の詳細                                                          |
| ------------------------------- | :----: | :-------------: | ------------------------------------------------------------------- |
| ATX 見出し (`#`, `##`, ...)     |  Yes   |       Yes       | 同等                                                                |
| Setext 見出し (`===`, `---`)    |  Yes   |       Yes       | marked.js がサポート                                                |
| 太字 (`**`, `__`)               |  Yes   |       Yes       | 同等                                                                |
| 斜体 (`*`, `_`)                 |  Yes   |       Yes       | 同等                                                                |
| 取り消し線 (`~~`)               |  Yes   |       Yes       | 同等（GFM 拡張）                                                    |
| インラインコード (`` ` ``)      |  Yes   |       Yes       | 同等                                                                |
| フェンスドコードブロック        |  Yes   |       Yes       | 同等（言語指定付き）                                                |
| インデントコードブロック        |  Yes   |       Yes       | marked.js がサポート                                                |
| 引用 (`>`)                      |  Yes   |       Yes       | 同等                                                                |
| 箇条書き（番号なし）            |  Yes   |       Yes       | 同等                                                                |
| 箇条書き（番号付き）            |  Yes   |       Yes       | 同等                                                                |
| テーブル                        |  Yes   |       Yes       | 同等（GFM 拡張）                                                    |
| 水平線 (`---`, `***`, `___`)    |  Yes   |       Yes       | 同等                                                                |
| タスクリスト (`- [ ]`, `- [x]`) |  Yes   |       Yes       | 同等（GFM 拡張）                                                    |
| リンク (`[text](url)`)          |  Yes   |       Yes       | Pleasanter はカスタムレンダラーで処理（UNC パス・Notes リンク対応） |
| リンク参照定義                  |  Yes   |       Yes       | marked.js がサポート                                                |
| 画像 (`![alt](url)`)            |  Yes   | Yes（差異あり） | Pleasanter は `?thumbnail=1` を付与、`<figure>` タグで囲む          |
| バックスラッシュエスケープ      |  Yes   |       Yes       | marked.js がサポート                                                |
| HTML エンティティ参照           |  Yes   |       Yes       | marked.js がサポート                                                |

#### 改行の挙動（重要な差異）

| 挙動                                   |       GitHub       |     Pleasanter     | 差異の詳細                                                    |
| -------------------------------------- | :----------------: | :----------------: | ------------------------------------------------------------- |
| 通常の改行（ソフトブレーク）           | スペースとして表示 | **改行として表示** | Pleasanter は `breaks: true` のため、単一改行が `<br>` になる |
| 末尾2スペース + 改行（ハードブレーク） |   `<br>` に変換    |   `<br>` に変換    | 同等                                                          |
| バックスラッシュ + 改行                |   `<br>` に変換    |   `<br>` に変換    | 同等                                                          |

> **注意**: この差異は非常に重要である。GitHub で記述した Markdown をプリザンターにコピーすると、改行の表示が変わる可能性がある。逆も同様で、Pleasanter で意図した改行が GitHub では連結して表示される。

#### 生の HTML

| 構文                                     | GitHub | Pleasanter | 差異の詳細                                                                       |
| ---------------------------------------- | :----: | :--------: | -------------------------------------------------------------------------------- |
| インライン HTML (`<del>`, `<sup>` 等)    |  Yes   |   **No**   | Pleasanter は `html` レンダラーで全てエスケープ                                  |
| ブロックレベル HTML (`<div>`, `<table>`) |  Yes   |   **No**   | 同上                                                                             |
| 危険なタグのフィルタリング               |  Yes   | **別方式** | GitHub は `<script>` 等の特定タグのみフィルタ、Pleasanter は全 HTML をエスケープ |
| HTML コメント (`<!-- -->`)               |  Yes   |   **No**   | エスケープされる                                                                 |

> **影響**: GitHub で `<details><summary>` による折りたたみ、`<sup>` による上付き文字、`<kbd>` によるキーボード表示などを使用している Markdown は、プリザンターではそのまま文字列として表示される。

#### GitHub 固有の拡張機能

| 構文                                            | GitHub | Pleasanter | 差異の詳細                                                                               |
| ----------------------------------------------- | :----: | :--------: | ---------------------------------------------------------------------------------------- |
| オートリンク（URL 自動リンク化）                |  Yes   |    Yes     | marked.js の GFM モードでサポート                                                        |
| オートリンク（メールアドレス）                  |  Yes   |    Yes     | marked.js の GFM モードでサポート                                                        |
| SHA 参照（`a5c3785ed8`）                        |  Yes   |   **No**   | GitHub リポジトリ固有機能                                                                |
| Issue/PR 参照（`#123`）                         |  Yes   |   **No**   | GitHub リポジトリ固有機能                                                                |
| ユーザーメンション（`@user`）                   |  Yes   |   **No**   | GitHub 固有機能                                                                          |
| 絵文字ショートコード（`:smile:`）               |  Yes   |   **No**   | GitHub 固有機能、marked.js 標準では非対応                                                |
| 脚注 (`[^1]`)                                   |  Yes   |   **No**   | GitHub 独自拡張。marked.js 標準では非対応（別途拡張が必要）                              |
| アラート / 注意書き（`> [!NOTE]`）              |  Yes   |   **No**   | GitHub 独自拡張。marked.js 標準では非対応                                                |
| 数式（`$...$`, `$$...$$`）                      |  Yes   |   **No**   | GitHub は MathJax/KaTeX でレンダリング。Pleasanter は非対応                              |
| Mermaid ダイアグラム（` ```mermaid ` ブロック） |  Yes   |   **No**   | GitHub はネイティブ対応。Pleasanter は拡張ファイルあるが Markdown フィールド内では未対応 |
| 見出しの自動 ID 生成                            |  Yes   |   **No**   | GitHub は見出しに自動で `id` 属性を付与（アンカーリンク）。Pleasanter は付与しない       |
| 目次の自動生成                                  |  Yes   |   **No**   | GitHub は見出しから目次を生成可能。Pleasanter は非対応                                   |

#### Pleasanter 固有の拡張機能

| 構文                                 | GitHub | Pleasanter | 差異の詳細                                                         |
| ------------------------------------ | :----: | :--------: | ------------------------------------------------------------------ |
| `[md]` プレフィックス                | **No** |    Yes     | Pleasanter 固有。1行目に `[md]` がないとMarkdownとして解釈されない |
| Notes モード（デフォルト）           | **No** |    Yes     | `[md]` なしの場合、リンクと画像のみ処理し他の構文はエスケープ      |
| UNC パス自動リンク                   | **No** |    Yes     | `\\server\share\path` を `file://` リンクに変換                    |
| IBM Notes リンク                     | **No** |    Yes     | `notes://` プロトコルをそのままリンク化                            |
| 画像サムネイル                       | **No** |    Yes     | `?thumbnail=1` パラメータ付与でサムネイル表示                      |
| 画像ライトボックス                   | **No** |    Yes     | 画像クリックでモーダル拡大表示（`data-enablelightbox="1"` 設定）   |
| 画像アップロード（ペースト）         |  Yes   |    Yes     | 両方とも `Ctrl+V` で画像貼り付け可能（ただし動作は異なる）         |
| カメラ撮影                           | **No** |    Yes     | モバイルカメラでの撮影・挿入                                       |
| コードブロックコピーボタン           |  Yes   |    Yes     | 両方ともコピーボタン付き（Pleasanter は `md-code-copy` クラス）    |
| ビューア切替（Auto/Manual/Disabled） | **No** |    Yes     | Pleasanter 固有の表示モード切替                                    |
| `target="_blank"` リンク             | **No** |    Yes     | `AnchorTargetBlank` 設定で外部リンクを新しいタブで開く             |

#### シンタックスハイライト

| 項目               | GitHub            | Pleasanter                        |
| ------------------ | ----------------- | --------------------------------- |
| ハイライトエンジン | Linguist ベース   | highlight.js                      |
| 対応言語数         | 数百言語          | highlight.js が対応する全言語     |
| 言語未指定時       | ハイライトなし    | `highlightAuto`（自動検出）で推定 |
| テーマ             | GitHub 独自テーマ | `github-dark` テーマ              |
| コピーボタン       | あり              | あり（`md-code-copy` クラス）     |

### 移行時の注意点

GitHub Markdown → Pleasanter、またはその逆方向に Markdown コンテンツを移行する際の注意点:

| 注意点                      | 影響                                                | 対処法                                                 |
| --------------------------- | --------------------------------------------------- | ------------------------------------------------------ |
| `[md]` プレフィックスが必要 | GitHub の Markdown をそのまま貼り付けても動作しない | 先頭行に `[md]` を追加する                             |
| 改行の挙動差異              | 改行の表示が変わる                                  | Pleasanter → GitHub: 改行位置に末尾2スペースを追加する |
| 生 HTML が使えない          | `<details>`, `<sup>` 等が表示されない               | Markdown 構文で代替するか、該当箇所を削除する          |
| GitHub 固有構文が使えない   | `[^1]`, `> [!NOTE]`, `$...$` 等が動作しない         | 引用ブロックや通常テキストで代替する                   |
| 絵文字ショートコード        | `:smile:` 等がテキストのまま表示される              | Unicode 絵文字（😄）を直接入力する                     |
| 画像パスの差異              | Pleasanter は `?thumbnail=1` を付与                 | 画像 URL の形式を確認・調整する                        |

### 差分の概念図

```mermaid
graph LR
    subgraph "共通サポート (GFM ベース)"
        A[見出し]
        B[太字・斜体]
        C[リンク・画像]
        D[コードブロック]
        E[テーブル]
        F[リスト・タスクリスト]
        G[引用・水平線]
        H[取り消し線]
        I[オートリンク]
    end

    subgraph "GitHub のみ"
        J[生 HTML]
        K[脚注]
        L[アラート]
        M[数式]
        N[Mermaid]
        O[メンション・Issue参照]
        P[絵文字ショートコード]
        Q[見出し自動ID]
    end

    subgraph "Pleasanter のみ"
        R["[md] プレフィックス"]
        S[Notes モード]
        T[UNC パス]
        U[Notes リンク]
        V[サムネイル・ライトボックス]
        W[カメラ撮影]
        X[ビューア切替]
    end
```

---

## Mermaid.js 対応の詳細調査

プリザンターの `wwwroot/Extensions/` ディレクトリには `mermaid-11.9.0.min.js` が配置されている。このライブラリが Markdown フィールドで利用可能かどうかを詳しく調査した。

### Mermaid.js の配置場所

```text
Implem.Pleasanter/
└── wwwroot/
    └── Extensions/
        ├── mermaid-11.9.0.min.js   ← Mermaid.js v11.9.0（minified）
        └── smt-json-to-table.html  ← Site Visualizer の HTML
```

`wwwroot/Extensions/` は `Startup.cs` の `app.UseStaticFiles()` により静的ファイルとして公開される。
しかし、通常のプリザンター画面に**自動注入する仕組みは存在しない**。
「ExtensionScript」のような拡張スクリプト自動注入の機能は C# コードにも `.cshtml` にも実装されていない。

### Mermaid.js の実際の利用箇所

Mermaid.js が読み込まれるのは **Site Visualizer（サイト設定可視化ツール）の 1 ページのみ**である。

#### Site Visualizer とは

Site Visualizer は、プリザンターのサイト設定（テーブル定義・リンク構成）を**ER 図として可視化**する管理機能である。

| 項目           | 内容                                                                                   |
| -------------- | -------------------------------------------------------------------------------------- |
| アクセス URL   | `/items/{id}/VisualizeSettings?viewer=html`                                            |
| ルーティング   | `ItemsController.VisualizeSettings()` → `SiteManagement.Utilities.VisualizeSettings()` |
| HTML ファイル  | `wwwroot/Extensions/smt-json-to-table.html`                                            |
| ライセンス制御 | `Parameters.PleasanterExtensions?.SiteVisualizer?.Disabled` で無効化可能               |

#### mermaid.js の読み込み（smt-json-to-table.html 内）

```html
<!-- Site Visualizer HTML内でのみ読み込み -->
<script {{nonce}} src="{{ApplicationPath}}Extensions/mermaid-11.9.0.min.js"></script>
```

#### mermaid.js の初期化・描画（smt-json-to-table.html 内の JavaScript）

```javascript
// ER図のレンダリング
if (erTables.length) {
    mermaid.initialize({ startOnLoad: false });
    mermaid
        .render('erDiagramSvg', mermaidText)
        .then(({ svg }) => {
            renderArea.innerHTML = svg;
            this.fitToContainer();
        })
        .catch((e) => {
            renderArea.innerHTML = `<span style="color:red;">${t('erd_mermaid_error', e.message)}</span>`;
        });
}
```

#### Mermaid テキストの生成（クライアントサイド）

`smt-json-to-table.html` 内の JavaScript が、サイト設定 JSON データから Mermaid の `erDiagram` テキストを動的生成する:

```javascript
toMermaid(tables) {
    let lines = ['erDiagram'];
    tables.forEach(table => {
        lines.push(`    TBL_${table.SiteId}["${table.Title}(${table.SiteId})"] {`);
        // PK/FK カラムを列挙
        lines.push(`    }`);
    });
    tables.forEach(table => {
        // FK リレーションを Mermaid ER 記法で出力
        lines.push(`    TBL_${parentSiteId} |o--o{ TBL_${table.SiteId} : ""`);
    });
    return lines.join('\n');
}
```

### サーバーサイドの Mermaid テキスト生成

`Json2MermaidConvertor` クラスが、サイト設定データを `.mmd`（Mermaid）ファイルとしてエクスポートする機能を提供する。

#### Json2MermaidConvertor.cs

```csharp
// Implem.Pleasanter/Libraries/SiteManagement/Json2MermaidConvertor.cs
internal class Json2MermaidConvertor
{
    internal static (string mermaidText, bool flowControl) Convert(SettingsJsonConverter dump)
    {
        if (dump?.ERDiagrams?.Tables == null) return (null, false);
        var stringBuilder = new System.Text.StringBuilder();
        stringBuilder.Append("erDiagram\n");
        foreach (var table in dump.ERDiagrams.Tables)
        {
            stringBuilder.Append(ConvertTable(table));  // テーブル定義
        }
        foreach (var table in dump.ERDiagrams.Tables)
        {
            stringBuilder.Append(ConvertRelation(table));  // リレーション定義
        }
        return (stringBuilder.ToString(), true);
    }
}
```

#### エクスポート処理（SiteManagement/Utilities.cs）

```csharp
// ExportType=mermaid の場合
else if (exportType == "mermaid")
{
    var (mermaidText, flowControl) = Json2MermaidConvertor.Convert(dump);
    if (flowControl)
    {
        var mem = new MemoryStream(mermaidText.ToBytes(), false);
        return new ResponseFile(
            fileContent: mem,
            fileDownloadName: ExportUtilities.FileName(
                context: context,
                title: "VisualizeSettings",
                extension: "mmd"),  // .mmd 拡張子でダウンロード
            contentType: "application/zip");
    }
}
```

Site Visualizer は 3 種類のエクスポート形式をサポートする:

| エクスポート形式 | 出力                                     |
| ---------------- | ---------------------------------------- |
| `json`           | サイト設定 JSON ファイル                 |
| `xlsx`           | Excel/ZIP ファイル                       |
| `mermaid`        | `.mmd` ファイル（Mermaid ER 図テキスト） |

### PleasanterExtensions パラメータ

```csharp
// Implem.ParameterAccessor/Parts/PleasanterExtensions.cs
public class PleasanterExtensions
{
    public class SiteVisualizerData
    {
        public bool Disabled { get; set; } = false;       // 機能の無効化
        public int ErdLinkDepth { get; set; } = 10;       // ER図のリンク探索深度
        public int ErdLinkLimit { get; set; } = 60;       // ER図のリンク数上限
    }
    public SiteVisualizerData SiteVisualizer = new();
}
```

### Markdown フィールドとの関係

Mermaid.js は Markdown フィールド（`<markdown-field>` Web Component）とは**完全に独立**している。

| 観点                                | 状況                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `markdownField.ts` での参照         | **なし** — mermaid に関する import / require / 参照は一切存在しない                        |
| `marked.js` の拡張設定              | **なし** — Mermaid コードブロック用のカスタムレンダラーは未定義                            |
| Markdown 内での ` ```mermaid ` 記述 | 通常のコードブロックとして表示される（フェンスドコードブロック + 言語名 "mermaid"）        |
| highlight.js での扱い               | mermaid は highlight.js の対応言語に含まれないため、`highlightAuto` で近似言語が推定される |
| DOMPurify の影響                    | 仮に Mermaid が SVG を生成しても、DOMPurify でサニタイズされる可能性がある                 |

### アーキテクチャ図

````text
┌──────────────────────────────────────────────────────────────┐
│  通常のプリザンター画面                                      │
│  ┌───────────────────────────┐                               │
│  │ <markdown-field>          │  marked.js + DOMPurify        │
│  │ Markdown → HTML 変換      │  ※ mermaid.js は読み込まれない │
│  │ ```mermaid → コードブロック │                               │
│  └───────────────────────────┘                               │
├──────────────────────────────────────────────────────────────┤
│  Site Visualizer（/items/{id}/VisualizeSettings?viewer=html）│
│  ┌───────────────────────────────────────────┐               │
│  │ smt-json-to-table.html                    │               │
│  │ ┌────────────────┐  ┌───────────────────┐ │               │
│  │ │ JSON データ     │→│ mermaid.render()  │ │               │
│  │ │ (ER Diagrams)   │  │ → SVG ER 図描画  │ │               │
│  │ └────────────────┘  └───────────────────┘ │               │
│  └───────────────────────────────────────────┘               │
│  ※ mermaid-11.9.0.min.js はこのページのみで読み込み         │
├──────────────────────────────────────────────────────────────┤
│  API エクスポート（ExportType=mermaid）                       │
│  Json2MermaidConvertor → .mmd ファイルダウンロード           │
│  ※ サーバーサイドで Mermaid テキスト生成のみ（描画なし）     │
└──────────────────────────────────────────────────────────────┘
````

### 結論（Mermaid 対応）

- **Markdown フィールドでは Mermaid 図は描画されない**。コードブロックに `mermaid` 言語を指定しても、テキストとして表示されるのみ
- `mermaid-11.9.0.min.js` は **Site Visualizer（サイト設定可視化）の ER 図描画専用**で配置されている
- `Json2MermaidConvertor` は **サイト設定の ER 図を `.mmd` ファイルとしてエクスポート**するためのサーバーサイドコンバーター
- Markdown フィールドで Mermaid 対応を実現するには、`markdownField.ts` に Mermaid 拡張を追加し、`marked.js` のカスタムレンダラーで `mermaid` 言語のコードブロックを処理する実装が必要になる

---

## 結論

| 項目                     | 内容                                                                    |
| ------------------------ | ----------------------------------------------------------------------- |
| アーキテクチャ           | **クライアントサイドレンダリング**（サーバーは HTML 構造のみ生成）      |
| Markdown パーサー        | **marked.js**（クライアントサイド）                                     |
| サニタイズ               | **DOMPurify** + HTML タグエスケープ + `escapeMarkdown()`                |
| コードハイライト         | **highlight.js**                                                        |
| UI コンポーネント        | **`<markdown-field>` Web Component**（Custom Elements）                 |
| サーバーサイドライブラリ | なし（Markdig 等は未使用）                                              |
| デフォルトモード         | Notes モード（`[md]` プレフィックスで Markdown フルレンダリング有効化） |
| GFM サポート             | あり（テーブル、取消線、タスクリスト対応）                              |
| 生 HTML サポート         | なし（セキュリティのためエスケープ）                                    |
| 画像サポート             | あり（アップロード・貼り付け・カメラ撮影対応、`AllowImage` 設定で制御） |
| ビューア切替             | Auto / Manual / Disabled の 3 モード                                    |
| Mermaid 対応             | **Markdown フィールドでは非対応**（Site Visualizer の ER 図描画専用）   |

---

## 関連ソースコード

| ファイル                                                                                 | 説明                                                          |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `Implem.PleasanterFrontend/wwwroot/src/scripts/modules/markdownField/markdownField.ts`   | Markdown Web Component（中核コード）                          |
| `Implem.PleasanterFrontend/wwwroot/src/scripts/modules/markdownField/markdownField.scss` | スタイル定義                                                  |
| `Implem.Pleasanter/Libraries/HtmlParts/HtmlControls.cs`                                  | サーバーサイドの Markdown コントロール生成                    |
| `Implem.Pleasanter/Libraries/HtmlParts/HtmlTags.cs`                                      | `<markdown-field>` タグ出力                                   |
| `Implem.Pleasanter/Libraries/HtmlParts/HtmlFields.cs`                                    | `FieldMarkDown()` フィールド生成                              |
| `Implem.Pleasanter/Libraries/HtmlParts/HtmlComments.cs`                                  | コメント欄の Markdown                                         |
| `Implem.Pleasanter/Libraries/HtmlParts/HtmlGuides.cs`                                    | ガイド表示の Markdown                                         |
| `Implem.Pleasanter/Libraries/Settings/Column.cs`                                         | カラム設定（`ViewerSwitchingType`, `AllowImage`, `FieldCss`） |
| `Implem.Pleasanter/Implem.Pleasanter.csproj`                                             | NuGet 依存関係（Markdown ライブラリなし）                     |
| `Implem.Pleasanter/Startup.cs`                                                           | X-XSS-Protection ヘッダー設定                                 |
| `Implem.Pleasanter/wwwroot/Extensions/mermaid-11.9.0.min.js`                             | Mermaid.js ライブラリ（Site Visualizer 専用）                 |
| `Implem.Pleasanter/wwwroot/Extensions/smt-json-to-table.html`                            | Site Visualizer HTML（Mermaid ER 図描画）                     |
| `Implem.Pleasanter/Libraries/SiteManagement/Json2MermaidConvertor.cs`                    | サイト設定 → Mermaid ER 図テキスト変換                        |
| `Implem.Pleasanter/Libraries/SiteManagement/Utilities.cs`                                | Site Visualizer のエントリポイント                            |
| `Implem.ParameterAccessor/Parts/PleasanterExtensions.cs`                                 | Site Visualizer パラメータ設定                                |
