#!/usr/bin/env node

/**
 * docs/ 配下の設計書を GitHub Wiki に同期するスクリプト
 *
 * このスクリプトはGitHub Actions環境でのみ実行可能です。
 * ローカル環境からの実行は許可されていません。
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawnSync } = require('child_process');

// 環境変数の取得
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const GITHUB_REPO = process.env.GITHUB_REPO || process.env.GITHUB_REPOSITORY;
const GITHUB_ACTIONS = process.env.GITHUB_ACTIONS === 'true';

// GitHub Actions環境でのみ実行を許可
if (!GITHUB_ACTIONS) {
  console.error('❌ このスクリプトはGitHub Actions環境でのみ実行できます');
  console.error('   ローカル環境からの実行は許可されていません');
  console.error('   Wiki同期はGitHub Actionsから自動的に実行されます');
  process.exit(1);
}

if (!GITHUB_TOKEN) {
  console.error('❌ GITHUB_TOKEN 環境変数が設定されていません');
  process.exit(1);
}

if (!GITHUB_REPO) {
  console.error('❌ GITHUB_REPO 環境変数が設定されていません');
  console.error('   例: GITHUB_REPO=owner/repo');
  process.exit(1);
}

const [owner, repo] = GITHUB_REPO.split('/');
if (!owner || !repo) {
  console.error('❌ GITHUB_REPO の形式が正しくありません');
  console.error('   例: GITHUB_REPO=owner/repo');
  process.exit(1);
}

// ここは実際の構成に合わせて変更してください
const DOCS_DIR = path.join(process.cwd(), 'docs', 'research');
const WIKI_TEMPLATE_DIR = path.join(process.cwd(), 'docs', 'wiki');

// Wiki にのみ残すべきページ（削除対象外）
// [private] で始まるページは自動的に保護されます
const PROTECTED_WIKI_PAGES = [];

/**
 * カテゴリディレクトリ名から表示用ラベルを取得
 * 例: "01-認証・権限" → "認証・権限"
 */
function getCategoryLabel(dirName) {
  return dirName.replace(/^\d+-/, '');
}

/**
 * カテゴリディレクトリ名から先頭の連番を取得（整数）
 * 例: "01-認証・権限" → 1
 */
function getCategoryNumber(dirName) {
  const match = dirName.match(/^(\d+)/);
  return match ? parseInt(match[1], 10) : 0;
}

/**
 * docs/research/ 配下の Markdown ファイルを再帰的に取得
 */
function getMarkdownFiles(dir, basePath = '') {
  const files = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    const relativePath = path.join(basePath, entry.name);

    if (entry.isDirectory()) {
      // サブディレクトリも含める
      files.push(...getMarkdownFiles(fullPath, relativePath));
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      files.push({
        filePath: fullPath,
        relativePath: relativePath,
        wikiTitle: getWikiTitle(relativePath),
      });
    }
  }

  return files;
}

/**
 * ファイルパスから Wiki ページタイトルを生成
 */
function getWikiTitle(relativePath) {
  // ファイル名から拡張子を除去
  const nameWithoutExt = relativePath.replace(/\.md$/, '');

  // パス区切りをハイフンに変換（必要に応じて調整）
  // 例: "01_要件定義書" -> "01_要件定義書"
  // 例: "01_要件定義書/顧客要件" -> "01_要件定義書-顧客要件"
  return nameWithoutExt.replace(/[\\/]/g, '-');
}

/**
 * ファイル名から表示用ラベルを取得
 * 例: "001-Upsert-API.md" → "Upsert API"
 */
function getDocLabel(relativePath) {
  const baseName = path.basename(relativePath, '.md');
  // 先頭の連番部分（例: "001-"）を除去し、ハイフンをスペースに変換
  return baseName.replace(/^\d+-/, '').replace(/-/g, ' ');
}

/**
 * ファイル名から先頭の連番を取得（整数）
 * 例: "001-Upsert-API.md" → 1
 */
function getDocNumber(relativePath) {
  const baseName = path.basename(relativePath, '.md');
  const match = baseName.match(/^(\d+)/);
  return match ? parseInt(match[1], 10) : 0;
}

/**
 * ドキュメントファイルをカテゴリ別にグルーピングし、サイドバー用のリンクリストを生成
 */
function buildGroupedDocsList(files) {
  // Home.md はトップレベルに配置
  const topLevel = files.filter(f => !f.relativePath.includes('/') || f.relativePath.includes('wiki-backup'));
  const categorized = files.filter(f => f.relativePath.includes('/') && !f.relativePath.includes('wiki-backup'));

  // カテゴリ別にグルーピング
  const groups = {};
  for (const file of categorized) {
    const category = file.relativePath.split(/[\\/]/)[0];
    if (!groups[category]) {
      groups[category] = [];
    }
    groups[category].push(file);
  }

  const lines = [];

  // トップレベルファイル（Home.md 等）
  for (const file of topLevel) {
    const title = getDocLabel(file.relativePath);
    lines.push(`- [[${title}|${file.wikiTitle}]]`);
  }

  // カテゴリ別
  const sortedCategories = Object.keys(groups).sort();
  for (const category of sortedCategories) {
    const label = getCategoryLabel(category);
    const categoryNum = getCategoryNumber(category);
    lines.push('');
    lines.push(`### ${categoryNum}. ${label}`);
    lines.push('');
    for (const file of groups[category]) {
      const num = getDocNumber(file.relativePath);
      const title = getDocLabel(file.relativePath);
      lines.push(`${num}. [[${title}|${file.wikiTitle}]]`);
    }
  }

  return lines.join('\n');
}

/**
 * Markdown コンテンツ内の相対リンクを Wiki 用に変換
 *
 * - 相対パスを解決してフラットな Wiki ページ名に変換
 * - .md 拡張子を除去（Wiki ページリンクにする）
 * - アンカー（#...）は維持
 */
function convertLinksForWiki(content, sourceRelativePath) {
  const sourceDir = path.dirname(sourceRelativePath);

  // Markdown リンク [text](path) のパターン
  // 外部URL（http/https）や絶対パス（/）は除外
  return content.replace(
    /\[([^\]]*)\]\((?!https?:\/\/|#|\/)([^)]+)\)/g,
    (match, text, linkPath) => {
      // アンカー部分を分離
      const [filePath, anchor] = linkPath.split('#');

      if (!filePath) {
        // #anchor のみの場合はそのまま返す
        return match;
      }

      // 相対パスを解決（sourceDir 基準）
      const resolved = path.posix.normalize(
        path.posix.join(sourceDir.replace(/\\/g, '/'), filePath.replace(/\\/g, '/'))
      );

      // .md ファイルへのリンクかどうか判定
      if (resolved.endsWith('.md')) {
        const wikiTitle = getWikiTitle(resolved);
        const anchorPart = anchor ? `#${anchor}` : '';
        return `[${text}](${wikiTitle}${anchorPart})`;
      }

      // .md 以外のリンク（画像等）はそのまま維持
      return match;
    }
  );
}

/**
 * Wiki ページを作成または更新（Gitリポジトリ経由）
 */
function createOrUpdateWikiPage(title, content, wikiDir) {
  const fileName = `${title}.md`;
  const filePath = path.join(wikiDir, fileName);

  // ファイルが既に存在するか確認
  const exists = fs.existsSync(filePath);

  // ファイルを書き込み
  fs.writeFileSync(filePath, content, 'utf-8');

  // Gitに追加
  const addResult = spawnSync('git', ['add', fileName], { cwd: wikiDir, stdio: 'pipe' });
  if (addResult.status !== 0) {
    throw new Error(`Command failed: git add "${fileName}"\n${addResult.stderr.toString()}`);
  }

  if (exists) {
    console.log(`✅ 更新: ${title}`);
  } else {
    console.log(`✨ 作成: ${title}`);
  }
}

/**
 * Wiki リポジトリからすべてのページを取得（Git操作のみ）
 */
function getAllWikiPages(wikiDir) {
  const pages = [];

  if (!fs.existsSync(wikiDir)) {
    return [];
  }

  const files = fs.readdirSync(wikiDir);
  for (const file of files) {
    if (file.endsWith('.md')) {
      const title = file.replace(/\.md$/, '');
      // システムページは除外
      if (title !== '_Sidebar' && title !== '_Footer' && title !== 'Home') {
        pages.push({
          title: title,
          fileName: file,
        });
      }
    }
  }

  return pages;
}

/**
 * ページタイトルが保護対象かどうかを判定
 */
function isProtectedPage(title) {
  // [private] で始まるページは保護対象
  if (title.startsWith('[private]')) {
    return true;
  }

  // 明示的に指定された保護対象ページ
  return PROTECTED_WIKI_PAGES.some(protectedPage => {
    // 完全一致または、スラッシュ/ハイフンの違いを考慮
    return title === protectedPage ||
      title === protectedPage.replace(/\//g, '-') ||
      title === protectedPage.replace(/-/g, '/');
  });
}

/**
 * Wiki ページを削除（Git操作のみ）
 */
function deleteWikiPages(wikiDir, pagesToDelete) {
  if (pagesToDelete.length === 0) {
    return 0;
  }

  let deletedCount = 0;
  for (const pageTitle of pagesToDelete) {
    const fileName = `${pageTitle}.md`;
    const filePath = path.join(wikiDir, fileName);

    if (fs.existsSync(filePath)) {
      const rmResult = spawnSync('git', ['rm', fileName], { cwd: wikiDir, stdio: 'pipe' });
      if (rmResult.status !== 0) {
        throw new Error(`Command failed: git rm "${fileName}"\n${rmResult.stderr.toString()}`);
      }
      console.log(`🗑️  削除: ${pageTitle}`);
      deletedCount++;
    }
  }

  return deletedCount;
}

/**
 * メイン処理
 */
function main() {
  console.log(`📚 ${GITHUB_REPO} の Wiki に同期を開始します...\n`);

  // docs/research/ ディレクトリの存在確認
  if (!fs.existsSync(DOCS_DIR)) {
    console.error(`❌ docs/research/ ディレクトリが見つかりません: ${DOCS_DIR}`);
    process.exit(1);
  }

  // Markdown ファイルの取得
  const files = getMarkdownFiles(DOCS_DIR);
  console.log(`📄 ${files.length} 個の Markdown ファイルが見つかりました\n`);

  // Wikiリポジトリをクローン
  const wikiDir = path.join(process.cwd(), '.wiki-temp');
  // GitHub Actions環境では、URLに直接トークンを埋め込む（ユーザー名に x-access-token を利用）
  const encodedToken = encodeURIComponent(GITHUB_TOKEN);
  const wikiRepoUrl = `https://x-access-token:${encodedToken}@github.com/${owner}/${repo}.wiki.git`;
  const gitUserName = process.env.GITHUB_ACTOR || 'github-actions[bot]';
  const gitUserEmail = process.env.GIT_COMMIT_EMAIL || `${gitUserName}@users.noreply.github.com`;

  try {
    // GitHub Actions環境でのGit認証設定
    // GIT_TERMINAL_PROMPTを0に設定してパスワードプロンプトを無効化
    const gitEnv = {
      ...process.env,
      GIT_TERMINAL_PROMPT: '0',
      GIT_ASKPASS: 'echo',
    };

    let isNewWiki = false;

    if (!fs.existsSync(wikiDir)) {
      console.log('📥 Wiki リポジトリをクローン中...\n');
      try {
        execSync(`git clone "${wikiRepoUrl}" "${wikiDir}"`, {
          stdio: 'inherit',
          env: gitEnv
        });
      } catch (cloneError) {
        // Wikiが初期化されていない場合、新規リポジトリとして作成
        console.log('⚠️  Wiki リポジトリが存在しません。新規作成します...\n');
        isNewWiki = true;
        fs.mkdirSync(wikiDir, { recursive: true });
        execSync(`cd "${wikiDir}" && git init`, { stdio: 'pipe', env: gitEnv });
        execSync(`cd "${wikiDir}" && git remote add origin "${wikiRepoUrl}"`, { stdio: 'pipe', env: gitEnv });
        // masterブランチを作成（GitHub Wikiはmasterを使用）
        execSync(`cd "${wikiDir}" && git checkout -b master`, { stdio: 'pipe', env: gitEnv });
      }
    } else {
      try {
        execSync(`cd "${wikiDir}" && git pull origin master`, {
          stdio: 'pipe',
          env: gitEnv
        });
      } catch (pullError) {
        // リモートが空の場合は無視
        console.log('⚠️  リモートからのpullをスキップしました（空のリポジトリの可能性）');
      }
    }

    // リモートURLを認証付きURLに更新（既存クローン対策）
    execSync(`cd "${wikiDir}" && git remote set-url origin "${wikiRepoUrl}"`, {
      stdio: 'pipe',
      env: gitEnv,
    });

    // Gitユーザー情報を設定
    execSync(`cd "${wikiDir}" && git config user.name "${gitUserName}"`, {
      stdio: 'pipe',
      env: gitEnv,
    });
    execSync(`cd "${wikiDir}" && git config user.email "${gitUserEmail}"`, {
      stdio: 'pipe',
      env: gitEnv,
    });

    // Wiki リポジトリから既存のページを取得
    const wikiPages = isNewWiki ? [] : getAllWikiPages(wikiDir);
    const docsWikiTitles = new Set(files.map(f => f.wikiTitle));

    // 保護対象ページを取得（サイドバーに含めるため）
    const protectedPages = wikiPages
      .filter(page => {
        const title = page.title;
        return isProtectedPage(title);
      })
      .map(page => ({
        title: page.title,
        wikiTitle: page.title,
        fileName: page.fileName,
      }));

    // すべてのファイルを追加
    for (const file of files) {
      const rawContent = fs.readFileSync(file.filePath, 'utf-8');
      const content = convertLinksForWiki(rawContent, file.relativePath);
      createOrUpdateWikiPage(file.wikiTitle, content, wikiDir);
    }

    // サイドバーを作成
    const sidebarTemplatePath = path.join(WIKI_TEMPLATE_DIR, '_Sidebar.md');
    const docsList = buildGroupedDocsList(files);
    const protectedList = protectedPages.length > 0
      ? `### Wiki 専用ページ\n\n${protectedPages.map(p => `- [[${p.wikiTitle}|${p.wikiTitle}]]`).join('\n')}`
      : '';
    if (fs.existsSync(sidebarTemplatePath)) {
      const sidebarContent = fs.readFileSync(sidebarTemplatePath, 'utf-8')
        .replace(/\{\{DOCS_LIST\}\}/g, docsList)
        .replace(/\{\{PROTECTED_PAGES\}\}/g, protectedList);
      createOrUpdateWikiPage('_Sidebar', sidebarContent, wikiDir);
    } else {
      // テンプレートがない場合はフォールバック
      const sidebarContent = `# 目次\n\n${docsList}\n\n${protectedList}\n`;
      createOrUpdateWikiPage('_Sidebar', sidebarContent, wikiDir);
    }

    // カスタムフッターを作成
    const footerTemplatePath = path.join(WIKI_TEMPLATE_DIR, '_Footer.md');
    if (fs.existsSync(footerTemplatePath)) {
      const repoUrl = `https://github.com/${GITHUB_REPO}`;
      const footerContent = fs.readFileSync(footerTemplatePath, 'utf-8')
        .replace(/\{\{YEAR\}\}/g, new Date().getFullYear().toString())
        .replace(/\{\{REPO_URL\}\}/g, repoUrl)
        .replace(/\{\{REPO\}\}/g, GITHUB_REPO);
      createOrUpdateWikiPage('_Footer', footerContent, wikiDir);
    }

    // 削除対象のページを処理
    const pagesToDelete = wikiPages
      .filter(page => {
        const title = page.title;
        // 保護対象ページは削除しない
        if (isProtectedPage(title)) {
          return false;
        }
        // docs/research/ に存在しないページのみ削除対象
        return !docsWikiTitles.has(title);
      })
      .map(page => page.title);

    // 保護対象ページの確認ログ
    const allProtectedPages = wikiPages.filter(page => isProtectedPage(page.title));
    if (allProtectedPages.length > 0) {
      console.log(`\n🔒 保護された Wiki ページ（削除対象外）: ${allProtectedPages.length} 個`);
      allProtectedPages.forEach(page => console.log(`   - ${page.title}`));
    }

    if (pagesToDelete.length > 0) {
      console.log(`\n🗑️  削除対象の Wiki ページ: ${pagesToDelete.length} 個`);
      pagesToDelete.forEach(title => console.log(`   - ${title}`));
      deleteWikiPages(wikiDir, pagesToDelete);
    } else {
      console.log('\n✅ 削除対象のページはありませんでした');
    }

    // 変更があるか確認してコミット・プッシュ
    try {
      execSync(`cd "${wikiDir}" && git diff --cached --quiet`, { stdio: 'pipe' });
      console.log('\n✅ 変更はありませんでした');
    } catch {
      // 変更がある場合はコミット・プッシュ
      console.log('\n💾 変更をコミット中...');
      execSync(`cd "${wikiDir}" && git commit -m "Sync docs/research to GitHub Wiki"`, { stdio: 'inherit' });

      console.log('📤 変更をプッシュ中...');
      execSync(`cd "${wikiDir}" && git push origin master`, {
        stdio: 'inherit',
        env: gitEnv
      });

      console.log('\n✅ Wikiへの同期が完了しました！');
    }
  } finally {
    // 一時ディレクトリをクリーンアップ
    if (fs.existsSync(wikiDir)) {
      execSync(`rm -rf "${wikiDir}"`, { stdio: 'pipe' });
    }
  }
}

try {
  main();
} catch (error) {
  console.error('\n❌ エラーが発生しました:', error);
  process.exit(1);
}
