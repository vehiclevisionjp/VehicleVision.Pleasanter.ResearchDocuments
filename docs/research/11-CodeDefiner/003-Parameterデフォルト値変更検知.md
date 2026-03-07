# パラメータデフォルト値の変更検知方式

案A（C# デフォルト値 + 部分 JSON 方式）を採用するにあたり、バージョンアップ時に C# 側のデフォルト値が変更された場合の検知・通知方法を調査する。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [案A の前提整理](#案a-の前提整理)
    - [動作原理](#動作原理)
    - [バージョンアップ時のデフォルト値変更パターン](#バージョンアップ時のデフォルト値変更パターン)
    - [通知が必要なケース](#通知が必要なケース)
- [デフォルト値変更が検知困難な理由](#デフォルト値変更が検知困難な理由)
- [検知方式の候補](#検知方式の候補)
    - [方式1: デフォルト値スナップショット比較（起動時自動検知）](#方式1-デフォルト値スナップショット比較起動時自動検知)
    - [方式2: CodeDefiner サブコマンド（明示的な差分レポート）](#方式2-codedefiner-サブコマンド明示的な差分レポート)
    - [方式3: デフォルト値マニフェスト同梱方式](#方式3-デフォルト値マニフェスト同梱方式)
    - [方式4: `[DefaultValue]` 属性の標準化 + 起動時バリデーション](#方式4-defaultvalue-属性の標準化--起動時バリデーション)
    - [方式5: ソースコード差分方式（Git タグ間比較）](#方式5-ソースコード差分方式git-タグ間比較)
- [方式の比較](#方式の比較)
- [推奨方式](#推奨方式)
    - [方式1 + 方式2 のハイブリッド](#方式1--方式2-のハイブリッド)
    - [詳細設計](#詳細設計)
- [既存コードへの改修箇所](#既存コードへの改修箇所)
    - [改修対象一覧](#改修対象一覧)
    - [段階的な導入計画](#段階的な導入計画)
- [複合型プロパティの扱い](#複合型プロパティの扱い)
    - [ネストオブジェクトのデフォルト値比較](#ネストオブジェクトのデフォルト値比較)
    - [コンストラクタで初期化されるクラス](#コンストラクタで初期化されるクラス)
    - [`[OnDeserialized]` パターンとの整合](#ondeserialized-パターンとの整合)
- [結論](#結論)
- [関連ソースコード](#関連ソースコード)
- [関連ドキュメント](#関連ドキュメント)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 調査情報

| 調査日       | リポジトリ | ブランチ           | タグ/バージョン | コミット    | 備考     |
| ------------ | ---------- | ------------------ | --------------- | ----------- | -------- |
| 2026年3月7日 | Pleasanter | Pleasanter_1.5.1.0 | v1.5.1.0        | `34f162a43` | 初回調査 |

## 調査目的

[前回の調査](002-CodeDefiner-Parameterマージ.md)で推奨した案A（C# デフォルト値 + 部分 JSON 方式）では、
ユーザーは変更したプロパティのみを JSON に記載し、
未記載のプロパティは C# フィールド初期化子のデフォルト値で動作する。
この方式では**バージョンアップで C# 側のデフォルト値が変更された場合、
JSON に未記載のプロパティは暗黙的に新しい値に切り替わる**。
これは多くの場合は望ましい動作だが、
運用に影響する変更（タイムアウト値の変更、機能の有効/無効切り替え等）については管理者への通知が必要である。

本ドキュメントでは、デフォルト値の変更を検知し通知する具体的な方式を検討する。

---

## 案A の前提整理

### 動作原理

Newtonsoft.Json の `DeserializeObject<T>()` は以下の順序で動作する。

1. `new T()` でインスタンスを生成（C# フィールド初期化子のデフォルト値が適用）
2. JSON に存在するプロパティだけを上書き
3. JSON に書かれていないプロパティは C# のデフォルト値がそのまま残る

### バージョンアップ時のデフォルト値変更パターン

```mermaid
flowchart TD
    subgraph v1["v1.5.0 の C# デフォルト"]
        A1["ServerScriptTimeOut = 10000"]
        A2["PageSize = 200"]
    end
    subgraph v2["v1.6.0 の C# デフォルト（値変更）"]
        B1["ServerScriptTimeOut = 30000"]
        B2["PageSize = 200"]
    end
    subgraph json["ユーザーの部分 JSON（変更なし）"]
        C1["{ }（空 = 全てデフォルト）"]
    end

    v1 --> |"DLL 差し替え"| v2
    v2 --> D["起動時デシリアライズ"]
    json --> D
    D --> E["ServerScriptTimeOut = 30000\n（暗黙的に変更される）"]
    D --> F["PageSize = 200\n（変更なし）"]
```

### 通知が必要なケース

| ケース                                               | 影響度 | 例                                         |
| ---------------------------------------------------- | :----: | ------------------------------------------ |
| タイムアウト値・リトライ回数等の性能パラメータの変更 |   中   | `ServerScriptTimeOut`: 10000 → 30000       |
| 機能の有効/無効のデフォルト切り替え                  |   高   | `ServerScript`: true → false               |
| セキュリティ関連パラメータの変更                     |   高   | `PasswordExpirationPeriod`: 0 → 90         |
| API バージョン・互換性フラグの変更                   |   高   | `Compatibility_1_3_12`: false → true       |
| 文字列パターン（正規表現等）の変更                   |   低   | `ChoiceSplitRegexPattern` の正規表現変更   |
| 新プロパティ追加（デフォルト値付き）                 |   低   | 新しい機能フラグが追加されデフォルトで有効 |
| 数値の上限/下限の変更                                |   中   | `LimitPerSite`: 0（無制限） → 1000         |

---

## デフォルト値変更が検知困難な理由

案A では JSON に未記載のプロパティは C# デフォルト値がそのまま使われるため、**どのプロパティが「ユーザーが意図的にデフォルトのままにしている」のか「ユーザーが存在を知らない」のかを区別できない**。

```mermaid
flowchart LR
    subgraph problem["区別不能な2つの状態"]
        P1["JSON に未記載\n= ユーザーがデフォルトでよいと判断"]
        P2["JSON に未記載\n= ユーザーがプロパティの存在を知らない"]
    end
    P1 --> R["どちらも同じ結果:\nC# デフォルト値が適用される"]
    P2 --> R
```

現行のコードにはデフォルト値の変更を検知する仕組みは存在しない。`Read<T>()` メソッドは JSON の読み込みとデシリアライズのみを行い、デフォルト値との比較は一切行わない。

---

## 検知方式の候補

### 方式1: デフォルト値スナップショット比較（起動時自動検知）

起動時にリフレクションで C# デフォルト値のスナップショットを生成し、前回起動時のスナップショットと比較する方式。

#### 仕組み

```mermaid
sequenceDiagram
    participant App as アプリケーション起動
    participant Init as Initializer
    participant Snap as スナップショット管理
    participant Log as ログ出力

    App->>Init: SetParameters()
    Init->>Init: Read<T>() で各パラメータ読み込み
    Init->>Snap: 現在の C# デフォルト値を生成<br/>new T() → JSON シリアライズ
    Snap->>Snap: 前回スナップショットと比較
    alt デフォルト値に変更あり
        Snap->>Log: 変更されたプロパティを警告出力
    end
    Snap->>Snap: 現在のスナップショットを保存
```

#### 実装イメージ

```csharp
public static class DefaultsSnapshot
{
    private const string SnapshotDir = "App_Data/Parameters/.defaults-snapshot";

    /// <summary>
    /// C# デフォルト値のスナップショットを生成し、前回と比較する。
    /// 変更があればログに警告を出力する。
    /// </summary>
    public static void CompareAndUpdate<T>() where T : new()
    {
        var name = typeof(T).Name;
        var currentDefaults = new T();
        var currentJson = JsonConvert.SerializeObject(
            currentDefaults, Formatting.Indented);

        var snapshotPath = Path.Combine(SnapshotDir, $"{name}.json");
        if (File.Exists(snapshotPath))
        {
            var previousJson = File.ReadAllText(snapshotPath);
            if (currentJson != previousJson)
            {
                var changes = DetectChanges(previousJson, currentJson);
                foreach (var change in changes)
                {
                    Console.WriteLine(
                        $"[WARN] {name}.{change.Property}: "
                        + $"デフォルト値が変更されました "
                        + $"({change.OldValue} → {change.NewValue})");
                }
            }
        }
        Directory.CreateDirectory(SnapshotDir);
        File.WriteAllText(snapshotPath, currentJson);
    }
}
```

#### 評価

| 項目           | 評価                                                                        |
| -------------- | --------------------------------------------------------------------------- |
| 検知タイミング | 起動時に自動検知                                                            |
| 検知精度       | C# デフォルト値の全プロパティを網羅的に比較可能                             |
| 実装コスト     | 小（リフレクション + JSON 比較のみ）                                        |
| 運用負荷       | なし（自動動作）                                                            |
| 制約           | 初回起動時はスナップショットがないため比較不可                              |
| 副作用         | スナップショットファイルの管理が必要（`.defaults-snapshot/` の Git 管理等） |

---

### 方式2: CodeDefiner サブコマンド（明示的な差分レポート）

CodeDefiner に `compare-defaults` サブコマンドを追加し、バージョンアップ前後のデフォルト値差分をレポートする方式。

#### 仕組み

```mermaid
flowchart TD
    A["dotnet Implem.CodeDefiner.dll\ncompare-defaults /b:{backupPath}"] --> B["旧バージョン DLL から\nパラメータクラスをロード"]
    B --> C["新バージョン DLL から\nパラメータクラスをロード"]
    C --> D["リフレクションで\nnew T() のデフォルト値を比較"]
    D --> E["差分レポート出力"]
```

#### 出力イメージ

```text
=== パラメータデフォルト値 変更レポート ===
比較: v1.5.0.0 → v1.5.1.0

[変更あり] Script.json:
  ServerScriptTimeOut: 10000 → 30000
  ServerScriptTimeOutMax: 86400000 → 172800000

[変更あり] Security.json:
  PasswordExpirationPeriod: 0 → 90
  MinimumPasswordLength: 8 → 10

[変更なし] Api.json
[変更なし] Rds.json
[新規追加] NewFeature.json (v1.5.1.0 で追加)

合計: 2 ファイルに変更、4 プロパティが変更されました。
```

#### 評価

| 項目           | 評価                                                                            |
| -------------- | ------------------------------------------------------------------------------- |
| 検知タイミング | バージョンアップ時に管理者が明示的に実行                                        |
| 検知精度       | DLL 間の直接比較で正確                                                          |
| 実装コスト     | 中（DLL の動的ロード + リフレクション + レポート生成）                          |
| 運用負荷       | 小（バージョンアップ手順に組み込み可能）                                        |
| 制約           | 旧バージョンの DLL が必要（バックアップから取得）                               |
| 副作用         | 異なるバージョンの DLL を同一プロセスにロードする際の依存関係の問題が発生しうる |

#### DLL 動的ロードの技術的課題

異なるバージョンの DLL を同一プロセスで扱う場合、以下の課題がある。

| 課題                  | 説明                                                                 | 対策                                              |
| --------------------- | -------------------------------------------------------------------- | ------------------------------------------------- |
| 型の不一致            | 同じ名前のクラスでも異なる DLL からロードすると別の型として扱われる  | JSON シリアライズ経由で比較する（型に依存しない） |
| 依存関係の競合        | 新旧 DLL が異なるバージョンの Newtonsoft.Json 等に依存する場合がある | `AssemblyLoadContext` で分離ロードする            |
| プロパティの追加/削除 | 旧バージョンに存在しないプロパティの比較ができない                   | JSON 化して `JObject` レベルで比較する            |

この課題を回避するため、**DLL からリフレクションでデフォルト値を JSON にエクスポートし、JSON 同士で比較する**方式が現実的である。

---

### 方式3: デフォルト値マニフェスト同梱方式

リリース時に全パラメータクラスのデフォルト値を JSON ファイル（マニフェスト）として DLL に埋め込み、バージョン間で比較する方式。

#### 仕組み

```mermaid
flowchart TD
    subgraph build["ビルド時"]
        B1["MSBuild タスク / Source Generator"] --> B2["全パラメータクラスの\nnew T() をシリアライズ"]
        B2 --> B3["defaults-manifest.json\nを埋め込みリソースとして生成"]
    end
    subgraph runtime["実行時"]
        R1["起動時にマニフェストを読み込み"] --> R2["前回バージョンのマニフェストと比較"]
        R2 --> R3["変更レポート出力"]
    end
    build --> runtime
```

#### マニフェストの形式

```json
{
    "version": "1.5.1.0",
    "generatedAt": "2026-03-07T00:00:00Z",
    "defaults": {
        "Api": {
            "Version": 0,
            "Enabled": false,
            "PageSize": 0,
            "LimitPerSite": 0,
            "Compatibility_1_3_12": false
        },
        "Script": {
            "ServerScript": true,
            "ServerScriptTimeOut": 10000,
            "ServerScriptTimeOutMax": 86400000
        }
    }
}
```

#### 評価

| 項目           | 評価                                                     |
| -------------- | -------------------------------------------------------- |
| 検知タイミング | 起動時に自動検知                                         |
| 検知精度       | ビルド時に生成するため正確                               |
| 実装コスト     | 大（MSBuild タスクまたは Source Generator の実装が必要） |
| 運用負荷       | なし（自動動作）                                         |
| 制約           | ビルドパイプラインの変更が必要                           |
| 副作用         | DLL サイズの微増                                         |

---

### 方式4: `[DefaultValue]` 属性の標準化 + 起動時バリデーション

既に `Script.cs` 等で部分的に使われている `[DefaultValue]` 属性を全パラメータクラスに拡張し、属性値とフィールド初期化子の一貫性を保証する方式。

#### 現状の使用パターン

```csharp
// Script.cs - [DefaultValue] とフィールド初期化子の二重定義
[DefaultValue(true)]
public bool ServerScript { get; set; } = true;

[DefaultValue(10000)]
public long ServerScriptTimeOut { get; set; } = 10000;
```

`[DefaultValue]` 属性は現在のコードでは**メタデータとしてのみ存在し、実行時に読み取られていない**。

#### 活用方法

```csharp
public static class DefaultValueValidator
{
    /// <summary>
    /// [DefaultValue] 属性の値とフィールド初期化子の値が一致しているか検証する。
    /// 不一致はデフォルト値の変更漏れ（属性の更新忘れ）を示す。
    /// </summary>
    public static void Validate<T>() where T : new()
    {
        var instance = new T();
        foreach (var prop in typeof(T).GetProperties())
        {
            var attr = prop.GetCustomAttribute<DefaultValueAttribute>();
            if (attr == null) continue;

            var actualDefault = prop.GetValue(instance);
            if (!Equals(attr.Value, actualDefault))
            {
                Console.WriteLine(
                    $"[WARN] {typeof(T).Name}.{prop.Name}: "
                    + $"[DefaultValue({attr.Value})] と "
                    + $"フィールド初期化子({actualDefault}) が不一致");
            }
        }
    }
}
```

#### 評価

| 項目           | 評価                                                                  |
| -------------- | --------------------------------------------------------------------- |
| 検知タイミング | 起動時またはテスト時                                                  |
| 検知精度       | `[DefaultValue]` 属性が付与されたプロパティのみ対象                   |
| 実装コスト     | 中（全クラスへの `[DefaultValue]` 属性追加 + バリデーションロジック） |
| 運用負荷       | 中（プロパティ追加/変更時に属性の更新が必要）                         |
| 制約           | 属性の更新忘れが発生しうる（属性値とフィールド初期化子の二重管理）    |
| 副作用         | なし                                                                  |

この方式は**デフォルト値の二重管理**が必要であり、属性の更新忘れというヒューマンエラーのリスクがある。ただし、方式1と組み合わせて「`[DefaultValue]` 属性とフィールド初期化子の一貫性チェック」として利用する価値はある。

---

### 方式5: ソースコード差分方式（Git タグ間比較）

バージョンアップ時に `Implem.ParameterAccessor/Parts/*.cs` ファイルの Git 差分を解析し、フィールド初期化子の変更を検出する方式。

#### 実行イメージ

```bash
# v1.5.0 → v1.5.1 間のパラメータクラス変更を検出
git diff v1.5.0.0..v1.5.1.0 -- Implem.ParameterAccessor/Parts/
```

#### 評価

| 項目           | 評価                                                           |
| -------------- | -------------------------------------------------------------- |
| 検知タイミング | バージョンアップ前に手動実行                                   |
| 検知精度       | ソースレベルで正確（ただしパース精度に依存）                   |
| 実装コスト     | 小（Git コマンドのみ。自動解析にはパーサーが必要）             |
| 運用負荷       | 中（手動実行 + 出力の読解が必要）                              |
| 制約           | Git リポジトリへのアクセスが必要、ソース非公開の場合は使用不可 |
| 副作用         | なし                                                           |

ソースコードが公開されているプリザンターでは有効だが、**自動化が困難**であり、運用手順としての定着が課題となる。

---

## 方式の比較

| 方式                                  | 自動検知 | 精度 | 実装コスト | 運用負荷 | 本体改修 |
| ------------------------------------- | :------: | :--: | :--------: | :------: | :------: |
| **1: スナップショット比較（起動時）** | **自動** |  高  |   **小**   | **なし** |   必要   |
| 2: CodeDefiner サブコマンド           |   手動   |  高  |     中     |    小    |   必要   |
| 3: デフォルト値マニフェスト同梱       |   自動   |  高  |     大     |   なし   |   必要   |
| 4: `[DefaultValue]` 属性標準化        |   自動   |  中  |     中     |    中    |   必要   |
| 5: ソースコード差分（Git タグ間）     |   手動   |  高  |     小     |    中    |   不要   |

---

## 推奨方式

### 方式1 + 方式2 のハイブリッド

**方式1（スナップショット比較）** を主軸とし、**方式2（CodeDefiner サブコマンド）** を補助的に利用する構成を推奨する。

```mermaid
flowchart TD
    subgraph primary["主軸: 方式1 - 起動時自動検知"]
        P1["アプリ起動"] --> P2["new T() で\n現在の C# デフォルト値を取得"]
        P2 --> P3["前回スナップショットと比較"]
        P3 --> P4{"変更あり?"}
        P4 -->|あり| P5["変更内容をログ出力\n（WARN レベル）"]
        P4 -->|なし| P6["通常起動"]
        P5 --> P7["新スナップショットを保存"]
        P6 --> P7
    end
    subgraph secondary["補助: 方式2 - 明示的レポート"]
        S1["dotnet Implem.CodeDefiner.dll\ncompare-defaults"] --> S2["全パラメータの\nデフォルト値一覧を出力"]
        S2 --> S3["バージョンアップ前後の\n差分レポート"]
    end
```

#### 推奨理由

| 理由                   | 説明                                                                                                 |
| ---------------------- | ---------------------------------------------------------------------------------------------------- |
| 実装コストが最小       | 方式1はリフレクション + JSON 比較のみで実現可能                                                      |
| 自動検知で見落とし防止 | 起動時に自動で検知するため、管理者の作業忘れによる見落としがない                                     |
| 既存の仕組みと整合     | `Read<T>()` の直後にスナップショット比較を挿入するだけで、既存のパラメータ読み込みフローを変更しない |
| CodeDefiner で事前確認 | バージョンアップ前に差分を確認し、影響範囲を事前に把握できる                                         |

### 詳細設計

#### スナップショットの保存場所

```text
App_Data/Parameters/
├── Api.json                  ← ユーザーパラメータ（部分 JSON）
├── Script.json
├── ...
└── .defaults-snapshot/       ← デフォルト値スナップショット（自動生成）
    ├── .gitignore            ← Git 管理対象外
    ├── Api.json
    ├── Script.json
    └── ...
```

`.defaults-snapshot/` ディレクトリは自動生成・自動更新されるため、ユーザーが直接編集する必要はない。

#### ログ出力の形式

```text
[2026-03-07 09:00:00] [WARN] パラメータデフォルト値の変更を検知しました:
[2026-03-07 09:00:00] [WARN]   Script.ServerScriptTimeOut: 10000 → 30000
[2026-03-07 09:00:00] [WARN]   Script.ServerScriptTimeOutMax: 86400000 → 172800000
[2026-03-07 09:00:00] [WARN]   Security.MinimumPasswordLength: 8 → 10
[2026-03-07 09:00:00] [WARN] 上記のプロパティは JSON に未記載のためデフォルト値が適用されています。
[2026-03-07 09:00:00] [WARN] 変更を維持する場合は対応不要です。
[2026-03-07 09:00:00] [WARN] 旧デフォルト値に戻す場合はパラメータ JSON に明示的に値を記載してください。
```

#### JSON に記載済みのプロパティとの区別

スナップショット比較だけではデフォルト値が変わったことしか分からない。**ユーザーの JSON に記載されていないプロパティのみ警告する**ためには、以下の追加処理が必要となる。

```csharp
/// <summary>
/// ユーザーの JSON に記載されていない（= デフォルト値に依存している）
/// プロパティのうち、デフォルト値が変更されたものを検出する。
/// </summary>
public static List<DefaultChange> DetectAffectedChanges<T>(
    string userJson,
    string previousDefaultsJson,
    string currentDefaultsJson) where T : new()
{
    var userObj = string.IsNullOrEmpty(userJson)
        ? new JObject()
        : JObject.Parse(userJson);
    var prevDefaults = JObject.Parse(previousDefaultsJson);
    var currDefaults = JObject.Parse(currentDefaultsJson);

    var changes = new List<DefaultChange>();
    foreach (var prop in currDefaults.Properties())
    {
        // ユーザー JSON に記載されているプロパティはスキップ
        // （ユーザーが明示的に値を指定しているため影響なし）
        if (userObj.ContainsKey(prop.Name)) continue;

        var prevValue = prevDefaults[prop.Name];
        var currValue = prop.Value;
        if (!JToken.DeepEquals(prevValue, currValue))
        {
            changes.Add(new DefaultChange
            {
                Property = prop.Name,
                OldValue = prevValue?.ToString(),
                NewValue = currValue?.ToString()
            });
        }
    }
    return changes;
}
```

この処理により、ユーザーが JSON で明示的に値を指定しているプロパティについてはデフォルト値の変更があっても警告を出さない（ユーザーの設定が優先されるため影響がない）。

#### 処理フロー全体

```mermaid
sequenceDiagram
    participant App as アプリケーション
    participant Init as Initializer.SetParameters()
    participant Read as Read<T>()
    participant Snap as DefaultsSnapshot
    participant Log as ログ

    App->>Init: 起動
    loop 各パラメータクラス T
        Init->>Read: Read<T>()
        Read-->>Init: パラメータ値（JSON + デフォルト）

        Init->>Snap: CompareAndUpdate<T>(userJson)
        Snap->>Snap: currentDefaults = new T()
        Snap->>Snap: 前回スナップショットを読み込み
        alt 前回スナップショットが存在する
            Snap->>Snap: デフォルト値の差分を検出
            Snap->>Snap: ユーザー JSON に未記載の<br/>変更プロパティを抽出
            alt 影響のある変更あり
                Snap->>Log: WARN: デフォルト値変更の通知
            end
        end
        Snap->>Snap: 現在のデフォルト値を<br/>スナップショットに保存
    end
    Init-->>App: パラメータ初期化完了
```

---

## 既存コードへの改修箇所

案A（デフォルト値整備）とデフォルト値変更検知を導入する場合の改修対象を整理する。

### 改修対象一覧

| 改修対象                                        | 内容                                                       | 工数 |
| ----------------------------------------------- | ---------------------------------------------------------- | :--: |
| `Implem.ParameterAccessor/Parts/*.cs`（約70件） | JSON の値をフィールド初期化子に転記                        |  中  |
| `Implem.DefinitionAccessor/Initializer.cs`      | `Read<T>(required: false)` への変更 + スナップショット比較 |  小  |
| `DefaultsSnapshot.cs`（新規）                   | スナップショット生成・比較・保存ロジック                   |  小  |
| `Implem.CodeDefiner/Starter.cs`                 | `compare-defaults` サブコマンドの追加                      |  小  |

### 段階的な導入計画

```mermaid
flowchart LR
    subgraph phase1["Phase 1: デフォルト値整備"]
        A1["約70クラスに\nフィールド初期化子を追加"]
        A2["Read<T>(required: false)\nへの段階的切り替え"]
    end
    subgraph phase2["Phase 2: 変更検知"]
        B1["DefaultsSnapshot クラス\nの実装"]
        B2["Initializer への\nスナップショット比較組み込み"]
    end
    subgraph phase3["Phase 3: CodeDefiner 拡張"]
        C1["compare-defaults\nサブコマンドの実装"]
        C2["バージョンアップ手順への\n組み込み"]
    end
    phase1 --> phase2 --> phase3
```

| Phase   | 内容                                                          | 前提条件     |
| ------- | ------------------------------------------------------------- | ------------ |
| Phase 1 | C# クラスへのデフォルト値転記、`required: false` への切り替え | なし         |
| Phase 2 | スナップショット比較による起動時自動検知の実装                | Phase 1 完了 |
| Phase 3 | CodeDefiner サブコマンドによる明示的差分レポートの実装        | Phase 1 完了 |

Phase 2 と Phase 3 は独立して実装可能であり、Phase 1 の完了後に並行して進められる。

---

## 複合型プロパティの扱い

### ネストオブジェクトのデフォルト値比較

`PleasanterExtensions.cs` のようにネストされたオブジェクトを持つパラメータクラスでは、`JToken.DeepEquals()` によるディープ比較が必要となる。

```csharp
// PleasanterExtensions.cs
public class PleasanterExtensions
{
    public class SiteVisualizerData
    {
        public bool Disabled { get; set; } = false;
        public int ErdLinkDepth { get; set; } = 10;
        public int ErdLinkLimit { get; set; } = 60;
    }
    public SiteVisualizerData SiteVisualizer = new();
}
```

スナップショット方式では `new T()` → `JsonConvert.SerializeObject()` でネストオブジェクトも含めて JSON 化されるため、特別な処理なしにディープ比較が可能である。

### コンストラクタで初期化されるクラス

`QuartzClustering` のようにコンストラクタでデフォルト値を設定するパターンも、`new T()` で正しくデフォルト値が反映される。

```csharp
// Quartz.cs
public class QuartzClustering
{
    public QuartzClustering()
    {
        Enabled = false;
        SchedulerName = "PleasanterScheduler";
        // ...
    }
}
```

### `[OnDeserialized]` パターンとの整合

`Rds.cs` の `[OnDeserialized]` パターンは JSON デシリアライズ後に実行されるため、`new T()` だけでは `Dbms` が空文字列のままとなる。

```csharp
// Rds.cs
[OnDeserialized]
private void OnDeserialized(StreamingContext streamingContext)
{
    Dbms = string.IsNullOrWhiteSpace(Dbms) ? "SQLServer" : Dbms;
}
```

スナップショット生成時は `new T()` → `JsonConvert.SerializeObject()`
→ `JsonConvert.DeserializeObject<T>()` のラウンドトリップを行うことで
`[OnDeserialized]` も発火させる必要がある。

---

## 結論

| 項目             | 内容                                                                                                                           |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| 採用方式         | 案A（C# デフォルト値 + 部分 JSON 方式）                                                                                        |
| デフォルト値検知 | **方式1（スナップショット比較）を主軸**とし、方式2（CodeDefiner サブコマンド）を補助的に利用                                   |
| 検知の仕組み     | 起動時に `new T()` でデフォルト値を生成し、前回スナップショットと比較。ユーザー JSON に未記載のプロパティのみ変更を警告        |
| ログ出力         | WARN レベルで変更内容を出力。ユーザー JSON に記載済みのプロパティは警告対象外                                                  |
| 導入計画         | Phase 1（デフォルト値整備）→ Phase 2（起動時検知）→ Phase 3（CodeDefiner 拡張）の段階的導入                                    |
| 既存環境への影響 | 既存の全プロパティ記載 JSON はそのまま動作し、破壊的変更なし。スナップショット比較による警告はログ出力のみで動作には影響しない |

## 関連ソースコード

| ファイル                                   | 説明                                         |
| ------------------------------------------ | -------------------------------------------- |
| `Implem.DefinitionAccessor/Initializer.cs` | パラメータ初期化・`Read<T>()` メソッド       |
| `Implem.ParameterAccessor/Parts/*.cs`      | パラメータクラス定義（デフォルト値整備対象） |
| `Implem.ParameterAccessor/Parameters.cs`   | パラメータインスタンス保持クラス             |
| `Implem.Libraries/Utilities/Jsons.cs`      | JSON デシリアライズ（`Deserialize<T>()`）    |
| `Implem.CodeDefiner/Starter.cs`            | CLI エントリポイント・コマンド定義           |
| `Implem.ParameterAccessor/Parts/Script.cs` | `[DefaultValue]` 属性の使用例                |
| `Implem.ParameterAccessor/Parts/Rds.cs`    | `[OnDeserialized]` パターンの使用例          |
| `Implem.ParameterAccessor/Parts/Quartz.cs` | コンストラクタデフォルトの使用例             |

## 関連ドキュメント

| ドキュメント                                                                                | 説明                                            |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| [CodeDefiner パラメータマージ（merge）の問題点と代替案](002-CodeDefiner-Parameterマージ.md) | 案A 〜 E の比較検討（本調査の前提ドキュメント） |
