# Sections サーバースクリプト AutoPostBack 動作

サーバースクリプトにおける `siteSettings.Sections` の動作と、AutoPostBack 時に期待動作しない原因を調査する。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [1. Sections の定義（SiteSettings）](#1-sections-の定義sitesettings)
    - [ファイル](#ファイル)
    - [Sections プロパティ（L182）](#sections-プロパティl182)
    - [Section クラス（`Implem.Pleasanter/Libraries/Settings/Section.cs` L5-L68）](#section-クラスimplempleasanterlibrariessettingssectioncs-l5-l68)
    - [エディタ列におけるセクションの識別（`SiteSettings.cs` L2834-L2843）](#エディタ列におけるセクションの識別sitesettingscs-l2834-l2843)
- [2. サーバースクリプトへの Sections の公開](#2-サーバースクリプトへの-sections-の公開)
    - [ファイル](#ファイル-1)
    - [コンストラクタ（L17-L25）](#コンストラクタl17-l25)
    - [スクリプトエンジンへの登録（`ServerScriptUtilities.cs` L1142）](#スクリプトエンジンへの登録serverscriptutilitiescs-l1142)
    - [ServerScriptModel のコンストラクタ（`ServerScriptModel.cs` L141-L143）](#serverscriptmodel-のコンストラクタserverscriptmodelcs-l141-l143)
- [3. AutoPostBack のフロントエンド処理フロー](#3-autopostback-のフロントエンド処理フロー)
    - [ファイル](#ファイル-2)
    - [controlAutoPostBack 関数（L60-L100）](#controlautopostback-関数l60-l100)
    - [トリガー条件（L40-L44）](#トリガー条件l40-l44)
- [4. AutoPostBack のサーバー側処理フロー](#4-autopostback-のサーバー側処理フロー)
    - [EditorResponse メソッド](#editorresponse-メソッド)
    - [EditorFields メソッド（例: IssueUtilities.cs L2691-L2732）](#editorfields-メソッド例-issueutilitiescs-l2691-l2732)
- [5. FieldResponse の動作（AutoPostBack 時のレスポンス生成）](#5-fieldresponse-の動作autopostback-時のレスポンス生成)
    - [FieldResponse メソッド（IssueUtilities.cs L2819-L2960、ResultUtilities.cs L2632-L2820）](#fieldresponse-メソッドissueutilitiescs-l2819-l2960resultutilitiescs-l2632-l2820)
    - [GetEditorColumnNames の AutoPostBack 時の動作（SiteSettings.cs L2651-L2674）](#geteditorcolumnnames-の-autopostback-時の動作sitesettingscs-l2651-l2674)
- [6. 通常描画時のセクション処理との比較](#6-通常描画時のセクション処理との比較)
    - [Fields メソッド（例: IssueUtilities.cs L2088-L2170）](#fields-メソッド例-issueutilitiescs-l2088-l2170)
- [7. SetValues におけるセクション変更の反映](#7-setvalues-におけるセクション変更の反映)
    - [SetViewValues メソッド（ServerScriptUtilities.cs L974-L984）](#setviewvalues-メソッドserverscriptutilitiescs-l974-l984)
- [結論](#結論)
    - [根本原因](#根本原因)
- [対処方法](#対処方法)
    - [1. クライアントスクリプトで AutoPostBack 後にセクション表示/非表示を制御する](#1-クライアントスクリプトで-autopostback-後にセクション表示非表示を制御する)
    - [2. クライアントスクリプトのみで制御する（推奨）](#2-クライアントスクリプトのみで制御する推奨)
    - [3. プリザンター本体の改修](#3-プリザンター本体の改修)
- [CodeDefiner による自動コード生成との関係](#codedefiner-による自動コード生成との関係)
    - [コード生成の仕組み](#コード生成の仕組み)
    - [改修箇所とテンプレートの対応](#改修箇所とテンプレートの対応)
    - [EditorFields テンプレートの該当箇所](#editorfields-テンプレートの該当箇所)
    - [Fields（セクション描画）テンプレートの該当箇所](#fieldsセクション描画テンプレートの該当箇所)
    - [改修アプローチの選択肢](#改修アプローチの選択肢)
    - [`/// Fixed:` による保護の仕組み](#-fixed-による保護の仕組み)
    - [推奨アプローチ: テンプレート改修（A）](#推奨アプローチ-テンプレート改修a)
- [関連ソースコード](#関連ソースコード)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 調査情報

| 調査日     | リポジトリ | ブランチ | タグ/バージョン    | コミット     | 備考                         |
| ---------- | ---------- | -------- | ------------------ | ------------ | ---------------------------- |
| 2026-02-10 | Pleasanter | -        | Pleasanter_1.5.0.0 | `8c261c0a80` | 初回調査                     |
| 2026-02-10 | Pleasanter | -        | Pleasanter_1.5.1.0 | `34f162a439` | 整合性チェック（行番号更新） |
| 2026-02-10 | Pleasanter | -        | Pleasanter_1.5.1.0 | `34f162a439` | 本体改修案の詳細調査         |

## 調査目的

サーバースクリプトで `siteSettings.Sections` を操作（例: `Hide = true` の設定）した場合、通常のページ表示時には期待通りセクションが非表示になるが、AutoPostBack（項目値変更時の自動ポストバック）時にはセクションの表示/非表示が反映されない問題の原因を特定する。

---

## 1. Sections の定義（SiteSettings）

### ファイル

`Implem.Pleasanter/Libraries/Settings/SiteSettings.cs`

### Sections プロパティ（L182）

```csharp
public List<Section> Sections;
```

`SiteSettings` クラスのフィールドとして `List<Section>` 型で定義されている。

### Section クラス（`Implem.Pleasanter/Libraries/Settings/Section.cs` L5-L68）

```csharp
public class Section
{
    public int Id;
    public string LabelText;
    public bool? AllowExpand;
    public bool? Expand;
    public bool? Hide;
    // ...
}
```

`Hide` プロパティが `bool?` 型で定義されており、これが `true` の場合にセクションが非表示となる。

### エディタ列におけるセクションの識別（`SiteSettings.cs` L2834-L2843）

```csharp
public int SectionId(string columnName)
{
    return columnName.StartsWith("_Section-")
        ? columnName.Substring("_Section-".Length).ToInt()
        : 0;
}

public string SectionName(int? sectionId)
{
    return sectionId > 0 ? $"_Section-{sectionId}" : null;
}
```

`EditorColumnHash` 内ではセクションは `_Section-{id}` という擬似カラム名で管理される。

---

## 2. サーバースクリプトへの Sections の公開

### ファイル

`Implem.Pleasanter/Libraries/ServerScripts/ServerScriptModelSiteSettings.cs`

### コンストラクタ（L17-L25）

```csharp
public class ServerScriptModelSiteSettings
{
    private readonly Context Context;
    private readonly SiteSettings SiteSettings;
    public int? DefaultViewId { get; set; }
    public List<Section> Sections { get; set; }

    public ServerScriptModelSiteSettings(
        Context context,
        SiteSettings ss)
    {
        Context = context;
        SiteSettings = ss;
        DefaultViewId = ss?.GridView;
        Sections = ss?.Sections;
    }
```

**重要**: `Sections = ss?.Sections` は**参照の代入**である。
`List<Section>` は参照型であり、`Section` もクラス（参照型）であるため、
サーバースクリプト内で `siteSettings.Sections[i].Hide = true` のように
個々のセクションのプロパティを変更すると、
**元の `SiteSettings.Sections` の同一オブジェクトが変更される**。

### スクリプトエンジンへの登録（`ServerScriptUtilities.cs` L1142）

```csharp
engine.AddHostObject("siteSettings", model.SiteSettings);
```

`siteSettings` という名前でスクリプトエンジンに公開される。

### ServerScriptModel のコンストラクタ（`ServerScriptModel.cs` L141-L143）

```csharp
SiteSettings = new ServerScriptModelSiteSettings(
    context: context,
    ss: ss);
```

---

## 3. AutoPostBack のフロントエンド処理フロー

### ファイル

`Implem.PleasanterFrontend/wwwroot/src/scripts/generals/_controllevents.js`

### controlAutoPostBack 関数（L60-L100）

```javascript
$p.controlAutoPostBack = function ($control) {
    if ($p.disableAutPostback) return;
    var queryParams = new URLSearchParams(location.search);
    if (queryParams.has('ver')) return;
    // ...
    var url = $('#BaseUrl').val() + id + '/' + action + '/?control-auto-postback=1&TabIndex=' + selectedTabIndex;
    var data = $p.getData($form);
    $p.setMustData($form);
    data.ControlId = $control.attr('id');
    data.ReplaceFieldColumns = $('#ReplaceFieldColumns').val();
    return $p.ajax(url, 'post', data, $control, false, !$control.hasClass('not-set-form-changed'));
};
```

**ポイント**: URL にクエリパラメータ `control-auto-postback=1` が付与される。これがサーバー側で AutoPostBack リクエストを識別する手がかりとなる。

### トリガー条件（L40-L44）

```javascript
$(document).on('change', '.control-auto-postback:not(select[multiple])', function () {
    $p.controlAutoPostBack($(this));
});
```

`control-auto-postback` CSS クラスを持つコントロールの `change` イベントで発火する。

---

## 4. AutoPostBack のサーバー側処理フロー

### EditorResponse メソッド

AutoPostBack リクエストは通常の編集画面表示と同じ `edit` アクションに送信されるが、`EditorResponse` メソッド内で処理が分岐する。

#### IssueUtilities.cs（L2642-L2647）

```csharp
if (context.QueryStrings.Bool("control-auto-postback"))
{
    return EditorFields(
        context: context,
        ss: ss,
        issueModel: issueModel);
}
```

#### ResultUtilities.cs（L2455-L2460）

```csharp
if (context.QueryStrings.Bool("control-auto-postback"))
{
    return EditorFields(
        context: context,
        ss: ss,
        resultModel: resultModel);
}
```

**通常時**は `Editor()` メソッドで**ページ全体の HTML を再生成**するが、**AutoPostBack 時**は `EditorFields()` で**個別フィールドの値のみ更新**する。

### EditorFields メソッド（例: IssueUtilities.cs L2691-L2732）

```csharp
private static ResponseCollection EditorFields(
    Context context,
    SiteSettings ss,
    IssueModel issueModel)
{
    // バリデーション
    var invalid = IssueValidators.OnEditing(...);
    // サーバースクリプト実行
    var serverScriptModelRow = issueModel.SetByBeforeOpeningPageServerScript(
        context: context,
        ss: ss);
    // フィールド個別の値更新レスポンス
    var ret = new ResponseCollection(context: context)
        .FieldResponse(
            context: context,
            ss: ss,
            issueModel: issueModel)
        .Html("#Notes", ...)
        .ReplaceAll(
            "#MainCommandsContainer", ...,
            _using: ss.SwitchCommandButtonsAutoPostBack == true)
        .Val("#ControlledOrder", ...)
        .Invoke("initRelatingColumnEditorNoSend")
        .Messages(context.Messages);
    return ret;
}
```

**重要**: `SetByBeforeOpeningPageServerScript` が呼ばれるため、`BeforeOpeningPage` 条件のサーバースクリプトは AutoPostBack 時にも**実行される**。

---

## 5. FieldResponse の動作（AutoPostBack 時のレスポンス生成）

### FieldResponse メソッド（IssueUtilities.cs L2819-L2960、ResultUtilities.cs L2632-L2820）

```csharp
public static ResponseCollection FieldResponse(
    this ResponseCollection res,
    Context context,
    SiteSettings ss,
    IssueModel issueModel,
    string idSuffix = null)
{
    var replaceFieldColumns = ss.ReplaceFieldColumns(...);
    // ...
    var columnNames = ss.GetEditorColumnNames(
        context.QueryStrings.Bool("control-auto-postback")
            ? ss.GetColumn(
                context: context,
                columnName: context.Forms.ControlId().Split_2nd('_'))
            : null);
    columnNames
        .Select(columnName => ss.GetColumn(context: context, columnName: columnName))
        .Where(column => column != null)  // ← _Section-{id} は Column ではないため null
        .ForEach(column =>
        {
            // 個別カラムの値を res.Val() または res.ReplaceAll() で更新
        });
    return res;
}
```

### GetEditorColumnNames の AutoPostBack 時の動作（SiteSettings.cs L2651-L2674）

```csharp
public List<string> GetEditorColumnNames(Column postbackColumn = null)
{
    var columnNames = (EditorColumnHash.Get(TabName(0))
        ?? Enumerable.Empty<string>())
            .Union(EditorColumnHash
                ?.Where(hash => TabId(hash.Key) > 0)
                .Select(hash => new { Id = TabId(hash.Key), Hash = hash })
                .Where(hash => hash.Id > 0)
                .SelectMany(hash => hash.Hash.Value)
                    ?? Enumerable.Empty<string>())
            .ToList();
    var postbackTargets = postbackColumn?.ColumnsReturnedWhenAutomaticPostback?.Split(',');
    if (postbackTargets?.Any() == true)
    {
        columnNames = postbackTargets
            .Where(columnName => columnNames.Contains(columnName))
            .ToList();
    }
    return columnNames;
}
```

**重要な発見**: `GetEditorColumnNames` は `_Section-{id}` を含む全エディタ列名リストを返す。しかし `FieldResponse` 内では:

```csharp
.Select(columnName => ss.GetColumn(context: context, columnName: columnName))
.Where(column => column != null)
```

`ss.GetColumn("_Section-1")` は通常の `Column` ではないため **`null` を返し、`Where` フィルタで除外される**。つまり、**`FieldResponse` はセクションの処理を一切行わない**。

---

## 6. 通常描画時のセクション処理との比較

### Fields メソッド（例: IssueUtilities.cs L2088-L2170）

通常の全ページ描画時には `Fields` メソッドが使用される:

```csharp
ss.GetEditorColumns(context: context, tab: tab, columnOnly: false)
    ?.Aggregate(new List<KeyValuePair<Section, List<string>>>(), (columns, column) =>
    {
        var sectionId = ss.SectionId(column.ColumnName);
        var section = ss.Sections?.FirstOrDefault(o => o.Id == sectionId);
        if (section != null)
        {
            columns.Add(new KeyValuePair<Section, List<string>>(
                new Section
                {
                    Id = section.Id,
                    LabelText = section.LabelText,
                    AllowExpand = section.AllowExpand,
                    Expand = section.Expand,
                    Hide = section.Hide       // ← Hide が参照される
                },
                new List<string>()));
        }
        // ...
    }).ForEach(section =>
    {
        if (section.Key == null) { /* セクション外のフィールド */ }
        else if (section.Key.Hide != true)  // ← Hide=true なら描画しない
        {
            hb.Div(id: $"SectionFields{section.Key.Id}Container", ...);
        }
    });
```

通常描画時は:

1. `_Section-{id}` エントリを検出し、対応する `Section` オブジェクトを取得
2. `Section.Hide == true` の場合はセクション全体を**描画しない**
3. サーバースクリプトで `siteSettings.Sections[i].Hide = true` とすると、参照経由で `SiteSettings.Sections` の同一オブジェクトが変更されるため、正しく動作する

---

## 7. SetValues におけるセクション変更の反映

### SetViewValues メソッド（ServerScriptUtilities.cs L974-L984）

```csharp
private static void SetViewValues(
    SiteSettings ss,
    ServerScriptModelSiteSettings data)
{
    if (ss == null) return;
    var viewId = data?.DefaultViewId ?? default;
    ss.GridView = ss?.Views?.Any(v => v.Id == viewId) == true ? viewId : default;
}
```

`SetValues` メソッドの末尾で `SetViewValues` が呼ばれるが、**`DefaultViewId` のみを処理し、`Sections` の変更は一切処理しない**。

ただし前述の通り、`ServerScriptModelSiteSettings.Sections` は
`SiteSettings.Sections` への**参照**であるため、サーバースクリプト内で
`siteSettings.Sections[i].Hide = true` と操作した場合、
`SiteSettings.Sections` の元オブジェクトも変更される。
したがって `SetViewValues` での明示的な反映処理は不要であり、
Sections のプロパティ変更自体は正しく `SiteSettings` に伝播する。

---

## 結論

| 項目                           | 通常描画時                                      | AutoPostBack 時                                  |
| ------------------------------ | ----------------------------------------------- | ------------------------------------------------ |
| サーバースクリプト実行         | `BeforeOpeningPage` が実行される                | `BeforeOpeningPage` が実行される（同じ）         |
| `siteSettings.Sections` の変更 | 参照経由で `SiteSettings.Sections` に反映される | 参照経由で `SiteSettings.Sections` に反映される  |
| レスポンス生成方式             | `Editor()` → `Fields()` で**全 HTML を再生成**  | `FieldResponse()` で**個別フィールド値のみ更新** |
| セクション表示/非表示の反映    | `Fields()` 内で `Section.Hide` をチェックし描画 | **セクション関連の処理なし**                     |
| `_Section-{id}` エントリの処理 | `SectionId()` で検出し、セクション描画に使用    | `GetColumn()` が `null` を返すため**スキップ**   |

### 根本原因

AutoPostBack 時のレスポンス生成（`FieldResponse`）は**個別カラムの値更新のみ**を行う設計であり、**セクションコンテナ（`#SectionFields{id}Container`）の表示/非表示制御は含まれていない**。

具体的には:

1. `FieldResponse` は `GetEditorColumnNames()` で取得した列名を
   `ss.GetColumn()` でカラムオブジェクトに変換するが、
   `_Section-{id}` は実カラムではないため `null` となりフィルタされる
2. 通常描画の `Fields()` メソッドが持つセクション表示/非表示ロジック（`section.Key.Hide != true` による分岐）に相当する処理が `FieldResponse` には存在しない
3. `EditorFields` メソッドも `FieldResponse` をコールするだけで、セクションの DOM 操作（表示/非表示の切り替え）を行うレスポンスを生成しない

---

## 対処方法

サーバースクリプトで AutoPostBack 時にセクションの表示/非表示を制御したい場合、以下の回避策が考えられる。

> **注意**: `elements` オブジェクト（`ServerScriptElements`）は
> **コマンドボタン・ナビゲーションメニュー・プロセスボタンなどの UI 要素専用**であり、
> セクションコンテナの表示制御には使用できない。
> `elements.DisplayType()` のキーは `HtmlCommands.cs`・`HtmlNavigationMenu.cs`・
> `HtmlProcess.cs` でのみ参照されるため、
> `SectionFields{id}Container` を指定しても効果はない。

### 1. クライアントスクリプトで AutoPostBack 後にセクション表示/非表示を制御する

`hidden` オブジェクトとクライアントスクリプトを組み合わせることで、サーバースクリプトの判定結果をクライアント側に伝達し、セクションの DOM を操作する。

**サーバースクリプト（BeforeOpeningPage）**:

```javascript
// 条件に基づいてセクション表示/非表示のフラグを hidden に設定
const shouldHide = model.ClassA === '非表示条件';
hidden.Add('HideSectionX', shouldHide ? '1' : '0');

// 通常描画時のために Sections の Hide も設定（併用推奨）
siteSettings.Sections.forEach(function (section) {
    if (section.Id === 1) {
        section.Hide = shouldHide;
    }
});
```

**クライアントスクリプト（on_editor_load イベント等）**:

```javascript
// AutoPostBack 完了後のセクション表示/非表示制御
$p.events.on_editor_load = function () {
    var hideFlag = $('#HideSectionX').val();
    if (hideFlag === '1') {
        $('#SectionFields1Container').hide();
    } else {
        $('#SectionFields1Container').show();
    }
};
```

> **注意**: `hidden` オブジェクトの値は**通常描画時**にのみ hidden input として
> HTML に出力されるため（`HtmlTemplates.HiddenServerScript`）、
> AutoPostBack レスポンスでは `#HideSectionX` の値は更新されない。
> この方法を使う場合は、`model` のフィールド値（クラス項目等）を
> クライアントスクリプト側で直接参照して判定するか、次の方法を使用する。

### 2. クライアントスクリプトのみで制御する（推奨）

AutoPostBack 時の制御をクライアントスクリプトに完全に委ねる。
`$p.ajax` の処理フロー（`_ajax.js`）には `ajax_after_done` イベントが用意されており、
AutoPostBack を含めたすべての Ajax 完了後に発火する。

**クライアントスクリプト**:

```javascript
// ajax_after_done はすべての Ajax レスポンス処理完了後に発火する
$p.events.ajax_after_done = function (args) {
    // AutoPostBack リクエスト時のみ処理する
    if (args && args[0] && args[0].indexOf('control-auto-postback') !== -1) {
        var classAValue = $('#Results_ClassA').val();
        if (classAValue === '非表示条件') {
            $('#SectionFields1Container').hide();
        } else {
            $('#SectionFields1Container').show();
        }
    }
};
```

この方法は以下の理由で最も実用的:

- `ajax_after_done` は `$p.ajax`（`_ajax.js` L99-L102）で定義されており、AutoPostBack の Ajax 完了後に確実に発火する
- フィールドの値が DOM に反映された後に実行されるため、最新の値を参照できる
- サーバースクリプトとの二重管理を避けられる

> **補足**: `EditorFields` のレスポンスには `.Events("on_editor_load")` が含まれないため、
> `on_editor_load` は AutoPostBack 完了後に発火しない。
> 代わりに `ajax_after_done` を使用する。

### 3. プリザンター本体の改修

#### 改修方針

本改修は 2 つの変更で構成される:

1. **初回描画の変更**: `Hide == true` のセクションもDOMに出力し、`display:none` で非表示にする
2. **AutoPostBack レスポンスの変更**: `EditorFields` でセクションの表示/非表示を `Toggle` で制御する

#### 前提知識: ResponseCollection.Toggle

`ResponseCollection.Toggle(name, value)` は既存のAPIで、クライアント側で jQuery の `.toggle(bool)` を実行する。`SiteUtilities.cs` 内で 3 箇所の使用実績がある。

```csharp
// ResponseCollection.cs L447-L458
public ResponseCollection Toggle(
    string name,
    bool value,
    bool _using = true)
{
    return _using
        ? Add(
            method: "Toggle",
            target: name,
            value: value.ToOneOrZeroString())
        : this;
}
```

クライアント側（`_dispatch.js` L134-L135）:

```javascript
case 'Toggle':
    $(target).toggle(value === '1');
```

#### 改修箇所 1: 初回描画 — Fields(HtmlBuilder) メソッド

**対象ファイル**:

- `IssueUtilities.cs` — `Fields` メソッド（L2088-L2189 付近）
- `ResultUtilities.cs` — `Fields` メソッド（対応する箇所）

**現状**: `section.Key.Hide == true` のセクションはDOMに出力されない。

```csharp
// IssueUtilities.cs L2152 付近
else if (section.Key.Hide != true)
{
    hb
        .Div(
            id: $"SectionFields{section.Key.Id}Container",
            css: "section-fields-container",
            action: () => hb
                // ... セクションの中身 ...
```

**問題**: 初回描画で `Hide=true` → AutoPostBack で `Hide=false` に変わった場合、セクションコンテナが DOM に存在しないため `Toggle(true)` が機能しない。

**改修案**: 条件を除去し、`Hide == true` のセクションも `display:none` 付きで DOM に出力する。

```csharp
// 改修後: section.Key.Hide の条件を除去し、style で制御
else
{
    hb
        .Div(
            id: $"SectionFields{section.Key.Id}Container",
            css: "section-fields-container",
            attributes: new HtmlAttributes()
                .Style("display:none;", _using: section.Key.Hide == true),
            action: () => hb
                // ... セクションの中身（既存コードそのまま） ...
```

> **`HtmlAttributes.Style` の使用パターン**:
> `HtmlControls.cs` L1080-L1083 に `.Style("display: none; ")` の使用実績がある。
> `_using` パラメータにより、`Hide == true` のときのみ
> `style="display:none;"` 属性が出力される。

**動作の変化**:

| 項目                     | 改修前             | 改修後                       |
| ------------------------ | ------------------ | ---------------------------- |
| `Hide=true` のセクション | DOM に出力されない | DOM に出力（`display:none`） |
| セクション内フィールド   | DOM に存在しない   | DOM に存在（非表示）         |
| フォーム送信データ       | 含まれない         | 含まれる（非表示でもsubmit） |

**フォーム送信データへの影響の検討**: `Hide=true` のセクション内フィールドがフォーム送信データに含まれるようになる。既存レコードのフィールド値はDB値が保持されるため、意図しないデータ変更のリスクは低い。新規レコードではデフォルト値が送信される。サーバースクリプトで値を変更しつつセクションを非表示にするユースケースでは、変更後の値が送信されるため、むしろ望ましい動作となる。

#### 改修箇所 2: AutoPostBack レスポンス — EditorFields メソッド

**対象ファイル**:

- `IssueUtilities.cs` — `EditorFields` メソッド（L2691-L2735）
- `ResultUtilities.cs` — `EditorFields` メソッド（L2504-L2550）

**現状**: `FieldResponse` の後にセクション表示/非表示の制御がない。

```csharp
// IssueUtilities.cs L2711-L2733
var ret = new ResponseCollection(context: context)
    .FieldResponse(
        context: context,
        ss: ss,
        issueModel: issueModel)
    .Html("#Notes", new HtmlBuilder().Notes(
        context: context,
        ss: ss,
        verType: issueModel.VerType,
        readOnly: issueModel.ReadOnly))
    // ...
```

**改修案**: `.FieldResponse()` の後に `.SectionToggleResponse(ss)` を追加する。

```csharp
// 改修後: SectionToggleResponse を追加
var ret = new ResponseCollection(context: context)
    .FieldResponse(
        context: context,
        ss: ss,
        issueModel: issueModel)
    .SectionToggleResponse(ss: ss) // ★ 追加
    .Html("#Notes", new HtmlBuilder().Notes(
        context: context,
        ss: ss,
        verType: issueModel.VerType,
        readOnly: issueModel.ReadOnly))
    // ...
```

> **WikiUtilities は改修不要**: Wiki の `EditorResponse` は
> AutoPostBack を含むすべてのケースで
> `ReplaceAll("#MainContainer", Editor(...))` を使用し、
> HTML 全体を再生成するため、セクションの表示/非表示は
> `Fields(HtmlBuilder)` の既存ロジックで正しく処理される。

#### 改修箇所 3: SectionToggleResponse 拡張メソッド（新規作成）

**新規ファイル**: `Implem.Pleasanter/Libraries/Responses/ResponseSections.cs`

`ResponseLookups.cs`（同ディレクトリ）の拡張メソッドパターンに準拠する。

```csharp
using Implem.Pleasanter.Libraries.Settings;
using System.Linq;

namespace Implem.Pleasanter.Libraries.Responses
{
    public static class ResponseSections
    {
        /// <summary>
        /// AutoPostBack レスポンスにセクションの表示/非表示 Toggle を追加する。
        /// サーバースクリプトで変更された Section.Hide の状態を
        /// クライアント側の DOM に反映する。
        /// </summary>
        public static ResponseCollection SectionToggleResponse(
            this ResponseCollection res,
            SiteSettings ss)
        {
            ss.Sections?.ForEach(section =>
            {
                res.Toggle(
                    name: $"#SectionFields{section.Id}Container",
                    value: section.Hide != true);
            });
            return res;
        }
    }
}
```

**ロジック**: `ss.Sections` の各セクションについて `Toggle` を発行する。

| `Section.Hide` の値  | `section.Hide != true` | Toggle の効果                      |
| -------------------- | ---------------------- | ---------------------------------- |
| `null`（デフォルト） | `true`                 | `$(target).toggle(true)` → 表示    |
| `false`              | `true`                 | `$(target).toggle(true)` → 表示    |
| `true`               | `false`                | `$(target).toggle(false)` → 非表示 |

> **パフォーマンスへの影響**: セクション数は通常数個程度であり、Toggle レスポンスの追加によるペイロード増加は軽微（1セクションあたり約 60 バイト）。

#### 改修対象ファイルの一覧

| ファイル                                                                              | 改修内容                                              | 種別             |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------- |
| `Libraries/Responses/ResponseSections.cs`                                             | `SectionToggleResponse` 拡張メソッド新規作成          | 新規（手動）     |
| `App_Data/Definitions/Definition_Code/Model_Utilities_EditorResponse_Tables_Body.txt` | `EditorFields` 内に `.SectionToggleResponse(ss)` 追加 | テンプレート修正 |
| `App_Data/Definitions/Definition_Code/Model_Utilities_EditorItem_Body.txt`            | セクション描画条件を `Style("display:none;")` に変更  | テンプレート修正 |
| `Models/Issues/IssueUtilities.cs`                                                     | ↑テンプレートから自動生成（CodeDefiner 実行で反映）   | 自動生成         |
| `Models/Results/ResultUtilities.cs`                                                   | ↑テンプレートから自動生成（CodeDefiner 実行で反映）   | 自動生成         |

#### 改修の制約事項

- **タブ内セクション**: `FieldSetTabs` は同一の `Fields(HtmlBuilder)` メソッドを使用するため、改修箇所 1 で一般タブ・追加タブ両方のセクションが対応される。
- **`AllowExpand`/`Expand` との併用**: Toggle はセクションコンテナ
  （`#SectionFields{id}Container`）全体の表示/非表示を制御する。
  セクション内の展開/折りたたみ状態
  （`#SectionFields{id}` の `hidden` クラス）は影響を受けない。
- **`ColumnsReturnedWhenAutomaticPostback` との関係**:
  セクションは列ではないため、AutoPostBack 対象列のフィルタリングの影響を受けない。
  `SectionToggleResponse` は列フィルタとは独立に動作する。

---

## CodeDefiner による自動コード生成との関係

`IssueUtilities.cs` および `ResultUtilities.cs` は
CodeDefiner（`Implem.CodeDefiner`）によるテンプレートベースの自動生成コードである。
生成済みの `.cs` ファイルを直接編集しても、
CodeDefiner 再実行時に上書きされる可能性がある。

### コード生成の仕組み

CodeDefiner は `App_Data/Definitions/Definition_Code/` 配下のテンプレート
（JSON + Body.txt）を読み込み、
`#ModelName#`・`#TableName#` 等のプレースホルダーを
テーブル名（Issues / Results 等）に置換して `.cs` ファイルを生成する。

```text
テンプレート (.json + _Body.txt)
    ↓ MvcCreator.CreateEachTable()
    ↓ Creators.Create() でテンプレート組み立て
    ↓ ReplacePlaceholder() でプレースホルダー展開
    ↓ Merger.Merge() で既存ファイルとマージ
生成コード (.cs)
```

### 改修箇所とテンプレートの対応

| 改修箇所                          | テンプレート Body ファイル                       | JSON 設定                                       |
| --------------------------------- | ------------------------------------------------ | ----------------------------------------------- |
| `EditorFields` / `EditorResponse` | `Model_Utilities_EditorResponse_Tables_Body.txt` | `Include: "Issues,Results"`, `GenericUi: "1"`   |
| `FieldResponse`                   | `Model_Utilities_FieldResponse_Body.txt`         | `Exclude: "Sites,Dashboards"`, `GenericUi: "1"` |
| `Fields`（セクション描画）        | `Model_Utilities_EditorItem_Body.txt`            | `ItemOnly: "1"`, `Exclude: "Sites,Dashboards"`  |

### EditorFields テンプレートの該当箇所

`Model_Utilities_EditorResponse_Tables_Body.txt`（L62-L102）:

```text
private static ResponseCollection EditorFields(
    Context context,
    SiteSettings ss,
    #ModelName#Model #modelName#Model)
{
    ...
    var ret = new ResponseCollection(context: context)
        .FieldResponse(
            context: context,
            ss: ss,
            #modelName#Model: #modelName#Model)
        .Html("#Notes", ...)
        ...
```

### Fields（セクション描画）テンプレートの該当箇所

`Model_Utilities_EditorItem_Body.txt`（L662 付近）:

```text
            else if (section.Key.Hide != true)
            {
                hb
                    .Div(
                        id: $"SectionFields{section.Key.Id}Container",
                        css: "section-fields-container",
                        action: () => hb
                            ...
```

### 改修アプローチの選択肢

| アプローチ                               | 方法                                                     | メリット                                  | デメリット                                                                                                         |
| ---------------------------------------- | -------------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **A. テンプレート改修**                  | `_Body.txt` ファイルを直接修正                           | CodeDefiner 再実行でも改修が維持される    | プリザンター本体のテンプレートを変更するため、アップデート時にコンフリクトする                                     |
| **B. 生成コード直接修正 + `/// Fixed:`** | 生成後の `.cs` を修正し、`/// Fixed:` コメントで保護     | テンプレートに触れずに改修できる          | CodeDefiner のマージロジックに依存。メソッド単位での保護のみ                                                       |
| **C. 拡張メソッドのみ（部分対応）**      | `ResponseSections.cs` の新規作成 + 生成コードへの1行追加 | 新規ファイルは CodeDefiner の対象外で安全 | `EditorFields` 内の `.SectionToggleResponse(ss)` 呼び出し追加と、`Fields` の描画条件変更は生成コードへの介入が必要 |

### `/// Fixed:` による保護の仕組み

CodeDefiner の `Parser.cs` は、メソッドのドキュメントコメントに `/// Fixed:` が含まれる場合、そのメソッドをマージ対象から除外する（`MergeFixedCode` で既存コードを保持）。

```csharp
// Parser.cs L60-L62
private void SetFixed()
{
    Fixed = Description.IndexOf("/// Fixed:") != -1;
}
```

実際に `IssueUtilities.cs` 内で `/// Fixed:` が使用されている例:

```csharp
// IssueUtilities.cs L2562-L2584
/// <summary>
/// Fixed:
/// </summary>
private static HtmlBuilder MainCommandExtensions(
    this HtmlBuilder hb,
    Context context,
    SiteSettings ss,
    IssueModel issueModel) { ... }
```

### 推奨アプローチ: テンプレート改修（A）

テンプレートを改修するアプローチが最も堅牢である。改修対象のテンプレートファイル:

| テンプレートファイル                             | 改修内容                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------ |
| `Model_Utilities_EditorResponse_Tables_Body.txt` | `EditorFields` 内に `.SectionToggleResponse(ss)` 追加                    |
| `Model_Utilities_EditorItem_Body.txt`            | `section.Key.Hide != true` 条件を除去し、`Style("display:none;")` に変更 |

改修後、`dotnet run --project Implem.CodeDefiner -- codedefiner` を実行すると、`IssueUtilities.cs` と `ResultUtilities.cs` に改修が自動展開される。

> **注意**: `ResponseSections.cs`（`Libraries/Responses/` 配下）は
> CodeDefiner の自動生成対象外である。
> CodeDefiner が `Libraries/Responses/` に生成するのは
> `Displays.cs`、`Messages.cs`、`ResponseSpecials.cs` の 3 ファイルのみであり、
> `ResponseSections.cs` は手動作成しても CodeDefiner 実行で削除・上書きされない。
> そのため、改修箇所 3（`ResponseSections.cs` 新規作成）は
> テンプレート改修なしで安全に実施できる。

---

## 関連ソースコード

| ファイル（`Implem.Pleasanter/` からの相対パス）                             | 内容                                            |
| --------------------------------------------------------------------------- | ----------------------------------------------- |
| `Libraries/Settings/SiteSettings.cs`                                        | Sections プロパティ定義、GetEditorColumnNames   |
| `Libraries/Settings/Section.cs`                                             | Section クラス定義（Hide プロパティ）           |
| `Libraries/Settings/ServerScript.cs`                                        | サーバースクリプト条件定義                      |
| `Libraries/Responses/ResponseCollection.cs`                                 | Toggle メソッド定義（L447-L458）                |
| `Libraries/Responses/ResponseLookups.cs`                                    | 拡張メソッドパターンの参考                      |
| `Libraries/Html/HtmlAttributes.cs`                                          | Style メソッド定義                              |
| `Libraries/ServerScripts/ServerScriptModelSiteSettings.cs`                  | siteSettings オブジェクトの実装                 |
| `Libraries/ServerScripts/ServerScriptModel.cs`                              | ServerScriptConditions 列挙体                   |
| `Libraries/ServerScripts/ServerScriptUtilities.cs`                          | サーバースクリプト実行・結果反映                |
| `Models/Issues/IssueUtilities.cs`                                           | Issue の EditorFields / FieldResponse / Fields  |
| `Models/Results/ResultUtilities.cs`                                         | Result の EditorFields / FieldResponse / Fields |
| `Models/Wikis/WikiUtilities.cs`                                             | Wiki の EditorResponse（改修不要の確認用）      |
| `Models/Sites/SiteUtilities.cs`                                             | Toggle メソッドの使用実績（3 箇所）             |
| `Models/Shared/_BaseModel.cs`                                               | SetByBeforeOpeningPageServerScript              |
| `Implem.PleasanterFrontend/wwwroot/src/scripts/generals/_controllevents.js` | controlAutoPostBack 関数                        |
| `Implem.PleasanterFrontend/wwwroot/src/scripts/generals/_dispatch.js`       | Toggle のクライアント側ハンドラ（L134-L135）    |

| ファイル（`Implem.Pleasanter/` からの相対パス）                                       | 内容                                       |
| ------------------------------------------------------------------------------------- | ------------------------------------------ |
| `App_Data/Definitions/Definition_Code/Model_Utilities_EditorResponse_Tables_Body.txt` | EditorFields テンプレート                  |
| `App_Data/Definitions/Definition_Code/Model_Utilities_EditorResponse_Tables.json`     | ↑の生成条件（`Include: "Issues,Results"`） |
| `App_Data/Definitions/Definition_Code/Model_Utilities_FieldResponse_Body.txt`         | FieldResponse テンプレート                 |
| `App_Data/Definitions/Definition_Code/Model_Utilities_EditorItem_Body.txt`            | Fields（セクション描画）テンプレート       |
| `App_Data/Definitions/Definition_Code/Model_Utilities_EditorItem.json`                | ↑の生成条件（`ItemOnly: "1"`）             |

| ファイル（`Implem.CodeDefiner/` からの相対パス） | 内容                                                 |
| ------------------------------------------------ | ---------------------------------------------------- |
| `Functions/AspNetMvc/CSharp/MvcCreator.cs`       | テンプレートからのコード生成（プレースホルダー展開） |
| `Functions/AspNetMvc/CSharp/Merger.cs`           | 生成コードと既存コードのマージ                       |
| `Functions/AspNetMvc/CSharp/Parser.cs`           | `/// Fixed:` による保護の判定ロジック                |
