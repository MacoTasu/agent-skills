---
name: retro
description: |
  マージ後の retro（学ぶループ）の入口。人間が /dev-crew:retro <PR番号> で呼ぶ。
  PR から事実（司法の判定コメント・先行する retro コメント・人間のレビューコメント・
  PR 作成後のコミット）を集め、dev-crew:retro エージェントを招集して新しい retro コメントを
  PR に追加する。判定も実装も PR 作成もしない。失敗しても何も止めない。
disable-model-invocation: true
allowed-tools:
  - Task
  - Bash
  - Read
---

# retro — マージ後に PR を振り返る

**書き手は `dev-crew:retro` エージェント 1 つ、入口は 2 つ。** PR 作成直後は指揮（`/conductor:dev`）が招集する
（`trigger=pr-created`）。このスキルは**マージ後に人間が打つ 2 つ目の入口**（`trigger=post-merge`）で、
PR 作成後に起きたこと（人間のレビュー指摘・追加コミット）も含めて振り返り、**新しいコメント**を積む。
先行する retro コメントは編集しない。

このスキルがするのは **事実の収集と招集だけ**。分類・提案・コメント・issue はエージェントが書く。

## 実行方法

```bash
/dev-crew:retro <PR番号>
```

## 手順

### 1. 引数の確認

PR 番号が無ければ、次を表示して止まる（推測で PR を選ばない）:

```
使い方: /dev-crew:retro <PR番号>
例: /dev-crew:retro 42
```

### 2. 事実の収集

```bash
gh pr view <PR番号> --json number,state,mergedAt,comments,reviews,commits,url
```

PR が無い・`gh` が失敗したら、「Retro: 未取得（理由）」の 1 行で終わる。

得られた JSON から、次を**機械的に**取り出す（判断はしない）:

| 事実 | 取り出し方 |
|---|---|
| 司法の判定コメント | `comments[]` のうち、本文の見出しに「司法の判定」を含むもの。見出しの「N ラウンド目」があれば N も控える |
| 先行する retro コメント | `comments[]` のうち、本文に ```` ```retro ```` ブロックを含むもの（`rounds` / `rejects` / `interventions` の値を控える） |
| 人間のレビューコメント | `reviews[]` と `comments[]` のうち、著者が bot でなく、司法・retro のコメントでもないもの（件数と本文） |
| PR 作成後のコミット | `commits[]`。先行する retro コメントがあれば、その投稿時刻より後のもの |
| state / mergedAt | マージ済みか。未マージでも止めない（`trigger` は `post-merge` のまま、未マージである事実を渡す） |

`gh pr view` の `--json` にレビューのインラインコメントが含まれないなら、
`gh api repos/{owner}/{repo}/pulls/<PR番号>/comments` で補う（取れなければ「不足」として渡す）。

### 3. 招集

`dev-crew:retro` を Task で招集する（`subagent_type: dev-crew:retro`、`model: sonnet`）。渡すもの:

- 対象 PR 番号、`trigger=post-merge`
- 司法の判定コメント（全ラウンド。本文をそのまま）
- 先行する retro コメント（あれば本文をそのまま。無ければ「先行 retro: なし」）
- 人間のレビューコメント（件数と本文。引用 `>` で）
- PR 作成後のコミット（SHA と件名）
- 契約に無かった書記の所見・契約合意後〜PR 作成までの人間の介入は、このスキルでは取れないので「不足」と明示して渡す
  （先行 retro コメントがあれば、そこに記録済み。無ければエージェントは `interventions` を `unknown` にする。
  このスキルは「介入: なし」と書かない＝取れていないだけで、無かったとは言えない）

エージェントは PR コメントと issue を書き、コメント URL と issue URL を返す。

### 4. 結果の表示

エージェントが返した PR コメントの URL と、作成・積んだ issue の URL を表示して終わる。

## 失敗

どの段階でも続けられなければ、次の **1 行だけ**を表示して終わる。他に何も止めない（非ブロッキング）:

```
Retro: 未取得（<理由>）
```

## しないこと

- PR 番号を推測する（引数が無ければ案内して止まる）
- 集めた事実を自分で分類・評価する（エージェントの仕事）
- 先行する retro コメントを編集する（新しいコメントを積む）
- PR を作る・マージする・コードを書く
