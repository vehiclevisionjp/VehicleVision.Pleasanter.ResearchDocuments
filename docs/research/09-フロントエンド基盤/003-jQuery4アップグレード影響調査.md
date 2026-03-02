# jQuery 4.0 アップグレード影響調査

Pleasanter フロントエンド（`Implem.PleasanterFrontend`）配下の自前スクリプトコード（JS/TS）において、jQuery 4.0 アップグレードで影響を受けるパターンを調査した結果をまとめる。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [調査対象](#調査対象)
- [調査結果サマリー](#調査結果サマリー)
- [詳細分析](#詳細分析)
    - [1. 削除済み非推奨 API](#1-削除済み非推奨-api)
    - [2. jQuery プロトタイプの配列メソッド（`.push`/`.sort`/`.splice`）](#2-jquery-プロトタイプの配列メソッドpushsortsplice)
    - [3. `toggleClass(boolean)`](#3-toggleclassboolean)
    - [4. `focusin`/`focusout` イベント](#4-focusinfocusout-イベント)
    - [5. `event.which` 使用（**高リスク**）](#5-eventwhich-使用高リスク)
    - [6. `.css()` 数値渡し（px 自動付与の変更）（**高リスク**）](#6-css-数値渡しpx-自動付与の変更高リスク)
    - [7. AJAX パターン](#7-ajax-パターン)
    - [8. `$.Deferred` 使用](#8-deferred-使用)
    - [9. JSONP 使用](#9-jsonp-使用)
    - [10. `.bind()` 使用（**中リスク**）](#10-bind-使用中リスク)
    - [11. `$(document).ajaxComplete()` 使用](#11-documentajaxcomplete-使用)
- [リスク別改修優先度](#リスク別改修優先度)
    - [高リスク（動作が壊れる可能性が高い）](#高リスク動作が壊れる可能性が高い)
    - [中リスク（非推奨の強化または将来削除）](#中リスク非推奨の強化または将来削除)
    - [低リスク（動作順序変更・将来対応推奨）](#低リスク動作順序変更将来対応推奨)
- [結論](#結論)
- [サーバーサイドでの変更点](#サーバーサイドでの変更点)
- [関連ソースコード](#関連ソースコード)
- [関連リンク](#関連リンク)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 調査情報

| 調査日        | リポジトリ | ブランチ        | タグ/バージョン    | コミット    | 備考                                    |
| ------------- | ---------- | --------------- | ------------------ | ----------- | --------------------------------------- |
| 2026年2月24日 | Pleasanter | (detached HEAD) | Pleasanter_1.5.1.0 | `34f162a43` | scripts/ 配下 112 個の .js ファイル対象 |

## 調査目的

jQuery 4.0 では多くの非推奨 API が完全に削除され、イベントや AJAX の挙動が変更される。
Pleasanter フロントエンドコードのうち、プラグイン（`plugins/`）を除く自前スクリプトコードにおいて、
jQuery 4.0 移行で破壊的影響を受けるパターンを特定し、改修の優先順位付けの根拠とする。

---

## 調査対象

**ディレクトリ**: `Implem.PleasanterFrontend/wwwroot/src/scripts/`

| ディレクトリ               | ファイル数 | 言語       | 調査結果                                                      |
| -------------------------- | ---------- | ---------- | ------------------------------------------------------------- |
| `generals/`                | 112        | JavaScript | jQuery 4.0 影響あり（本ドキュメントの主な対象）               |
| `generals/modal/`          | 2          | TypeScript | **影響なし**（jQuery 利用は `$p.modal` 参照のみ）             |
| `generals/grid-container/` | 1          | TypeScript | **影響なし**（vanilla DOM + Web Component）                   |
| `modules/`                 | 15         | TypeScript | **影響なし**（主に vanilla DOM API、jQuery 使用は橋渡し程度） |
| `app.ts` / `modules.ts`    | 2          | TypeScript | **影響なし**（import のみ）                                   |

`modules/` 配下の TypeScript ファイルは、主に vanilla DOM API と Web Components で構成されており、
jQuery の使用は `$p.set($(element), value)` や `$p.display()` 等のプリザンター独自グローバル API への橋渡しに限定されている。
jQuery 4.0 の破壊的変更に該当するパターンは検出されなかった。

**除外**: `plugins/` ディレクトリ（サードパーティプラグイン）→ 別ドキュメント参照

---

## 調査結果サマリー

| #   | カテゴリ                                            | 該当数  | リスク | 説明                                                             |
| --- | --------------------------------------------------- | ------- | ------ | ---------------------------------------------------------------- |
| 1   | 削除済み非推奨 API（`$.isArray` 等）                | **0**   | なし   | 使用なし                                                         |
| 2   | jQuery プロトタイプの配列メソッド                   | **0**   | なし   | `.push`/`.sort`/`.splice` はすべてネイティブ配列に対する使用     |
| 3   | `toggleClass(boolean)`                              | **0**   | なし   | 使用なし                                                         |
| 4   | `focusin`/`focusout` イベント                       | **1**   | 低     | 動作順序の変更に注意                                             |
| 5   | `event.which` 使用                                  | **3**   | **高** | shim が削除されるため `event.key` への移行が必要                 |
| 6   | `.css()` 数値渡し（px 自動付与）                    | **11+** | **高** | `z-index` は安全だが、 `top`/`left`/`width` 等で数値直接渡しあり |
| 7   | AJAX パターン（`$.ajax`/`.done`/`.fail`/`.always`） | **9**   | **中** | `$.ajaxSetup` や `async: false` の使用に注意                     |
| 8   | `$.Deferred` 使用                                   | **0**   | なし   | 明示的な `$.Deferred` 生成なし                                   |
| 9   | JSONP 使用                                          | **0**   | なし   | 使用なし                                                         |
| 10  | `.bind()` 使用（jQuery 3.x で非推奨）               | **1**   | **中** | `.on()` へ移行が必要                                             |
| 11  | `$.ajaxSetup` 使用                                  | **3**   | **中** | グローバル AJAX 設定への依存                                     |
| 12  | `event.keyCode` 使用                                | **3**   | 低     | `event.which` とは別に `keyCode` も使用                          |

---

## 詳細分析

### 1. 削除済み非推奨 API

以下の API はいずれも Pleasanter スクリプトコード内で **使用されていない**。

| API                                    | 検索結果 | jQuery 4.0 での状態                      |
| -------------------------------------- | -------- | ---------------------------------------- |
| `$.isArray` / `jQuery.isArray`         | 0 件     | 削除（`Array.isArray` を使用）           |
| `$.parseJSON` / `jQuery.parseJSON`     | 0 件     | 削除（`JSON.parse` を使用）              |
| `$.trim` / `jQuery.trim`               | 0 件     | 削除（`String.prototype.trim` を使用）   |
| `$.type` / `jQuery.type`               | 0 件     | 削除                                     |
| `$.now` / `jQuery.now`                 | 0 件     | 削除（`Date.now` を使用）                |
| `$.isNumeric` / `jQuery.isNumeric`     | 0 件     | 削除                                     |
| `$.isFunction` / `jQuery.isFunction`   | 0 件     | 削除（`typeof x === 'function'` を使用） |
| `$.isWindow` / `jQuery.isWindow`       | 0 件     | 削除                                     |
| `$.camelCase` / `jQuery.camelCase`     | 0 件     | 削除                                     |
| `$.nodeName` / `jQuery.nodeName`       | 0 件     | 削除                                     |
| `$.cssNumber` / `jQuery.cssNumber`     | 0 件     | 削除                                     |
| `$.cssProps` / `jQuery.cssProps`       | 0 件     | 削除                                     |
| `$.fx.interval` / `jQuery.fx.interval` | 0 件     | 削除                                     |

### 2. jQuery プロトタイプの配列メソッド（`.push`/`.sort`/`.splice`）

検索で31箇所の `.push()`、3箇所の `.sort()`、3箇所の `.splice()` が見つかったが、**すべてネイティブ JavaScript 配列に対する操作**であり、jQuery オブジェクトに対するものではない。

代表例:

- `generals/fieldselectable.js` - `afterColumns.push(...)` / `afterColumns.splice(...)` → ネイティブ配列
- `generals/gantt.js` - `days.push(d)` → ネイティブ配列
- `generals/timeseries.js` - `indexes.sort(...)` → ネイティブ配列

**影響: なし**

### 3. `toggleClass(boolean)`

**使用箇所: 0 件** — 影響なし。

### 4. `focusin`/`focusout` イベント

**該当: 1 件**

**ファイル**: `generals/dropdownsearchevents.js`（行: 2）

```javascript
$(document).on('focusin', '.control-dropdown.search', function (e) {
    e.preventDefault();
    if ($('#EditorLoading').val() === '1') {
        $(this).blur();
        $('#EditorLoading').val(0);
    } else {
        $p.openDropDownSearchDialog($(this));
    }
});
```

jQuery 4.0 では `focusin`/`focusout` のイベント発火順序が変更される
（ネイティブブラウザの `focus`/`blur` イベントとの順序関係が変化）。
このコードは `focusin` でダイアログを開くシンプルなパターンのため、
**直接的な破壊は低リスク**だが、
他の `focus`/`blur` ハンドラとの相互作用がある場合は動作確認が必要。

### 5. `event.which` 使用（**高リスク**）

jQuery 4.0 では `event.which` の shim が削除される。`event.key` または `event.code` への移行が必要。

**該当: 3 件**

| ファイル                   | 行  | コード                   | 用途                             |
| -------------------------- | --- | ------------------------ | -------------------------------- |
| `generals/searchevents.js` | 9   | `if (e.which === 13)`    | Enter キーで検索実行             |
| `generals/keyevents.js`    | 3   | `if (e.which === 13)`    | Enter キーでフォームのボタン発火 |
| `generals/keyevents.js`    | 8   | `return e.which !== 13;` | Enter キーのデフォルト動作抑制   |

**修正方針**: `e.which === 13` → `e.key === 'Enter'` に変更する。

> **補足**: `event.keyCode` も3箇所で使用されている（以下参照）。
> `keyCode` 自体は DOM 標準の非推奨プロパティだが、
> jQuery 4.0 では引き続き利用可能（jQuery が shim を提供していたのは `which` のみ）。
> ただし将来的には `event.key` への移行が推奨される。

| ファイル                      | 行  | コード                  | 用途                             |
| ----------------------------- | --- | ----------------------- | -------------------------------- |
| `generals/_controllevents.js` | 52  | `if (e.keyCode === 13)` | Enter キーで autopostback        |
| `generals/keyevents.js`       | 11  | `if (e.keyCode === 9)`  | Tab キーでフォーカス制御         |
| `generals/gridevents.js`      | 200 | `if (e.keyCode === 13)` | Enter キーでグリッドフィルタ閉じ |

### 6. `.css()` 数値渡し（px 自動付与の変更）（**高リスク**）

jQuery 4.0 では、`.css()` に数値を渡した場合の `px` 自動付与のルールが変更される。
`$.cssNumber` に含まれない CSS プロパティに数値を渡すと、
jQuery 3.x では自動的に `"px"` が付与されたが、
jQuery 4.0 ではこのリストが削除・変更される。

#### 6.1 数値直接渡し（`.css('property', number)`）

| ファイル                 | 行  | コード                 | プロパティ | リスク                               |
| ------------------------ | --- | ---------------------- | ---------- | ------------------------------------ |
| `generals/tenants.js`    | 15  | `.css('z-index', 110)` | z-index    | **安全**（`z-index` は元々単位なし） |
| `generals/kamban.js`     | 76  | `.css('z-index', 2)`   | z-index    | **安全**                             |
| `generals/bulkupdate.js` | 14  | `.css('z-index', 110)` | z-index    | **安全**                             |

#### 6.2 数値式渡し（`.css('property', expression)`）

| ファイル                             | 行  | コード                                     | プロパティ | リスク     |
| ------------------------------------ | --- | ------------------------------------------ | ---------- | ---------- |
| `generals/responsive.js`             | 101 | `.css('bottom', parseInt(...))`            | bottom     | **要注意** |
| `generals/responsive.js`             | 104 | `.css('bottom', parseInt(...))`            | bottom     | **要注意** |
| `generals/viewfilterslabelevents.js` | 29  | `.css('top', $this.offset().top + ...)`    | top        | **要注意** |
| `generals/viewfilterslabelevents.js` | 30  | `.css('left', $this.offset().left)`        | left       | **要注意** |
| `generals/jqueryui.js`               | 213 | `.css('top', $header.offset().top + ...)`  | top        | **要注意** |
| `generals/jqueryui.js`               | 214 | `.css('left', $header.offset().left)`      | left       | **要注意** |
| `generals/jqueryui.js`               | 225 | `.css('top', $control.offset().top + ...)` | top        | **要注意** |
| `generals/jqueryui.js`               | 226 | `.css('left', $control.offset().left)`     | left       | **要注意** |

#### 6.3 オブジェクト渡し（`.css({...})`） — 数値を含むケース

| ファイル                 | 行      | コード概要                       | 該当プロパティ                      | リスク     |
| ------------------------ | ------- | -------------------------------- | ----------------------------------- | ---------- |
| `generals/gridevents.js` | 126-147 | `$menuSort.css(cssProps)`        | `top`, `left`, `width`, `marginTop` | **要注意** |
| `generals/gantt.js`      | 162-166 | `$('#Gantt').css('height', ...)` | height                              | **要注意** |

**修正方針**: 数値渡しの箇所を `+ 'px'` を付与する形式に変更するか、jQuery 4.0 の `$.cssNumber` 互換リストを確認して対応する。

> **注意**: `_dispatch.js` の `$(target).css(json.Name, json.Value)` は、
> サーバーサイドから動的にプロパティ名と値を受け取るため、
> 値が数値の場合にリスクが生じる可能性がある。
> サーバーサイドのレスポンスに `px` 付きの文字列が含まれていれば安全。

### 7. AJAX パターン

#### 7.1 `$.ajax` の使用

**該当: 5 箇所**（4 ファイル）

| ファイル            | 行  | パターン              | 備考                      |
| ------------------- | --- | --------------------- | ------------------------- |
| `generals/_api.js`  | 53  | `$.ajax({...})`       | API 実行（POST/JSON）     |
| `generals/_api.js`  | 85  | `$.ajax(ajaxSetings)` | API 実行（POST/JSON）     |
| `generals/_ajax.js` | 79  | `$.ajax({...})`       | 汎用 AJAX（POST/JSON）    |
| `generals/_ajax.js` | 168 | `$.ajax({...})`       | マルチアップロード        |
| `generals/grid.js`  | 62  | `$.ajax({...})`       | グリッド selectedIds 取得 |

すべて `dataType: 'json'` + `type: 'post'` のパターンで、JSONP は使用されていない。jQuery 4.0 でも基本的な `$.ajax` の使い方は維持されるため、**直接的な破壊リスクは低い**。

#### 7.2 `.done()`/`.fail()`/`.always()` チェーン

`$.ajax` の返り値に `.done()/.fail()/.always()` をチェーンするパターンが全 AJAX 呼び出しで使用されている。jQuery 4.0 でも Deferred/Promise インターフェースは維持されるため、**安全**。

#### 7.3 `$.ajaxSetup` 使用（**中リスク**）

| ファイル            | 行  | コード                               | 用途              |
| ------------------- | --- | ------------------------------------ | ----------------- |
| `generals/_ajax.js` | 6   | `$.ajaxSetup({ beforeSend: ... })`   | CSRF トークン設定 |
| `generals/_api.js`  | 39  | `$.ajaxSetup({ async: args.async })` | 同期/非同期切替   |
| `generals/_api.js`  | 69  | `$.ajaxSetup({ async: args.async })` | 同期/非同期切替   |

jQuery 4.0 では `$.ajaxSetup` は非推奨が強化され、将来的に削除される可能性がある。特に `async: false`（同期 AJAX）は主要ブラウザで警告が出る非推奨機能であり、`$.ajaxSetup` でグローバルに設定を変更するパターンは改善が必要。

#### 7.4 `$.ajaxSettings.xhr()` 使用

| ファイル            | 行  | コード                                 |
| ------------------- | --- | -------------------------------------- |
| `generals/_ajax.js` | 170 | `var uploadobj = $.ajaxSettings.xhr()` |

内部 API を参照しているため、jQuery 4.0 で API が変更された場合に影響を受ける可能性がある。

#### 7.5 `async: false`（同期 AJAX）

| ファイル           | 行  | コード         |
| ------------------ | --- | -------------- |
| `generals/grid.js` | 65  | `async: false` |

### 8. `$.Deferred` 使用

明示的な `$.Deferred()` または `jQuery.Deferred()` の生成は **0 件**。`$.ajax` が返す Deferred を `.done`/`.fail`/`.always` で使用するのみ。

### 9. JSONP 使用

**0 件** — 使用なし。

### 10. `.bind()` 使用（**中リスク**）

| ファイル                    | 行  | コード                                | 用途                         |
| --------------------------- | --- | ------------------------------------- | ---------------------------- |
| `generals/confirmevents.js` | 15  | `$(window).bind('beforeunload', ...)` | ページ離脱時の確認ダイアログ |

jQuery 3.x で非推奨、jQuery 4.0 で削除される可能性がある。`.on('beforeunload', ...)` に変更すべき。

### 11. `$(document).ajaxComplete()` 使用

| ファイル                 | 行  | コード                                          |
| ------------------------ | --- | ----------------------------------------------- |
| `generals/responsive.js` | 97  | `$(document).ajaxComplete(function () { ... })` |

jQuery 4.0 でも AJAX グローバルイベントは維持される見込みだが、確認が必要。

---

## リスク別改修優先度

### 高リスク（動作が壊れる可能性が高い）

| #   | 対象                                                                    | ファイル数 | 箇所数 | 改修内容                       |
| --- | ----------------------------------------------------------------------- | ---------- | ------ | ------------------------------ |
| 1   | `event.which` 使用                                                      | 2          | 3      | `event.key === 'Enter'` に置換 |
| 2   | `.css()` 数値渡し（`top`/`left`/`width`/`height`/`bottom`/`marginTop`） | 5          | 11+    | 数値に `+ 'px'` を付与         |

### 中リスク（非推奨の強化または将来削除）

| #   | 対象                        | ファイル数 | 箇所数 | 改修内容                         |
| --- | --------------------------- | ---------- | ------ | -------------------------------- |
| 3   | `$.ajaxSetup` 使用          | 2          | 3      | 個別の `$.ajax` オプションに移行 |
| 4   | `.bind()` 使用              | 1          | 1      | `.on()` に置換                   |
| 5   | `$.ajaxSettings.xhr()` 参照 | 1          | 1      | 標準の XMLHttpRequest を使用     |
| 6   | `async: false`（同期 AJAX） | 1          | 1      | Promise ベースの非同期処理に移行 |

### 低リスク（動作順序変更・将来対応推奨）

| #   | 対象                         | ファイル数 | 箇所数 | 改修内容                   |
| --- | ---------------------------- | ---------- | ------ | -------------------------- |
| 7   | `focusin` イベント順序変更   | 1          | 1      | 動作確認のみ               |
| 8   | `event.keyCode` 使用         | 3          | 3      | `event.key` への移行を推奨 |
| 9   | `$(document).ajaxComplete()` | 1          | 1      | 動作確認                   |

---

## 結論

| 観点               | 結論                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------ |
| 削除済み非推奨 API | 使用なし — **影響なし**                                                                                |
| 最大のリスク       | `.css()` への数値渡し（11箇所以上）と `event.which`（3箇所）                                           |
| AJAX               | `$.ajax` + `.done/.fail/.always` パターンは安全だが、`$.ajaxSetup` と `async: false` は要改修          |
| modules/ (TS)      | **影響なし** — jQuery 使用は橋渡し程度。主に vanilla DOM API と Web Components で構成                  |
| 全体的な影響度     | **中程度** — 破壊的変更を受ける箇所は限定的だが、`.css()` 数値渡しは広範に分散している                 |
| 推奨対応           | 本体コードの該当箇所を直接修正する。プラグイン用には jQuery Migrate を最小限で導入し、段階的に解消する |
| `.bind()`          | 1箇所のみだが早期に `.on()` に移行すべき                                                               |
| サーバーサイド     | `HtmlScripts.cs` の jQuery ファイルパス参照の更新が必要                                                |

---

## サーバーサイドでの変更点

jQuery のファイル参照はサーバーサイド（C#）のコードにハードコードされている。
jQuery 4.0 へ移行する際は、JavaScript ファイルの差し替えに加え、以下の C# コードの変更が必要。

**ファイル**: `Implem.Pleasanter/Libraries/HtmlParts/HtmlScripts.cs`

```csharp
// 現状: jQuery 3.6.0 のファイル名がハードコードされている
Res.Css("assets/plugins/jquery-3.6.0.min.js")

// 移行後: jQuery 4.0.0 のファイル名に変更する
Res.Css("assets/plugins/jquery-4.0.0.min.js")
```

> **注意**: 実際のメソッド名は `Res.Css` ではなく、`script` タグの生成処理の一部である。
> ファイル名の変更に加え、jQuery 4.0 では **Slim ビルドが廃止** されているため、
> Slim ビルドを使用している場合は通常ビルドへの切り替えも必要。

---

## 関連ソースコード

| ファイル                             | 主な該当パターン                                                       |
| ------------------------------------ | ---------------------------------------------------------------------- |
| `generals/_ajax.js`                  | `$.ajaxSetup`, `$.ajax`, `$.ajaxSettings.xhr()`, `.done/.fail/.always` |
| `generals/_api.js`                   | `$.ajaxSetup`, `$.ajax`, `.done/.fail/.always`                         |
| `generals/grid.js`                   | `$.ajax`, `async: false`                                               |
| `generals/keyevents.js`              | `e.which`, `e.keyCode`                                                 |
| `generals/searchevents.js`           | `e.which`                                                              |
| `generals/gridevents.js`             | `.css(cssProps)` 数値渡し, `e.keyCode`                                 |
| `generals/jqueryui.js`               | `.css('top'/left', number)`                                            |
| `generals/viewfilterslabelevents.js` | `.css('top'/left', number)`                                            |
| `generals/responsive.js`             | `.css('bottom', parseInt(...))`, `ajaxComplete`                        |
| `generals/gantt.js`                  | `.css('height', number)`                                               |
| `generals/confirmevents.js`          | `.bind('beforeunload', ...)`                                           |
| `generals/dropdownsearchevents.js`   | `focusin` イベント                                                     |
| `generals/_controllevents.js`        | `e.keyCode`                                                            |
| `generals/_dispatch.js`              | `.css(json.Name, json.Value)` — 動的値のリスク                         |

---

## 関連リンク

- [jQuery 4.0 Upgrade Guide](https://jquery.com/upgrade-guide/4.0/)
- [jQuery 4.0 Released!](https://blog.jquery.com/2025/01/17/jquery-4-0-0-released/)
- [jQuery Migrate Plugin](https://github.com/jquery/jquery-migrate)
