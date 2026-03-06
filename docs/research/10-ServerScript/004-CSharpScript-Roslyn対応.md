# C# Script（Roslyn Scripting API）ServerScript 対応の実現可能性調査

ServerScript のスクリプト言語として C# Script（Roslyn Scripting API）を追加する場合の技術的実現可能性、サンドボックス構築の可否、既存の ClearScript（V8）/ IronPython との比較を調査する。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [調査情報](#調査情報)
- [調査目的](#調査目的)
- [Roslyn Scripting API 概要](#roslyn-scripting-api-概要)
    - [NuGet パッケージ](#nuget-パッケージ)
    - [基本的な使用方法](#基本的な使用方法)
    - [コンパイルと実行の分離](#コンパイルと実行の分離)
    - [グローバルオブジェクト（ホストオブジェクト注入）](#グローバルオブジェクトホストオブジェクト注入)
    - [パフォーマンス特性](#パフォーマンス特性)
- [サンドボックス / セキュリティモデル](#サンドボックス--セキュリティモデル)
    - [根本的な問題：.NET ランタイム上での実行](#根本的な問題net-ランタイム上での実行)
    - [ScriptOptions による制御機能](#scriptoptions-による制御機能)
    - [ブロックできるもの vs ブロックできないもの](#ブロックできるもの-vs-ブロックできないもの)
- [サンドボックス戦略：構文木（SyntaxTree）検査による防御](#サンドボックス戦略構文木syntaxtree検査による防御)
    - [実装アプローチ](#実装アプローチ)
    - [構文木検査の限界](#構文木検査の限界)
- [セマンティックモデル検査（第2レイヤー）](#セマンティックモデル検査第2レイヤー)
    - [セマンティック検査の利点と限界](#セマンティック検査の利点と限界)
- [CSharpScriptEngine 実装スケッチ](#csharpscriptengine-実装スケッチ)
    - [IScriptEngine インターフェース（再掲）](#iscriptengine-インターフェース再掲)
    - [CSharpScriptEngine 実装](#csharpscriptengine-実装)
    - [タイムアウト制御](#タイムアウト制御)
- [比較表：V8/ClearScript vs IronPython vs C# Script (Roslyn)](#比較表v8clearscript-vs-ironpython-vs-c-script-roslyn)
    - [デプロイメント・基本特性](#デプロイメント基本特性)
    - [サンドボックス・セキュリティ](#サンドボックスセキュリティ)
    - [ホストオブジェクト統合](#ホストオブジェクト統合)
    - [スレッド安全性・並行実行](#スレッド安全性並行実行)
- [リスク評価](#リスク評価)
    - [C# Script 固有のリスク](#c-script-固有のリスク)
    - [リスクサマリー](#リスクサマリー)
- [IronPython と C# Script の比較：サンドボックス観点](#ironpython-と-c-script-の比較サンドボックス観点)
    - [IronPython の方が安全な理由](#ironpython-の方が安全な理由)
    - [C# Script の方が優れる点](#c-script-の方が優れる点)
- [代替アプローチ：C# Script をより安全に実行する方法](#代替アプローチc-script-をより安全に実行する方法)
    - [アプローチ 1: プロセス分離](#アプローチ-1-プロセス分離)
    - [アプローチ 2: WebAssembly (WASI) ランタイム内での実行](#アプローチ-2-webassembly-wasi-ランタイム内での実行)
    - [アプローチ 3: ホワイトリスト方式の厳密な構文木分析（現実的アプローチ）](#アプローチ-3-ホワイトリスト方式の厳密な構文木分析現実的アプローチ)
- [プリザンター本体での既存 Roslyn 使用状況](#プリザンター本体での既存-roslyn-使用状況)
- [結論](#結論)
    - [推奨される戦略](#推奨される戦略)
- [関連ドキュメント](#関連ドキュメント)
- [関連ソースコード](#関連ソースコード)
- [関連リンク](#関連リンク)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 調査情報

| 調査日        | リポジトリ | ブランチ | タグ/バージョン    | コミット    | 備考     |
| ------------- | ---------- | -------- | ------------------ | ----------- | -------- |
| 2026年2月23日 | Pleasanter | main     | Pleasanter_1.5.1.0 | `34f162a43` | 初回調査 |

## 調査目的

- Roslyn Scripting API（`Microsoft.CodeAnalysis.CSharp.Scripting`）の基本機能を調査する
- C# Script の実行環境をサンドボックス化し、V8 同等の分離レベルを達成できるか評価する
- ClearScript（V8）・IronPython と比較してメリット・デメリットを明らかにする
- 具体的な `CSharpScriptEngine` の実装スケッチとサンドボックス戦略を示す

---

## Roslyn Scripting API 概要

### NuGet パッケージ

| パッケージ                                | 説明                         | ライセンス |
| ----------------------------------------- | ---------------------------- | ---------- |
| `Microsoft.CodeAnalysis.CSharp.Scripting` | C# スクリプティング API 本体 | MIT        |
| `Microsoft.CodeAnalysis.CSharp`           | C# コンパイラ（依存）        | MIT        |
| `Microsoft.CodeAnalysis.Common`           | 共通基盤（依存）             | MIT        |

```xml
<PackageReference Include="Microsoft.CodeAnalysis.CSharp.Scripting" Version="4.12.0" />
```

### 基本的な使用方法

Roslyn Scripting API は `CSharpScript` クラスを通じてスクリプトの作成・実行を行う。

```csharp
using Microsoft.CodeAnalysis.CSharp.Scripting;
using Microsoft.CodeAnalysis.Scripting;

// 最もシンプルな実行
var result = await CSharpScript.EvaluateAsync<int>("1 + 2");
// result == 3

// ScriptOptions でアセンブリ参照・インポートを制御
var options = ScriptOptions.Default
    .WithReferences(typeof(object).Assembly)
    .WithImports("System");

var result2 = await CSharpScript.EvaluateAsync<string>(
    "string.Join(\", \", new[] { \"a\", \"b\", \"c\" })",
    options);
```

### コンパイルと実行の分離

```csharp
// 1. スクリプトをコンパイル（再利用可能）
var script = CSharpScript.Create<object>(
    code: "model.ClassA = \"hello\"; return model.ClassA;",
    options: options,
    globalsType: typeof(ScriptGlobals));

// 2. コンパイル結果を検証（エラーチェック）
var diagnostics = script.Compile();

// 3. 実行（グローバルオブジェクトを注入）
var globals = new ScriptGlobals { model = myModel, context = myContext };
var state = await script.RunAsync(globals);
var returnValue = state.ReturnValue;
```

### グローバルオブジェクト（ホストオブジェクト注入）

Roslyn Scripting では、**グローバル型**を定義し、そのインスタンスをスクリプト実行時に渡すことで、スクリプトからホストオブジェクトにアクセスさせる。

```csharp
// グローバル型の定義
public class ScriptGlobals
{
    public dynamic model { get; set; }
    public dynamic saved { get; set; }
    public ServerScriptModelContext context { get; set; }
    public ServerScriptModelApiItems items { get; set; }
    public ServerScriptModelDepts depts { get; set; }
    public ServerScriptModelGroups groups { get; set; }
    public ServerScriptModelUsers users { get; set; }
    public dynamic columns { get; set; }
    public ServerScriptModelSiteSettings siteSettings { get; set; }
    public ServerScriptModelView view { get; set; }
    public ServerScriptModelHidden hidden { get; set; }
    public ServerScriptModelResponses responses { get; set; }
    public ServerScriptElements elements { get; set; }
    public ServerScriptModelExtendedSql extendedSql { get; set; }
    public ServerScriptModelNotification notifications { get; set; }
    public ServerScriptModelHttpClient httpClient { get; set; }
    public ServerScriptModelUtilities utilities { get; set; }
    public ServerScriptModelLogs logs { get; set; }
}

// スクリプト内では直接プロパティとしてアクセス可能
// model.ClassA = "test";
// var userId = context.UserId;
// items.Get(123);
```

> **ClearScript との比較**: ClearScript では
> `engine.AddHostObject("name", obj)` で個別にオブジェクトをエンジンに注入する。
> Roslyn では 1 つのグローバル型にまとめて定義し、`RunAsync(globals)` で一括注入する。
> 機能的には同等であるが、Roslyn の方が**型安全**
> （コンパイル時にプロパティの型がチェックされる）。

### パフォーマンス特性

| 項目               | 特性                                                              |
| ------------------ | ----------------------------------------------------------------- |
| 初回コンパイル     | 重い（数百 ms〜）。Roslyn コンパイラ全体が起動する                |
| `Script<T>` 再利用 | コンパイル済みスクリプトの再実行は高速（数 ms〜）                 |
| ウォームアップ     | 最初のスクリプト実行でコンパイラ DLL のロードが発生（1〜2 秒）    |
| メモリ消費         | コンパイルにより IL を生成するため、スクリプトごとにメモリを消費  |
| GC 圧力            | 大量のスクリプト実行時は `AssemblyLoadContext` のアンロードが必要 |

```csharp
// コンパイルキャッシュの実装パターン
private static readonly ConcurrentDictionary<string, Script<object>> _cache = new();

public Script<object> GetOrCompile(string code, ScriptOptions options, Type globalsType)
{
    var key = code.GetHashCode().ToString(); // 本番ではより堅牢なキーを使用
    return _cache.GetOrAdd(key, _ =>
    {
        var script = CSharpScript.Create<object>(code, options, globalsType);
        script.Compile(); // 事前コンパイル
        return script;
    });
}
```

---

## サンドボックス / セキュリティモデル

### 根本的な問題：.NET ランタイム上での実行

> **重要**: Roslyn Scripting API は C# コードを IL にコンパイルし、**ホストプロセスと同じ .NET ランタイム** 上で実行する。V8 のようなプロセス分離は存在しない。

```text
V8 (ClearScript):
  ┌──────────────────────────┐
  │  完全に独立した JS VM     │ ← ネイティブ V8 エンジン
  │  .NET API = 存在しない    │ ← 原理的にアクセス不可能
  │  OS API = 存在しない      │
  └──────────────────────────┘
  ↕ AddHostObject で明示注入した物のみ通過

IronPython (DLR):
  ┌──────────────────────────┐
  │  DLR 上の Python VM       │ ← .NET 上だが言語レイヤーで分離
  │  import clr → .NET 全体   │ ← ブロック可能（4層防御）
  │  OS API = import で到達   │ ← ブロック可能
  └──────────────────────────┘
  ↕ SetVariable + import 制御で制限

C# Script (Roslyn):
  ┌──────────────────────────┐
  │  ホスト .NET ランタイム    │ ← 同一プロセス・同一 CLR
  │  .NET API = 同居している  │ ← 参照されたアセンブリの型は全てアクセス可能
  │  OS API = フレームワーク内 │ ← System.Runtime に含まれる
  └──────────────────────────┘
  ↕ 分離境界が存在しない
```

これが **C# Script のサンドボックスを V8 / IronPython より困難にする根本的な理由** である。

### ScriptOptions による制御機能

Roslyn Scripting API が提供する制御メカニズムを以下に整理する。

#### 1. アセンブリ参照の制御（`WithReferences`）

```csharp
var options = ScriptOptions.Default
    .WithReferences(
        // 最小限のアセンブリのみ参照
        typeof(object).Assembly,           // System.Runtime（必須）
        typeof(ExpandoObject).Assembly,    // System.Linq.Expressions
        typeof(ScriptGlobals).Assembly     // ホストオブジェクト定義アセンブリ
    );
```

**問題点**: `System.Runtime`（旧 `mscorlib`）は C# スクリプト実行に**必須**であるが、このアセンブリには以下の危険な型が含まれる。

| 名前空間                         | 危険な型                            | リスク               |
| -------------------------------- | ----------------------------------- | -------------------- |
| `System.IO`                      | `File`, `Directory`, `StreamReader` | ファイル I/O         |
| `System.Diagnostics`             | `Process`                           | プロセス実行         |
| `System.Net`                     | ネットワーク関連                    | ネットワークアクセス |
| `System.Reflection`              | `Assembly`, `MethodInfo` 等         | リフレクション       |
| `System.Runtime.InteropServices` | `Marshal`, `DllImport`              | ネイティブ呼び出し   |
| `System.Runtime.Loader`          | `AssemblyLoadContext`               | 動的アセンブリロード |
| `System.Threading`               | `Thread`, `Task`                    | スレッド生成         |
| `System.Environment`             | -                                   | 環境変数アクセス     |

> **致命的な問題**: `System.IO.File` も `System.Diagnostics.Process` も
> `System.Runtime` の一部であり、C# スクリプト実行に必須の
> `typeof(object).Assembly` を参照した時点でアクセス可能になる。

#### 2. 名前空間インポートの制御（`WithImports`）

```csharp
var options = ScriptOptions.Default
    .WithImports("System");  // System のみインポート
    // System.IO, System.Diagnostics 等はインポートしない
```

**限界**: `WithImports` は `using` ディレクティブの自動追加を制御するだけであり、**完全修飾名でのアクセスをブロックしない**。

```csharp
// using System.IO; がなくても完全修飾名でアクセス可能
System.IO.File.ReadAllText("C:\\secret.txt");
System.Diagnostics.Process.Start("cmd.exe", "/c dir");
```

#### 3. MetadataReferenceResolver のカスタマイズ

`#r` ディレクティブ（スクリプト内でのアセンブリ参照追加）をブロックできる。

```csharp
/// <summary>
/// すべての #r ディレクティブをブロックする MetadataReferenceResolver
/// </summary>
public class BlockingMetadataReferenceResolver : MetadataReferenceResolver
{
    public override bool Equals(object other) => other is BlockingMetadataReferenceResolver;
    public override int GetHashCode() => typeof(BlockingMetadataReferenceResolver).GetHashCode();

    public override ImmutableArray<PortableExecutableReference> ResolveReference(
        string reference, string baseFilePath, MetadataReferenceProperties properties)
    {
        // すべての #r ディレクティブを拒否
        throw new InvalidOperationException(
            $"Assembly reference '{reference}' is not allowed in sandboxed scripts.");
    }
}

var options = ScriptOptions.Default
    .WithMetadataResolver(new BlockingMetadataReferenceResolver());
```

#### 4. SourceReferenceResolver のカスタマイズ

`#load` ディレクティブ（外部スクリプトファイルの読み込み）をブロックできる。

```csharp
/// <summary>
/// すべての #load ディレクティブをブロックする SourceReferenceResolver
/// </summary>
public class BlockingSourceReferenceResolver : SourceReferenceResolver
{
    public override bool Equals(object other) => other is BlockingSourceReferenceResolver;
    public override int GetHashCode() => typeof(BlockingSourceReferenceResolver).GetHashCode();

    public override string NormalizePath(string path, string baseFilePath) => path;
    public override string ResolveReference(string path, string baseFilePath) => null;

    public override Stream OpenRead(string resolvedPath)
    {
        throw new InvalidOperationException(
            $"Loading external scripts ('{resolvedPath}') is not allowed.");
    }
}
```

### ブロックできるもの vs ブロックできないもの

| 項目                       | ブロック可否         | 方法                                   | 備考                                           |
| -------------------------- | -------------------- | -------------------------------------- | ---------------------------------------------- |
| `#r` ディレクティブ        | **可能**             | `BlockingMetadataReferenceResolver`    | アセンブリ動的追加を完全ブロック               |
| `#load` ディレクティブ     | **可能**             | `BlockingSourceReferenceResolver`      | 外部スクリプト読込を完全ブロック               |
| 自動 `using` インポート    | **可能**             | `WithImports` で制限                   | 自動インポートのみ制御                         |
| 完全修飾名でのアクセス     | **不可能**           | （制御手段なし）                       | `System.IO.File.ReadAllText()` 等              |
| `typeof().Assembly`        | **不可能**           | （制御手段なし）                       | 任意のアセンブリメタデータ取得                 |
| リフレクション             | **不可能**           | （制御手段なし）                       | `Type.GetMethod()`, `Invoke()` 等              |
| `unsafe` コード            | **可能**             | `ScriptOptions.WithAllowUnsafe(false)` | デフォルトで無効                               |
| `dynamic` キーワード       | **不可能**           | （制御手段なし）                       | DLR 経由で型チェック回避に利用可能             |
| P/Invoke（`DllImport`）    | △ 構文解析で検出可能 | SyntaxTree 検査                        | 完全ブロックは静的解析に依存                   |
| 文字列からの型構築         | **不可能**           | （制御手段なし）                       | `Type.GetType("System.IO.File")` 等            |
| `AppDomain` / プロセス分離 | **非対応**           | .NET 8+ で廃止                         | `AssemblyLoadContext` は型アクセスを制限しない |

---

## サンドボックス戦略：構文木（SyntaxTree）検査による防御

ScriptOptions だけではサンドボックスが不十分であるため、**コンパイル後の構文木を検査**してブロックリストに一致するコードを拒否する戦略が必要になる。

### 実装アプローチ

```csharp
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

/// <summary>
/// 危険な API 使用を検出する構文木バリデータ
/// </summary>
public class ScriptSandboxValidator
{
    /// <summary>
    /// ブロックする名前空間プレフィックス
    /// </summary>
    private static readonly string[] BlockedNamespacePrefixes = new[]
    {
        "System.IO",
        "System.Diagnostics",
        "System.Net",
        "System.Reflection",
        "System.Runtime.InteropServices",
        "System.Runtime.Loader",
        "System.Security",
        "System.Threading",
        "System.Runtime.CompilerServices",
        "Microsoft.Win32",
        "System.CodeDom",
    };

    /// <summary>
    /// ブロックする型名
    /// </summary>
    private static readonly string[] BlockedTypeNames = new[]
    {
        "Process",
        "File",
        "Directory",
        "Path",
        "Assembly",
        "Type",
        "Activator",
        "Marshal",
        "Thread",
        "Task",
        "Environment",
        "AppDomain",
        "AssemblyLoadContext",
        "GCHandle",
        "Console",
        "Unsafe",
    };

    /// <summary>
    /// ブロックするキーワード / 構文
    /// </summary>
    private static readonly SyntaxKind[] BlockedSyntaxKinds = new[]
    {
        SyntaxKind.UnsafeStatement,
        SyntaxKind.UnsafeKeyword,
        SyntaxKind.ExternKeyword,
        SyntaxKind.FixedStatement,
        SyntaxKind.PointerType,
        SyntaxKind.PointerIndirectionExpression,
        SyntaxKind.AddressOfExpression,
    };

    public (bool IsValid, List<string> Errors) Validate(SyntaxTree syntaxTree)
    {
        var errors = new List<string>();
        var root = syntaxTree.GetRoot();

        // 1. using ディレクティブの検査
        foreach (var usingDirective in root.DescendantNodes().OfType<UsingDirectiveSyntax>())
        {
            var ns = usingDirective.Name?.ToString();
            if (ns != null && BlockedNamespacePrefixes.Any(b => ns.StartsWith(b)))
            {
                errors.Add($"Blocked using directive: '{ns}'");
            }
        }

        // 2. 完全修飾名アクセスの検査
        foreach (var memberAccess in root.DescendantNodes().OfType<MemberAccessExpressionSyntax>())
        {
            var fullName = memberAccess.ToString();
            if (BlockedNamespacePrefixes.Any(b => fullName.StartsWith(b)))
            {
                errors.Add($"Blocked member access: '{fullName}'");
            }
        }

        // 3. 識別子名の検査（型名の直接使用）
        foreach (var identifier in root.DescendantNodes().OfType<IdentifierNameSyntax>())
        {
            var name = identifier.Identifier.ValueText;
            if (BlockedTypeNames.Contains(name))
            {
                errors.Add($"Blocked type reference: '{name}'");
            }
        }

        // 4. typeof 式の検査
        foreach (var typeofExpr in root.DescendantNodes().OfType<TypeOfExpressionSyntax>())
        {
            var typeName = typeofExpr.Type.ToString();
            if (BlockedNamespacePrefixes.Any(b => typeName.StartsWith(b))
                || BlockedTypeNames.Any(b => typeName.Contains(b)))
            {
                errors.Add($"Blocked typeof expression: typeof({typeName})");
            }
        }

        // 5. 危険な構文の検査
        foreach (var node in root.DescendantNodesAndTokens())
        {
            if (node.IsToken && BlockedSyntaxKinds.Contains(node.Kind()))
            {
                errors.Add($"Blocked syntax: {node.Kind()}");
            }
            if (node.IsNode && BlockedSyntaxKinds.Contains(node.Kind()))
            {
                errors.Add($"Blocked syntax: {node.Kind()}");
            }
        }

        // 6. 文字列リテラル内の危険なパターン検出（リフレクション回避策の検出）
        foreach (var literal in root.DescendantNodes().OfType<LiteralExpressionSyntax>()
            .Where(l => l.Kind() == SyntaxKind.StringLiteralExpression))
        {
            var text = literal.Token.ValueText;
            if (text.Contains("System.IO") || text.Contains("System.Diagnostics")
                || text.Contains("Process") || text.Contains("System.Net"))
            {
                errors.Add($"Suspicious string literal: '{text}'");
            }
        }

        return (errors.Count == 0, errors);
    }
}
```

### 構文木検査の限界

構文木検査はあくまで**静的解析**であり、以下のバイパス手法には対応が困難である。

#### バイパス手法 1: 文字列結合による型名構築

```csharp
// 構文木検査では "System.IO.File" という文字列が直接現れない
var typeName = "System" + ".IO" + ".File";
var type = Type.GetType(typeName);
var method = type.GetMethod("ReadAllText");
method.Invoke(null, new object[] { "C:\\secret.txt" });
```

#### バイパス手法 2: リフレクション経由

```csharp
// typeof(object) は必ず許可される
var asm = typeof(object).Assembly;
// アセンブリ内の全型を列挙してターゲットを見つける
var fileType = asm.GetTypes().First(t => t.FullName == "System.IO.File");
```

#### バイパス手法 3: dynamic を利用した間接呼び出し

```csharp
// dynamic 経由で型チェックを回避
dynamic obj = Activator.CreateInstance("System.Runtime", "System.Diagnostics.ProcessStartInfo")
    .Unwrap();
```

#### バイパス手法 4: 補間文字列 / char 配列

```csharp
// 文字列リテラル検査を回避
var t = new string(new[] { 'S','y','s','t','e','m','.','I','O','.','F','i','l','e' });
```

> **結論**: 構文木検査は**第一防御レイヤー**としては有効だが、**それだけでは不十分**である。高度な攻撃者による回避が可能であり、V8 の「原理的保証」とは根本的に異なる。

---

## セマンティックモデル検査（第2レイヤー）

構文木検査のバイパスに対処するために、**セマンティックモデル**（コンパイラが解決した型情報）を検査する方法がある。

```csharp
/// <summary>
/// セマンティック解析による危険な API 使用の検出
/// </summary>
public class SemanticSandboxValidator
{
    private static readonly HashSet<string> BlockedNamespaces = new(StringComparer.Ordinal)
    {
        "System.IO",
        "System.Diagnostics",
        "System.Net",
        "System.Net.Http",
        "System.Net.Sockets",
        "System.Reflection",
        "System.Runtime.InteropServices",
        "System.Runtime.Loader",
        "System.Security.Cryptography",
        "System.Threading",
        "Microsoft.Win32",
    };

    private static readonly HashSet<string> BlockedTypes = new(StringComparer.Ordinal)
    {
        "System.Environment",
        "System.Console",
        "System.Activator",
        "System.AppDomain",
        "System.GC",
        "System.Type",             // typeof() → .GetMethod() を防ぐ
        "System.Reflection.Assembly",
    };

    public (bool IsValid, List<string> Errors) Validate(
        Compilation compilation, SyntaxTree syntaxTree)
    {
        var errors = new List<string>();
        var semanticModel = compilation.GetSemanticModel(syntaxTree);
        var root = syntaxTree.GetRoot();

        foreach (var node in root.DescendantNodes())
        {
            var symbolInfo = semanticModel.GetSymbolInfo(node);
            var symbol = symbolInfo.Symbol ?? symbolInfo.CandidateSymbols.FirstOrDefault();
            if (symbol == null) continue;

            var containingNamespace = symbol.ContainingNamespace?.ToDisplayString();
            var containingType = symbol.ContainingType?.ToDisplayString();

            // 名前空間チェック
            if (containingNamespace != null
                && BlockedNamespaces.Any(ns => containingNamespace.StartsWith(ns)))
            {
                errors.Add($"Blocked API: {symbol.ToDisplayString()} (namespace: {containingNamespace})");
            }

            // 型チェック
            if (containingType != null && BlockedTypes.Contains(containingType))
            {
                errors.Add($"Blocked type access: {symbol.ToDisplayString()} (type: {containingType})");
            }

            // `typeof` の結果に対するメソッド呼び出し検出
            if (node is InvocationExpressionSyntax invocation)
            {
                var methodSymbol = semanticModel.GetSymbolInfo(invocation).Symbol as IMethodSymbol;
                if (methodSymbol?.ContainingType?.ToDisplayString() == "System.Type")
                {
                    errors.Add($"Blocked reflection call: {methodSymbol.ToDisplayString()}");
                }
            }
        }

        return (errors.Count == 0, errors);
    }
}
```

### セマンティック検査の利点と限界

| 観点 | 説明                                                                                   |
| ---- | -------------------------------------------------------------------------------------- |
| 利点 | コンパイラが解決した**実際の型情報**に基づいて検査するため、完全修飾名の省略を検出可能 |
| 利点 | `using` エイリアスや `var` 推論の先も追跡可能                                          |
| 限界 | `dynamic` 型の呼び出しはコンパイル時に解決されないため検出不可能                       |
| 限界 | 文字列から `Type.GetType()` で動的に取得した型は追跡不可能                             |
| 限界 | 実行時に動的生成されるコード（`Expression<T>` コンパイル等）は検出不可能               |

> **`System.Type` のブロックについての注意**:
> `System.Type` をブロックリストに入れると、スクリプト内で `typeof()` が使えなくなる。
> これは過剰制限になる可能性がある。
> しかし `typeof().GetMethod()` というリフレクション呼び出しパターンを防ぐには必要である。
> **どの程度制限するかはトレードオフ**になる。

---

## CSharpScriptEngine 実装スケッチ

既存の `ScriptEngine`（V8 ラッパー）および [007-ServerScript-Python対応.md](007-ServerScript-Python対応.md) で提案されている `IScriptEngine` インターフェースに準拠した実装スケッチを示す。

### IScriptEngine インターフェース（再掲）

```csharp
public interface IScriptEngine : IDisposable
{
    void AddHostObject(string name, object target);
    void AddHostType(Type type);
    void Execute(string code, bool debug);
    object Evaluate(string code);
    Func<bool> ContinuationCallback { set; }
}
```

### CSharpScriptEngine 実装

```csharp
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Scripting;
using Microsoft.CodeAnalysis.Scripting;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Dynamic;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;

namespace Implem.Pleasanter.Libraries.ServerScripts
{
    /// <summary>
    /// C# Script エンジン（Roslyn Scripting API ベース）
    /// </summary>
    public class CSharpScriptEngine : IScriptEngine
    {
        private readonly Dictionary<string, object> _hostObjects = new();
        private readonly List<Type> _hostTypes = new();
        private readonly ScriptSandboxValidator _syntaxValidator = new();
        private readonly CancellationTokenSource _cts = new();
        private Func<bool> _continuationCallback;

        /// <summary>
        /// コンパイル済みスクリプトのキャッシュ
        /// </summary>
        private static readonly ConcurrentDictionary<int, Script<object>> _compilationCache
            = new();

        public Func<bool> ContinuationCallback
        {
            set => _continuationCallback = value;
        }

        public void AddHostObject(string name, object target)
        {
            _hostObjects[name] = target;
        }

        public void AddHostType(Type type)
        {
            _hostTypes.Add(type);
        }

        public void Execute(string code, bool debug)
        {
            ExecuteAsync(code).GetAwaiter().GetResult();
        }

        public object Evaluate(string code)
        {
            return ExecuteAsync(code).GetAwaiter().GetResult();
        }

        private async Task<object> ExecuteAsync(string code)
        {
            // 1. ScriptOptions の構築（最小限のアセンブリ参照）
            var options = CreateSandboxedOptions();

            // 2. スクリプトのコンパイル
            var script = CSharpScript.Create<object>(
                code: code,
                options: options,
                globalsType: typeof(CSharpScriptGlobals));

            var diagnostics = script.Compile();
            CheckCompilationErrors(diagnostics);

            // 3. 構文木検査（サンドボックスバリデーション）
            var syntaxTree = script.GetCompilation().SyntaxTrees.Last();
            var (isValid, errors) = _syntaxValidator.Validate(syntaxTree);
            if (!isValid)
            {
                throw new ScriptSecurityException(
                    $"Script contains blocked operations: {string.Join("; ", errors)}");
            }

            // 4. セマンティック検査
            var semanticValidator = new SemanticSandboxValidator();
            var (semValid, semErrors) = semanticValidator.Validate(
                script.GetCompilation(), syntaxTree);
            if (!semValid)
            {
                throw new ScriptSecurityException(
                    $"Script contains blocked API usage: {string.Join("; ", semErrors)}");
            }

            // 5. グローバルオブジェクトの構築
            var globals = BuildGlobals();

            // 6. タイムアウト付きで実行
            using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(_cts.Token);
            var state = await script.RunAsync(
                globals: globals,
                cancellationToken: linkedCts.Token);

            return state.ReturnValue;
        }

        private ScriptOptions CreateSandboxedOptions()
        {
            var references = new List<MetadataReference>
            {
                MetadataReference.CreateFromFile(typeof(object).Assembly.Location),
                MetadataReference.CreateFromFile(typeof(ExpandoObject).Assembly.Location),
                MetadataReference.CreateFromFile(typeof(CSharpScriptGlobals).Assembly.Location),
            };

            // ホスト型のアセンブリも参照に追加
            foreach (var type in _hostTypes)
            {
                references.Add(MetadataReference.CreateFromFile(type.Assembly.Location));
            }

            return ScriptOptions.Default
                .WithReferences(references)
                .WithImports("System")                   // 最小限のインポートのみ
                .WithAllowUnsafe(false)                  // unsafe コード禁止
                .WithMetadataResolver(new BlockingMetadataReferenceResolver())
                .WithSourceResolver(new BlockingSourceReferenceResolver());
        }

        private CSharpScriptGlobals BuildGlobals()
        {
            var globals = new CSharpScriptGlobals();
            foreach (var (name, value) in _hostObjects)
            {
                typeof(CSharpScriptGlobals)
                    .GetProperty(name)?
                    .SetValue(globals, value);
            }
            return globals;
        }

        private void CheckCompilationErrors(
            IEnumerable<Diagnostic> diagnostics)
        {
            var errors = diagnostics
                .Where(d => d.Severity == DiagnosticSeverity.Error)
                .ToList();
            if (errors.Any())
            {
                throw new CompilationErrorException(
                    "Script compilation failed",
                    errors.ToImmutableArray());
            }
        }

        public void Dispose()
        {
            _cts?.Cancel();
            _cts?.Dispose();
        }
    }

    /// <summary>
    /// スクリプトに公開するグローバルオブジェクト群
    /// </summary>
    public class CSharpScriptGlobals
    {
        public dynamic model { get; set; }
        public dynamic saved { get; set; }
        public dynamic grid { get; set; }
        public dynamic columns { get; set; }
        public ServerScriptModelContext context { get; set; }
        public ServerScriptModelApiItems items { get; set; }
        public ServerScriptModelDepts depts { get; set; }
        public ServerScriptModelGroups groups { get; set; }
        public ServerScriptModelUsers users { get; set; }
        public ServerScriptModelSiteSettings siteSettings { get; set; }
        public ServerScriptModelView view { get; set; }
        public ServerScriptModelHidden hidden { get; set; }
        public ServerScriptModelResponses responses { get; set; }
        public ServerScriptElements elements { get; set; }
        public ServerScriptModelExtendedSql extendedSql { get; set; }
        public ServerScriptModelNotification notifications { get; set; }
        public ServerScriptModelHttpClient httpClient { get; set; }
        public ServerScriptModelUtilities utilities { get; set; }
        public ServerScriptModelLogs logs { get; set; }
    }

    public class ScriptSecurityException : Exception
    {
        public ScriptSecurityException(string message) : base(message) { }
    }
}
```

### タイムアウト制御

```csharp
/// <summary>
/// タイムアウト付きスクリプト実行
/// </summary>
public async Task ExecuteWithTimeout(string code, int timeoutMs)
{
    using var cts = new CancellationTokenSource(timeoutMs);
    try
    {
        var options = CreateSandboxedOptions();
        var script = CSharpScript.Create<object>(code, options, typeof(CSharpScriptGlobals));
        var globals = BuildGlobals();
        await script.RunAsync(globals, cancellationToken: cts.Token);
    }
    catch (OperationCanceledException)
    {
        throw new TimeoutException(
            $"Script execution timed out after {timeoutMs}ms");
    }
}
```

> **ClearScript との比較**: ClearScript では `ContinuationCallback` による
> タイムアウト制御を行う（スクリプトエンジンの実行ループに割り込む）。
> Roslyn では `CancellationToken` を使用するが、
> **CPU バウンドの無限ループ（`while(true){}`）はキャンセルトークンで中断できない**
> 場合がある。これは ClearScript の `ContinuationCallback` が
> V8 の内部ループに直接介入するのに対し、
> `CancellationToken` は await ポイントでのみチェックされるためである。

---

## 比較表：V8/ClearScript vs IronPython vs C# Script (Roslyn)

### デプロイメント・基本特性

| 項目                   | ClearScript (V8)                 | IronPython 3               | C# Script (Roslyn)                        |
| ---------------------- | -------------------------------- | -------------------------- | ----------------------------------------- |
| NuGet パッケージ       | `Microsoft.ClearScript.Complete` | `IronPython` (3.4.x)       | `Microsoft.CodeAnalysis.CSharp.Scripting` |
| ネイティブ依存         | あり（V8 ネイティブバイナリ）    | なし（Pure .NET）          | なし（Pure .NET）                         |
| ライセンス             | MIT                              | Apache 2.0                 | MIT                                       |
| .NET 10 対応           | Yes                              | Yes                        | Yes                                       |
| Docker イメージ影響    | V8 バイナリでサイズ増加          | 影響小                     | 影響小                                    |
| スクリプト言語         | JavaScript                       | Python                     | C#                                        |
| 言語バージョン         | ECMAScript 2023                  | Python 3.4 互換            | C# 12+                                    |
| 初回起動コスト         | 中（V8 エンジン初期化）          | 中（DLR 初期化）           | 高（Roslyn コンパイラ起動）               |
| 定常実行パフォーマンス | 高速（JIT済みネイティブ実行）    | 中（DLR 動的ディスパッチ） | 高速（IL → JIT）                          |
| コンパイルキャッシュ   | V8 内部キャッシュ                | DLR CallSite キャッシュ    | `Script<T>` 再利用                        |

### サンドボックス・セキュリティ

| 項目                     | ClearScript (V8)         | IronPython 3                  | C# Script (Roslyn)                          |
| ------------------------ | ------------------------ | ----------------------------- | ------------------------------------------- |
| **サンドボックスモデル** | **原理的保証**           | **実装的保証**（4層防御）     | **実装的保証**（構文木+セマンティック検査） |
| OS API の存在            | なし（エンジン内に皆無） | あり（import で到達）         | あり（同一ランタイムに同居）                |
| ファイル I/O ブロック    | 不要（API がない）       | import / PAL / clr で多層防御 | 構文木検査 + セマンティック検査             |
| プロセス実行ブロック     | 不要（API がない）       | import / clr ブロック         | 構文木検査（バイパスリスクあり）            |
| リフレクション防止       | 不要                     | clr import ブロック           | 完全防止は困難                              |
| `typeof().Assembly`      | 不可能                   | 相当する操作を clr で制限     | 防止不可能                                  |
| 文字列→型構築のブロック  | 不要                     | `__import__` カスタム + clr   | `Type.GetType(string)` 防止困難             |
| `dynamic` 経由の回避     | 不要                     | `.NET interop` ブロックで対応 | 制御困難                                    |
| 防御の確実性             | ★★★★★                    | ★★★☆☆                         | ★★☆☆☆                                       |
| エスケープ（脱出）リスク | なし                     | 中（**subclasses** 等）       | **高**（リフレクション、dynamic）           |

### ホストオブジェクト統合

| 項目                   | ClearScript (V8)         | IronPython 3                | C# Script (Roslyn)                     |
| ---------------------- | ------------------------ | --------------------------- | -------------------------------------- |
| オブジェクト注入方式   | `AddHostObject()`        | `scope.SetVariable()`       | `RunAsync(globals)` 型安全             |
| ExpandoObject 対応     | 自動的にJSオブジェクト化 | 辞書的アクセス              | `dynamic` で自然にアクセス             |
| 型安全性               | なし（動的型付け）       | なし（動的型付け）          | **あり**（コンパイル時型チェック可能） |
| IDE サポート           | なし                     | 限定的                      | **充実**（Roslyn ベース）              |
| ホスト型の直接参照     | `AddHostType()` で明示的 | `import clr` で全型アクセス | **参照アセンブリ内の全型**             |
| `JsonConvert` 等の利用 | `AddHostType()` で提供   | import で自然にアクセス     | using / 参照追加で自然                 |

### スレッド安全性・並行実行

| 項目             | ClearScript (V8)               | IronPython 3                    | C# Script (Roslyn)                                 |
| ---------------- | ------------------------------ | ------------------------------- | -------------------------------------------------- |
| 並行実行         | V8 インスタンスごとに独立      | ScriptEngine は非スレッドセーフ | `Script<T>.RunAsync` はスレッドセーフ              |
| エンジンの再利用 | 使い捨て（Dispose 必須）       | 使い捨て推奨                    | コンパイル結果のみ再利用可能                       |
| タイムアウト制御 | `ContinuationCallback`（確実） | `Thread.Abort` 代替必要         | `CancellationToken`（CPUループに効かない場合あり） |

---

## リスク評価

### C# Script 固有のリスク

#### リスク 1: リフレクションによるサンドボックス脱出（深刻度: 高）

```csharp
// typeof(object) は常にアクセス可能
// そこからアセンブリ内の全型にアクセス可能
var asm = typeof(object).Assembly;
var types = asm.GetTypes();
var fileType = types.First(t => t.FullName == "System.IO.File");
var readMethod = fileType.GetMethod("ReadAllText", new[] { typeof(string) });
var content = readMethod.Invoke(null, new object[] { "/etc/passwd" });
```

**対策**: `System.Type` のメソッド呼び出しをセマンティック検査で検出できるが、`dynamic` と組み合わせると回避される可能性がある。

#### リスク 2: `dynamic` による型チェック回避（深刻度: 高）

```csharp
// dynamic を使うとコンパイル時の型チェックが完全にスキップされる
dynamic x = typeof(object).Assembly;
// セマンティック解析では x に対する操作が追跡できない
```

**対策**: `dynamic` キーワードの使用自体を構文木検査で禁止するアプローチが考えられるが、`ExpandoObject`（ホストオブジェクトで使用）も `dynamic` でアクセスするため、**完全禁止はできない**。

#### リスク 3: CPU バウンドの無限ループ（深刻度: 中）

```csharp
// CancellationToken は await ポイントでしかチェックされない
while (true) { var x = 1 + 1; }  // キャンセル不可能
```

**対策**: スクリプト実行を別スレッドで行い、タイムアウト後にスレッドを強制終了する。ただし .NET では `Thread.Abort()` が廃止されており、確実な中断手段がない。

#### リスク 4: メモリ枯渇攻撃（深刻度: 中）

```csharp
var list = new System.Collections.Generic.List<byte[]>();
while (true) { list.Add(new byte[1024 * 1024]); }  // 1MB ずつ確保
```

**対策**: プロセスレベルのメモリ制限が必要。.NET ランタイム単体では制限できない。

#### リスク 5: `Expression<T>` による動的コード生成（深刻度: 中）

```csharp
// Linq Expression を使って実行時にコードを生成・実行
var param = System.Linq.Expressions.Expression.Parameter(typeof(string));
// ...コンパイル不要でデリゲートを生成可能
```

**対策**: `System.Linq.Expressions` 名前空間をブロック対象に追加。

### リスクサマリー

| リスク                         | 深刻度 | 対策の実現性              | 残存リスク               |
| ------------------------------ | ------ | ------------------------- | ------------------------ |
| リフレクションによる脱出       | **高** | △ 部分的に可能            | `dynamic` 経由で回避可能 |
| `dynamic` による型チェック回避 | **高** | 完全対策不可              | ExpandoObject で必須     |
| CPU 無限ループ                 | 中     | △ スレッド強制終了        | `Thread.Abort` 廃止      |
| メモリ枯渇                     | 中     | △ OS レベル制限           | プロセス内制限は困難     |
| Expression Tree 動的生成       | 中     | ○ 名前空間ブロック        | 構文木検査で検出可能     |
| P/Invoke / extern              | 中     | ○ 構文木検査              | 検出可能                 |
| `#r` / `#load`                 | 低     | ◎ Resolver で完全ブロック | -                        |

---

## IronPython と C# Script の比較：サンドボックス観点

### IronPython の方が安全な理由

| 観点                 | IronPython                     | C# Script                      |
| -------------------- | ------------------------------ | ------------------------------ |
| .NET APIアクセス経路 | `import clr` が唯一のゲート    | 全型が暗黙的にアクセス可能     |
| ゲートの封鎖         | `clr` インポートブロックで封鎖 | 封鎖手段なし（同一ランタイム） |
| リフレクション       | `clr` ブロックで到達困難       | `typeof(object)` から到達可能  |
| 言語レイヤー分離     | Python → DLR → .NET（間接的）  | C# → IL → .NET（直接的）       |
| 防御のかかり具合     | import でチョークポイントあり  | チョークポイントなし           |

IronPython は「Python 言語 → .NET ランタイム」の間に
**DLR（Dynamic Language Runtime）という仲介レイヤー** があり、
`import clr` というチョークポイントを封鎖すれば .NET API への到達が遮断される。

一方、C# Script は **C# コード自体が .NET のネイティブ言語** であるため、チョークポイントが存在しない。`typeof(object)` すら .NET リフレクションの起点となる。

### C# Script の方が優れる点

| 観点                        | C# Script                    | IronPython                           |
| --------------------------- | ---------------------------- | ------------------------------------ |
| 型安全性                    | コンパイル時型チェック       | 動的型付けのみ                       |
| IDE サポート                | Roslyn ベースの IntelliSense | 限定的                               |
| ホストアプリとの親和性      | ホストアプリと同一言語（C#） | 言語インピーダンスミスマッチ         |
| エラーメッセージの品質      | コンパイルエラーが詳細       | 実行時のエラーが Python 式           |
| パフォーマンス              | JIT コンパイル後は高速       | DLR 動的ディスパッチのオーバーヘッド |
| 学習コスト（C# 開発者向け） | ゼロ（同一言語）             | Python 学習が必要                    |

---

## 代替アプローチ：C# Script をより安全に実行する方法

### アプローチ 1: プロセス分離

```text
┌─────────────────┐       IPC        ┌───────────────────────┐
│ メインプロセス    │ ←──────────────→ │ サンドボックスプロセス  │
│ (Pleasanter)     │   stdin/stdout   │ (C# Script 実行)       │
│                  │   or named pipe  │ - 制限付きユーザー      │
│                  │                  │ - ファイルシステム制限   │
│                  │                  │ - ネットワーク制限       │
└─────────────────┘                  └───────────────────────┘
```

**メリット**: OS レベルの分離により、リフレクション等のバイパスが無意味になる。
**デメリット**: プロセス間通信のオーバーヘッド、ホストオブジェクトのシリアライズ/デシリアライズ、実装の複雑性が大幅に増加。ServerScript の「model.ClassA = 'test'」のような軽量な値操作に対してはオーバーキル。

### アプローチ 2: WebAssembly (WASI) ランタイム内での実行

```text
┌─────────────────┐       ┌──────────────────────────┐
│ メインプロセス    │       │  WASM サンドボックス       │
│ (Pleasanter)     │ ←───→ │  - .NET → WASM コンパイル  │
│                  │       │  - メモリ制限               │
│                  │       │  - ファイルI/O なし          │
│                  │       │  - ネットワーク なし         │
└─────────────────┘       └──────────────────────────┘
```

**メリット**: WASM の sandboxing は V8 同等レベル。
**デメリット**: .NET → WASM のコンパイルパイプラインが複雑。ホストオブジェクトの橋渡しが困難。現時点では実用段階にない。

### アプローチ 3: ホワイトリスト方式の厳密な構文木分析（現実的アプローチ）

ブロックリストではなく、**許可する操作のみを列挙するホワイトリスト方式**に切り替える。

```csharp
/// <summary>
/// ホワイトリスト方式の厳密なバリデータ
/// スクリプトで許可する操作を明示的に列挙し、
/// それ以外のすべてをブロックする。
/// </summary>
public class WhitelistSandboxValidator
{
    /// <summary>
    /// 許可する型（完全修飾名）
    /// </summary>
    private static readonly HashSet<string> AllowedTypes = new()
    {
        // プリミティブ型
        "System.Object",
        "System.String",
        "System.Boolean",
        "System.Byte",
        "System.Int16",
        "System.Int32",
        "System.Int64",
        "System.Single",
        "System.Double",
        "System.Decimal",
        "System.DateTime",
        "System.TimeSpan",
        "System.Guid",
        "System.Nullable<T>",

        // コレクション
        "System.Collections.Generic.List<T>",
        "System.Collections.Generic.Dictionary<TKey,TValue>",
        "System.Collections.Generic.IEnumerable<T>",
        "System.Linq.Enumerable",

        // 文字列操作
        "System.Text.StringBuilder",
        "System.Text.RegularExpressions.Regex",

        // 数学
        "System.Math",

        // JSON
        "Newtonsoft.Json.JsonConvert",

        // ExpandoObject（ホストオブジェクト）
        "System.Dynamic.ExpandoObject",
    };

    /// <summary>
    /// 許可する名前空間
    /// </summary>
    private static readonly HashSet<string> AllowedNamespaces = new()
    {
        "System",
        "System.Collections.Generic",
        "System.Linq",
        "System.Text",
        "System.Text.RegularExpressions",
        "System.Dynamic",
        "Newtonsoft.Json",
    };

    public (bool IsValid, List<string> Errors) Validate(
        Compilation compilation, SyntaxTree syntaxTree)
    {
        var errors = new List<string>();
        var semanticModel = compilation.GetSemanticModel(syntaxTree);
        var root = syntaxTree.GetRoot();

        foreach (var node in root.DescendantNodes())
        {
            var symbolInfo = semanticModel.GetSymbolInfo(node);
            var symbol = symbolInfo.Symbol;
            if (symbol == null) continue;

            // ホストオブジェクトのメンバーアクセスは常に許可
            if (IsHostObjectAccess(symbol)) continue;

            var containingType = symbol.ContainingType?.ToDisplayString();
            var containingNamespace = symbol.ContainingNamespace?.ToDisplayString();

            if (containingType != null && !AllowedTypes.Contains(containingType))
            {
                // 許可リストにない型の使用を検出
                errors.Add($"Type not allowed: {containingType} (used: {symbol.ToDisplayString()})");
            }
        }

        return (errors.Count == 0, errors);
    }

    private bool IsHostObjectAccess(ISymbol symbol)
    {
        // CSharpScriptGlobals のプロパティ / ホストオブジェクトの型か判定
        var containingAssembly = symbol.ContainingAssembly?.Name;
        return containingAssembly == "Implem.Pleasanter";
    }
}
```

**ホワイトリスト方式の課題**:

| 課題                       | 説明                                                            |
| -------------------------- | --------------------------------------------------------------- |
| `dynamic` の追跡不可能     | ExpandoObject を `dynamic` でアクセスする場合、型が解決されない |
| 過剰制限のリスク           | 許可リストが厳しすぎるとスクリプトの表現力が大幅に低下する      |
| メンテナンスコスト         | 新しい型を許可するたびにホワイトリストの更新が必要              |
| ジェネリック型のマッチング | `List<T>` のようなオープンジェネリクスの判定が複雑              |

---

## プリザンター本体での既存 Roslyn 使用状況

`Implem.Pleasanter.csproj` を調査した結果、**`Microsoft.CodeAnalysis` パッケージへの直接参照は存在しない**。

```xml
<!-- 現在の ClearScript 参照 -->
<PackageReference Include="Microsoft.ClearScript.Complete" Version="7.5.0" />

<!-- Microsoft.CodeAnalysis 系のパッケージは未参照 -->
```

ただし、Roslyn のアナライザ DLL は NuGet パッケージの依存関係として間接的に使用されている（`Microsoft.Extensions.Logging.Generators` 等）。これはビルド時のコード生成用であり、実行時には使用されない。

---

## 結論

| 項目                        | 結論                                                                                                                                                  |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Roslyn Scripting API の機能 | ホストオブジェクト注入（globals 型）、コンパイルキャッシュ、`.NET 10` 完全互換。機能面での不足なし                                                    |
| サンドボックスの実現可能性  | **V8 同等の分離レベルは達成不可能**。C# は .NET のネイティブ言語であり、参照アセンブリ内の全型に暗黙的にアクセスできる                                |
| サンドボックスの防御レベル  | 構文木検査 + セマンティック検査で「実装的保証」は可能だが、`dynamic` + リフレクションによるバイパスリスクが**高い**                                   |
| IronPython との比較         | IronPython の方が安全。`import clr` というチョークポイントがあるのに対し、C# Script にはチョークポイントが存在しない                                  |
| V8 (ClearScript) との比較   | V8 が圧倒的に安全。V8 は OS API が原理的に存在しないのに対し、C# Script は .NET ランタイムの全機能と同居する                                          |
| 型安全性・開発者体験        | C# Script が最も優れる（コンパイル時型チェック、IntelliSense、ホストアプリと同一言語）                                                                |
| **推奨度**                  | **ServerScript 用途には推奨しない**。セキュリティ要件（値操作のみ許可）を確実に満たせない。信頼できるスクリプトのみを実行する限定的なシナリオでは有用 |
| 代替案                      | 管理者のみが編集可能な「信頼済みスクリプト」モードとして提供する場合は検討の余地あり                                                                  |
| プロセス分離アプローチ      | OS レベルの分離を使えば安全だが、ホストオブジェクト連携のオーバーヘッドが大きく、ServerScript の軽量な値操作には不向き                                |

### 推奨される戦略

```text
スクリプト言語の安全性ランキング（ServerScript 用途）:

1. ClearScript (V8/JS)    ★★★★★  原理的保証   ← 現行のまま継続
2. IronPython 3            ★★★☆☆  実装的保証   ← 追加オプションとして有望
3. C# Script (Roslyn)      ★★☆☆☆  バイパス可能 ← 非推奨（一般ユーザー向け）
```

C# Script を導入する場合の**唯一の安全なシナリオ**は、以下のような制限を設けることである。

| 条件                        | 説明                                                         |
| --------------------------- | ------------------------------------------------------------ |
| スクリプト作成者を限定      | テナント管理者またはシステム管理者のみがスクリプトを作成可能 |
| コードレビュー必須          | 本番環境へのスクリプトデプロイ前にレビューを義務化           |
| 構文木 + セマンティック検査 | 既知の危険パターンを検出するバリデーション層を設置           |
| 監査ログ                    | スクリプトの作成・変更・実行をすべて記録                     |
| プロセス分離（オプション）  | 最高セキュリティが必要な場合はサブプロセスでの実行を検討     |

> **総括**: C# Script は「型安全性」「開発者体験」「ホストアプリとの親和性」では
> 最も優れるが、**サンドボックスの確実性ではV8・IronPython の両方に劣る**。
> ServerScript の設計原則である「値操作のみ許可」を **原理的に** 保証できないため、
> 一般ユーザーが自由にスクリプトを記述できる環境への導入は推奨しない。

---

## 関連ドキュメント

- [ServerScript 実装](006-ServerScript実装.md) — 現行 ClearScript アーキテクチャの詳細
- [ServerScript Python 対応の実現可能性調査](007-ServerScript-Python対応.md) — IronPython エンジン選定・実装方針
- [IronPython 3 サンドボックス実装ガイド](008-IronPythonサンドボックス.md) — IronPython のサンドボックス多層防御

## 関連ソースコード

| ファイル                                                                               | 説明                                         |
| -------------------------------------------------------------------------------------- | -------------------------------------------- |
| `Implem.Pleasanter/Implem.Pleasanter/Libraries/ServerScripts/ScriptEngine.cs`          | 既存 V8 エンジンラッパー                     |
| `Implem.Pleasanter/Implem.Pleasanter/Libraries/ServerScripts/ServerScriptUtilities.cs` | メイン実行ロジック（ホストオブジェクト登録） |
| `Implem.Pleasanter/Implem.Pleasanter/Libraries/ServerScripts/ServerScriptModel.cs`     | ServerScript グローバルオブジェクト定義      |
| `Implem.Pleasanter/Implem.Pleasanter/Implem.Pleasanter.csproj`                         | NuGet パッケージ参照                         |

## 関連リンク

| リンク                                                                                                                    | 内容                                          |
| ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| [Roslyn Scripting API](https://github.com/dotnet/roslyn/blob/main/docs/wiki/Scripting-API-Samples.md)                     | Roslyn Scripting API 公式サンプル             |
| [Microsoft.CodeAnalysis.CSharp.Scripting (NuGet)](https://www.nuget.org/packages/Microsoft.CodeAnalysis.CSharp.Scripting) | NuGet パッケージ                              |
| [Roslyn GitHub](https://github.com/dotnet/roslyn)                                                                         | Roslyn コンパイラプラットフォームソースコード |
| [.NET CAS 廃止](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5362)                       | Code Access Security 非推奨情報               |
