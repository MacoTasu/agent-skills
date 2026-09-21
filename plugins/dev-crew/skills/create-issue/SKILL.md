---
name: create-issue
description: |
  GitHub Issueを作成するスキル。
  対話形式で情報を収集し、AIフレンドリーなIssueを生成。
  手動で /dev-crew:create-issue で呼び出し。
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Create Issue Skill

GitHub Issueを作成するための標準手順。
AIが仕事に着手しやすいフォーマットでIssueを生成する。

## 実行方法

```bash
# 対話形式（推奨）
/dev-crew:create-issue

# タイトル指定
/dev-crew:create-issue "認証機能のバグ修正"

# オプション付き
/dev-crew:create-issue --title "バグ修正" --label bug --assignee @me
```

## オプション

| オプション | 説明 | 例 |
|-----------|------|-----|
| `--title` / `-t` | Issueタイトル | `--title "Fix login bug"` |
| `--label` / `-l` | ラベル（複数指定可） | `--label bug --label urgent` |
| `--assignee` / `-a` | アサイン | `--assignee @me` |
| `--repo` / `-R` | リポジトリ指定 | `--repo owner/repo` |
| `--quick` | 対話スキップ | 最小限の情報で即作成 |
| `--draft` | ドラフトモード | テンプレートのみ表示 |

## 手順

### 1. 状態確認

```bash
# GitHubリポジトリ確認
gh repo view --json name,url

# 類似Issue検索
gh issue list --search "<keywords>" --state all --limit 5
```

類似Issueが見つかった場合は、ユーザーに通知して続行するか確認する。

### 2. 情報収集（対話形式）

以下の項目を順番に収集する（スキップ可）:

1. **タイトル**: 何をするかを簡潔に（必須）
2. **背景・コンテキスト**: なぜこのタスクが必要か
3. **ゴール**: 何が達成されれば完了か
4. **詳細**: 具体的な実装内容
5. **Acceptance Criteria**: 完了条件のチェックリスト
6. **スコープ外**: 今回やらないこと

### 3. Issue本文生成

収集した情報をテンプレートに適用:

```markdown
## 背景・コンテキスト

[ユーザー入力の背景]

## ゴール

[ユーザー入力のゴール]

## 詳細

[ユーザー入力の詳細]

## Acceptance Criteria

- [ ] [条件1]
- [ ] [条件2]
- [ ] [条件3]

## スコープ外

- [対象外項目1]
- [対象外項目2]

## 関連

- 関連Issue/PR: [検出されたもの]
- 関連ファイル: [検出されたファイル]

---
🤖 Generated with [Claude Code](https://claude.ai/claude-code)
```

### 4. ユーザー確認

生成したIssue本文をプレビュー表示し、確認を求める:

```
### プレビュー
[生成したIssue本文]

---
このIssueを作成しますか？ [Y/n/edit]
```

- `Y`: 作成実行
- `n`: キャンセル
- `edit`: 編集モード

### 5. Issue作成

```bash
gh issue create \
  --title "<タイトル>" \
  --body "$(cat <<'EOF'
<生成したIssue本文>
EOF
)" \
  --label "<ラベル>" \
  --assignee "<アサイン>"
```

作成後、Issue URLを表示。

## テンプレート

### フルフォーマット（デフォルト）

```markdown
## 背景・コンテキスト

[なぜこのタスクが必要か、前提となる状況]

## ゴール

[何が達成されれば完了か、一言で]

## 詳細

[具体的な実装内容、技術的な詳細]

### 要件
- [要件1]
- [要件2]

## Acceptance Criteria

- [ ] [完了条件1]
- [ ] [完了条件2]
- [ ] [完了条件3]

## スコープ外

- [今回やらないこと]

## 関連

- 関連Issue/PR: #XX
- 関連ファイル: `path/to/file`
- 参考ドキュメント: [URL]

---
🤖 Generated with [Claude Code](https://claude.ai/claude-code)
```

### ショートフォーマット（`--quick` オプション時）

```markdown
## 概要

[タイトルの詳細説明]

## Acceptance Criteria

- [ ] [完了条件]

---
🤖 Generated with [Claude Code](https://claude.ai/claude-code)
```

## エラーハンドリング

### 認証エラー

```
⚠️ GitHub認証が必要です。

以下を実行してください:
gh auth login
```

### リポジトリ未設定

```
⚠️ GitHubリポジトリが見つかりません。

以下のいずれかを実行してください:
1. GitHubリポジトリ内でこのコマンドを実行
2. --repo オプションでリポジトリを指定

例: /dev-crew:create-issue --repo owner/repo "タイトル"
```

### 重複Issue検出

```
⚠️ 類似のIssueが見つかりました:

- #42: ユーザー認証機能の改善 (open)
- #38: パスワード関連の修正 (closed)

続行しますか？ [Y/n/view]
```

## 例

### 例1: 対話形式で新機能を追加

```
ユーザー: /dev-crew:create-issue

Claude: Issueのタイトルを入力してください:

ユーザー: ユーザー認証にパスワードリセット機能を追加

Claude: ### 背景・コンテキスト
なぜこの機能が必要ですか？（Enterでスキップ）

ユーザー: パスワードを忘れたユーザーからの問い合わせが増えている

Claude: ### ゴール
何が達成されれば完了ですか？（Enterでスキップ）

ユーザー: ユーザーがメール経由でパスワードをリセットできる

Claude: ### Acceptance Criteria
完了条件を入力してください（複数行可、空行で終了）:

ユーザー:
- パスワードリセットリンクをメール送信できる
- リンクは24時間で無効化される
- 新しいパスワードを設定できる

Claude:
### プレビュー

## 背景・コンテキスト
パスワードを忘れたユーザーからの問い合わせが増えている

## ゴール
ユーザーがメール経由でパスワードをリセットできる

## Acceptance Criteria
- [ ] パスワードリセットリンクをメール送信できる
- [ ] リンクは24時間で無効化される
- [ ] 新しいパスワードを設定できる

---
🤖 Generated with [Claude Code](https://claude.ai/claude-code)

---
このIssueを作成しますか？ [Y/n/edit]

ユーザー: Y

Claude: ✅ Issueを作成しました
https://github.com/owner/repo/issues/123
```

### 例2: クイック作成

```
ユーザー: /dev-crew:create-issue --quick "READMEのタイポ修正"

Claude:
### プレビュー

## 概要
READMEのタイポ修正

## Acceptance Criteria
- [ ] タイポを修正する

---
🤖 Generated with [Claude Code](https://claude.ai/claude-code)

---
このIssueを作成しますか？ [Y/n/edit]

ユーザー: Y

Claude: ✅ Issueを作成しました
https://github.com/owner/repo/issues/124
```

### 例3: オプション付き作成

```
ユーザー: /dev-crew:create-issue --title "CI/CDパイプラインの最適化" --label enhancement --label ci --assignee @me

Claude: ### 背景・コンテキスト
なぜこの機能が必要ですか？（Enterでスキップ）

ユーザー: ビルド時間が長くなってきたので短縮したい

...（以降、対話形式で情報収集）

Claude: ✅ Issueを作成しました
https://github.com/owner/repo/issues/125

ラベル: enhancement, ci
アサイン: @me
```

## 注意事項

- 秘匿情報（APIキー、パスワード等）はIssueに含めない
- 大きなタスクは小さく分割してIssue化することを推奨
- Acceptance Criteriaは検証可能な形で記述する（「高速」ではなく「200ms以下」）
- 重複Issueがないか事前に確認する
