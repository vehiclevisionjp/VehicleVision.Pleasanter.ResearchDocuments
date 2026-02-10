# プリザンター Sections サーバースクリプト AutoPostBack 動作調査

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
    - [対処方法の案](#対処方法の案)
- [関連ソースコード](#関連ソースコード)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 調査情報

| 調査日     | リポジトリ | ブランチ | タグ/バージョン    | コミット     | 備考                         |
| ---------- | ---------- | -------- | ------------------ | ------------ | ---------------------------- |
| 2026-02-10 | Pleasanter | -        | Pleasanter_1.5.0.0 | `8c261c0a80` | 初回調査                     |
| 2026-02-10 | Pleasanter | -        | Pleasanter_1.5.1.0 | `34f162a439` | 整合性チェック（行番号更新） |

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

**重要**: `Sections = ss?.Sections` は**参照の代入**である。`List<Section>` は参照型であり、`Section` もクラス（参照型）であるため、サーバースクリプト内で `siteSettings.Sections[i].Hide = true` のように個々のセクションのプロパティを変更すると、**元の `SiteSettings.Sections` の同一オブジェクトが変更される**。

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

ただし前述の通り、`ServerScriptModelSiteSettings.Sections` は `SiteSettings.Sections` への**参照**であるため、サーバースクリプト内で `siteSettings.Sections[i].Hide = true` と操作した場合、`SiteSettings.Sections` の元オブジェクトも変更される。したがって `SetViewValues` での明示的な反映処理は不要であり、Sections のプロパティ変更自体は正しく `SiteSettings` に伝播する。

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

1. `FieldResponse` は `GetEditorColumnNames()` で取得した列名を `ss.GetColumn()` でカラムオブジェクトに変換するが、`_Section-{id}` は実カラムではないため `null` となりフィルタされる
2. 通常描画の `Fields()` メソッドが持つセクション表示/非表示ロジック（`section.Key.Hide != true` による分岐）に相当する処理が `FieldResponse` には存在しない
3. `EditorFields` メソッドも `FieldResponse` をコールするだけで、セクションの DOM 操作（表示/非表示の切り替え）を行うレスポンスを生成しない

### 対処方法の案

サーバースクリプトで AutoPostBack 時にセクションの表示/非表示を制御したい場合、以下の回避策が考えられる。

> **注意**: `elements` オブジェクト（`ServerScriptElements`）は**コマンドボタン・ナビゲーションメニュー・プロセスボタンなどの UI 要素専用**であり、セクションコンテナの表示制御には使用できない。`elements.DisplayType()` のキーは `HtmlCommands.cs`・`HtmlNavigationMenu.cs`・`HtmlProcess.cs` でのみ参照されるため、`SectionFields{id}Container` を指定しても効果はない。

#### 1. クライアントスクリプトで AutoPostBack 後にセクション表示/非表示を制御する

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

> **注意**: `hidden` オブジェクトの値は**通常描画時**にのみ hidden input として HTML に出力されるため（`HtmlTemplates.HiddenServerScript`）、AutoPostBack レスポンスでは `#HideSectionX` の値は更新されない。この方法を使う場合は、`model` のフィールド値（クラス項目等）をクライアントスクリプト側で直接参照して判定するか、次の方法を使用する。

#### 2. クライアントスクリプトのみで制御する（推奨）

AutoPostBack 時の制御をクライアントスクリプトに完全に委ねる。`$p.ajax` の処理フロー（`_ajax.js`）には `ajax_after_done` イベントが用意されており、AutoPostBack を含めたすべての Ajax 完了後に発火する。

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

> **補足**: `EditorFields` のレスポンスには `.Events("on_editor_load")` が含まれないため、`on_editor_load` は AutoPostBack 完了後に発火しない。代わりに `ajax_after_done` を使用する。

#### 3. プリザンター本体の改修（将来的な対応）

`FieldResponse` メソッドにセクションコンテナの表示/非表示を制御するレスポンスを追加する改修を行う。具体的には、`EditorFields` メソッド内で `ss.Sections` の `Hide` プロパティを参照し、`res.Toggle()` や `res.ReplaceAll()` でセクションコンテナの表示状態を制御する処理を追加する。

---

## 関連ソースコード

| ファイル（`Implem.Pleasanter/` からの相対パス）                             | 内容                                          |
| --------------------------------------------------------------------------- | --------------------------------------------- |
| `Libraries/Settings/SiteSettings.cs`                                        | Sections プロパティ定義、GetEditorColumnNames |
| `Libraries/Settings/Section.cs`                                             | Section クラス定義（Hide プロパティ）         |
| `Libraries/Settings/ServerScript.cs`                                        | サーバースクリプト条件定義                    |
| `Libraries/ServerScripts/ServerScriptModelSiteSettings.cs`                  | siteSettings オブジェクトの実装               |
| `Libraries/ServerScripts/ServerScriptModel.cs`                              | ServerScriptConditions 列挙体                 |
| `Libraries/ServerScripts/ServerScriptUtilities.cs`                          | サーバースクリプト実行・結果反映              |
| `Models/Issues/IssueUtilities.cs`                                           | Issue の EditorResponse / FieldResponse       |
| `Models/Results/ResultUtilities.cs`                                         | Result の EditorResponse / FieldResponse      |
| `Models/Shared/_BaseModel.cs`                                               | SetByBeforeOpeningPageServerScript            |
| `Implem.PleasanterFrontend/wwwroot/src/scripts/generals/_controllevents.js` | controlAutoPostBack 関数                      |
