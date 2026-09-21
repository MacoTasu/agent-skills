---
name: release-note
description: |
  PR番号からNotionの「お知らせ」ページをWIPとして作成するスキル。
  概要を自動生成し、PR内のスクショを抽出して添付、開発者コメント欄を空で残す。
  Notion MCPが使える場合は直接ページを作成、使えない場合はMarkdownを書き出してユーザーに渡す。
  手動で /dev-crew:release-note <PR番号> で呼び出し。
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
  - mcp__claude_ai_Notion__notion-search
  - mcp__claude_ai_Notion__notion-fetch
  - mcp__claude_ai_Notion__notion-create-pages
  - mcp__claude_ai_Notion__notion-update-page
---

# Release Note Skill

GitHub PRから、Notionの「お知らせ」DBにWIPページを作成するスキル。
リリース前のドラフトをセットアップし、開発者コメントだけを後で埋めるだけにする。

## 実行方法

```bash
# PR番号を渡す（最低限）
/dev-crew:release-note 1234

# リポジトリを明示
/dev-crew:release-note 1234 --repo owner/repo

# プロパティを事前に渡す（対話スキップ）
/dev-crew:release-note 1234 \
  --title "決済フロー改善" \
  --category "改善" \
  --service "Checkout" \
  --release-date 2026-05-10

# Markdown書き出しを強制（MCPを使わない）
/dev-crew:release-note 1234 --markdown
```

## 入力

| 引数 / オプション | 説明 | 必須 |
|---|---|---|
| `<PR番号>` | お知らせの元になるPR | ✅ |
| `--repo` / `-R` | `owner/repo` 形式。省略時は `gh` の解決に従う | |
| `--title` | お知らせのタイトル（省略時はPRタイトルを提案） | |
| `--category` | カテゴリ（DBのselect値に一致させる） | |
| `--service` | サービス名（DBのselect値に一致させる） | |
| `--release-date` | 公開予定日 `YYYY-MM-DD` | |
| `--db` | NotionのDB IDを上書き | |
| `--markdown` | MCPを使わずMarkdownを書き出すモード | |

省略されたプロパティは対話で順に埋める。

## 設定

Notion DB IDとプロパティ名の対応は `config.yaml` に保持する。
初回のみ `config.example.yaml` をコピーして編集する：

```bash
cp "${CLAUDE_PLUGIN_ROOT}/skills/release-note/config.example.yaml" \
   .claude/release-note.config.yaml
```

`config.yaml` は `.gitignore` 対象とし、コミットしない。

## 手順

### 1. 前提チェック

```bash
gh auth status
gh repo view --json nameWithOwner,url
```

`config.yaml` の有無を確認。なければユーザーに作成を促す。

### 2. PR情報の取得

```bash
gh pr view <PR番号> --json number,title,body,url,author,mergedAt,baseRefName,headRefName,files,commits,labels
gh pr diff <PR番号>
gh api repos/{owner}/{repo}/issues/<PR番号>/comments
gh api repos/{owner}/{repo}/pulls/<PR番号>/comments
```

以下を抽出：

- PRタイトル / 本文 / マージ日
- コミット一覧と件名（「概要」生成のソース）
- 変更ファイル一覧（影響範囲の推定）
- ラベル（カテゴリのデフォルト推定に利用）
- 本文・コメント中の画像URL（`![...](...)` と `<img src="...">`、`https://user-images.githubusercontent.com/...` 等）

### 3. プロパティ確定（対話）

足りないものだけ順に質問する：

1. **タイトル** — デフォルトはPRタイトル。日本語のお知らせ向けに整形を提案。
2. **カテゴリ** — DB側のselect候補を `notion-fetch` で取得して提示。
3. **サービス名** — 同上。
4. **公開日** — デフォルトは `today + 1営業日` を提案。

選択値はDBの既存optionに完全一致させる。一致しない場合は最も近いものを提案して再確認する（誤った新規optionを勝手に作らない）。

### 4. スクショの取得（skillの責務）

優先度の高い順に、自動で集める：

1. **PR本文・コメント内の画像** — 上で抽出したURLをダウンロードして `cache/release-note/<PR番号>/` に保存。
2. **GitHub添付画像（user-images）** — 認証付きURLは `gh api` 経由で取得。
3. **既存のスクショが0件のとき** — ユーザーに以下を提示してから先へ進む：
   - 「PRに画像が見つからなかった。スクショ無しで続行しますか？ [Y/n/path]」
   - `path` を選んだ場合、ローカルの画像パスを受け取って添付。

ユーザーに「自分でスクショ撮って」と要求しないこと。skill側で取れる手段を尽くす。

### 5. 「概要」セクションの生成

PRのコミット件名・本文・変更ファイルから、「何が変わったか」を箇条書きで生成する。

ルール：

- ユーザー視点の言い回しに直す（"refactor: extract X" → "内部処理の整理（挙動変更なし）"）。
- `chore:` `ci:` `test:` 等、利用者に無関係なコミットは落とす。
- 1項目1行、3〜7項目に収める。多すぎる場合はカテゴリで束ねる。

### 6. 「変更内容」セクションの生成

ファイル単位ではなく、機能単位でまとめる。各項目で：

- 何を変えたかの一文
- **Before / After** で書けるものは差分で示す（UI文言、デフォルト値、エンドポイント等）
- 4で集めたスクショを該当箇所に配置

差分が文字列レベルで明確に取れないものは Before/After を無理に作らない。

### 7. 「開発者コメント」セクションの設置

空のプレースホルダだけ置く：

```
## 開発者コメント

> ここに開発者から一言（リリース後の注意点・既知の制限など）。
```

skill側で内容を埋めない。

### 8. Notionに書き込み

#### 8a. MCP経路（デフォルト）

`mcp__claude_ai_Notion__notion-create-pages` で、`config.yaml` のDBに新規ページを作成：

- properties:
  - `Title` ← タイトル
  - `Status` ← `WIP`
  - `Category` ← カテゴリ
  - `Service` ← サービス名
  - `ReleaseDate` ← 公開日
  - `PR` ← PRのURL（urlプロパティがあれば）
- children:
  - heading_1 「概要」 + 箇条書き
  - heading_1 「変更内容」 + 機能ごとのtoggleまたはheading_2
    - paragraph（説明）
    - code または callout（Before/After）
    - image（スクショ）
  - heading_1 「開発者コメント」 + quote（プレースホルダ）

画像は Notion の external image ブロックとして、ダウンロード元のGitHub URLを直接参照する（GitHubのCDNはNotionから到達可能）。MCPがアップロードに対応していない場合はexternal URLにフォールバック。

成功時は作成ページのURLを表示。

#### 8b. Markdownフォールバック

以下のいずれかでMarkdownモードへ切り替える：

- `--markdown` 指定時
- MCPの認証エラー（無料プラン制限・トークン未設定）
- `notion-create-pages` が失敗

書き出し先：

```
cache/release-note/<PR番号>/dev-crew:release-note.md
```

ユーザーへの提示：

```
✅ Markdownを書き出しました
cache/release-note/<PR番号>/dev-crew:release-note.md

NotionのDB「<DB名>」で New を押し、貼り付けてください。
プロパティ：
  Title: <タイトル>
  Status: WIP
  Category: <カテゴリ>
  Service: <サービス名>
  ReleaseDate: <YYYY-MM-DD>
スクショ: cache/release-note/<PR番号>/screenshots/ にあります。
```

### 9. 終了レポート

- 作成したNotionページURL（または書き出したMarkdownパス）
- 取り込んだスクショ枚数
- 後で人間が埋める必要がある項目（開発者コメント、未確定のBefore/After）

## ページ構成（テンプレート）

```markdown
# 概要

- <変更1>
- <変更2>
- <変更3>

# 変更内容

## <機能Aの変更>

<一文で要約>

**Before**
<Before の状態>

**After**
<After の状態>

![<キャプション>](<スクショURL>)

## <機能Bの変更>

...

# 開発者コメント

> ここに開発者から一言（リリース後の注意点・既知の制限など）。
```

## エラーハンドリング

### Notion MCPが認証エラー

```
⚠️ Notion MCP に到達できませんでした（理由: <auth_required|paid_only|...>）。
Markdownモードに切り替えます。
```

そのまま 8b に進む。ユーザーには確認しない（自動フォールバック）。

### config.yaml が無い

```
⚠️ Notion DB 設定が見つかりません。

以下を実行して、お知らせDBのIDとプロパティ名を設定してください：

  cp "${CLAUDE_PLUGIN_ROOT}/skills/release-note/config.example.yaml" \
     .claude/release-note.config.yaml
  $EDITOR .claude/release-note.config.yaml

その後、もう一度 /dev-crew:release-note <PR番号> を実行してください。
```

ここで処理を停止する。

### PRがマージされていない

警告だけ出して続行（リリース前にWIPで仕込みたいケースを想定）：

```
⚠️ PR #1234 はまだマージされていません。WIPページとして作成を続行します。
```

### カテゴリ・サービス名がDB optionと一致しない

```
⚠️ カテゴリ「ばぐ修正」は既存optionに一致しません。

候補:
  1) バグ修正
  2) 改善
  3) 新機能

どれにしますか？ [1/2/3/abort]
```

新規optionを勝手に作らない。

## 例

### 例1: 対話で完走

```
ユーザー: /dev-crew:release-note 1234

Claude: PR #1234「Fix: 決済時のリトライロジック修正」を取得中...
        スクショ 2 枚を検出（PRコメントから）。

        タイトル案: 「決済リトライの安定化」
        この案で良いですか？ [Y/edit]

ユーザー: Y

Claude: カテゴリ:
        1) バグ修正  2) 改善  3) 新機能
        ラベル `bug` から「バグ修正」を提案。 [1/2/3]

ユーザー: 1

Claude: サービス名:
        1) Checkout  2) Account  3) Admin

ユーザー: 1

Claude: 公開日（YYYY-MM-DD、デフォルト 2026-05-07）:

ユーザー: [Enter]

Claude: ### プレビュー
        # 概要
        - 決済中に通信エラーが起きた場合のリトライ間隔を見直し
        - 最大リトライ回数を3→5に拡張
        ...

        このまま Notion に WIP として作成しますか？ [Y/n/markdown]

ユーザー: Y

Claude: ✅ Notionにページを作成しました
        https://www.notion.so/.../...

        スクショ: 2枚添付
        要記入: 開発者コメント
```

### 例2: MCPが使えずMarkdownにフォールバック

```
ユーザー: /dev-crew:release-note 1234

Claude: PR #1234 を取得中...
        ⚠️ Notion MCP に到達できませんでした（auth_required）。
        Markdownモードに切り替えます。

        ...（プロパティ確定の対話）...

        ✅ Markdownを書き出しました
        cache/release-note/1234/release-note.md
        スクショ: cache/release-note/1234/screenshots/ (2枚)
```

### 例3: フラグで一括指定

```
ユーザー: /dev-crew:release-note 1234 \
           --title "決済リトライの安定化" \
           --category "バグ修正" \
           --service "Checkout" \
           --release-date 2026-05-10

Claude: PR #1234 を取得中... プロパティはフラグで確定済み。
        ✅ Notionにページを作成しました
        https://www.notion.so/.../...
```

## 注意事項

- **WIP固定**: このスキルが作るページは常に `Status = WIP`。公開状態への遷移は人手で行う。
- **新規optionを作らない**: カテゴリ・サービス名は必ず既存optionに合わせる。
- **スクショの責務**: ユーザーに撮影依頼をしない。PR内に画像が無い場合のみ、ローカルパスでの差し込みを許可する。
- **秘匿情報を載せない**: PR本文に含まれるトークン・URLパラメータ等を機械的に検出してマスクする。
- **Markdownモードの成果物**: `cache/release-note/<PR番号>/` 以下に集約し、後から再利用できる形にする。
