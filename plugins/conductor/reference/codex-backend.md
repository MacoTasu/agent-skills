# 実行方式: Codex

司法（judge）を、Task サブエージェントではなく [Codex CLI](https://github.com/openai/codex) の
`codex exec` に担わせる手順。あわせて `codex exec review` を**任意の書記**として使う手順も置く。
**任意の実行方式**で、既定は Task のまま。行政（implement）には使わない。

## なぜ Codex か

- **判事を別ベンダーのモデルにできる。** 書いたモデルと採点するモデルが同じだと、同じ盲点を
  両方が共有する（`herdr-backend.md`「なぜペインに出すのか」と同じ理由）。
- **herdr が要らない。** `codex exec` は非対話で動き、Bash から直接呼べる。ペインも画面の読み取りも無い。
- **「直せない」を OS のサンドボックスで強制できる。** `-s read-only` はシェル経由の書き込みも遮断する。
  Copilot CLI の `--deny-tool write` がシェルを止められず「禁止＋事後検出」に弱まったのと違い、
  判事の分離が再び**構造的**になる。
- **判定を JSON に固定できる。** `--output-schema` を付けると最終応答がその schema どおりの JSON だけになる。
  判定行の解析も画面読みも要らない。

実測（codex-cli 0.162.1、macOS）:

| 操作 | `-s read-only` | `-s workspace-write` |
|---|---|---|
| cwd への書き込み | 遮断 | 可 |
| `.git/` への書き込み・`git commit` | 遮断 | 遮断 |
| `$TMPDIR` への書き込み | 遮断 | 可 |
| `$HOME` への書き込み | 遮断 | 遮断 |
| cwd 外の読み取り（例: `/etc/hosts`） | 可 | 可 |
| ネットワーク（curl） | 遮断 | 遮断 |

- `-o <file>` の最終応答ファイルは `read-only` でも書ける（Codex 本体がサンドボックスの外で書く）。
  結果の受け渡しはこれで足りる。判事自身にファイルを書かせる必要が無い。
- 判事は `read-only` で動かす。書き込み（キャッシュ・ビルド成果物・`$TMPDIR`）やネットワークを要する
  テストは、サンドボックスの中では失敗しうる。そこで**決定性チェック（テスト・lint・型）は指揮が実行し、生の出力を証拠として渡す**。
  Codex 判事が担うのはセマンティック判定と総合判定だけ。

## 設定

対象リポジトリの `.claude/conductor.json`（任意。無ければ全役割 Task）:

```json
{
  "backends": {
    "judge": { "via": "codex", "model": "<任意>" }
  },
  "scribes": ["codex-review"]
}
```

| キー | 意味 |
|---|---|
| `backends.judge.via` | `task`（既定）/ `herdr` / `codex` |
| `backends.judge.model` | 任意。`codex exec` の `-m` にそのまま渡す。無ければ Codex の既定モデル |
| `scribes` | 任意。`codex-review` があれば、後述の書記を公式6観点に加えて回す |

`via: codex` は judge だけに対応する。implement に指定されていたら Task にフォールバックする
（行政は書き込みが仕事なので `read-only` では動かない。未検証の構成を推測で使わない）。

## フォールバック条件（1つでも欠けたら Task）

招集の直前に毎回検査し、欠けたら**理由を1行表示して Task で続行**する。黙って切り替えない。

```bash
command -v codex                      # codex がある
command -v jq                         # 結果の検査に使う（手順5）
codex login status                    # 認証済み（exit 0。"Logged in using ChatGPT" など）
git branch --show-current             # 空でなく、かつ main 等でないこと（実装ブランチの上にいる）
```

`git branch --show-current` は detached HEAD で空文字を返すので、空も「欠けた」として扱う。
加えて `judge.md` が見つかること（`herdr-backend.md`「1. judge.md を見つける」の `find` をそのまま使う。
見つかったディレクトリを `<judge_root>` と呼ぶ）。

- **クォータ（利用上限の残り）は事前に照会できない。** `codex doctor` は認証・MCP サーバ数・
  サンドボックスの既定値を出すが残量は出さず、`--json` に出るのもトークン使用量だけ。
  上限に当たったことは実行時の失敗として拾う（「判事が失敗したとき」）。
- **cloud の routine（`loop-engine`）には適用しない。** この設定を読まない。

## 前提: 指揮・行政・司法は同じディレクトリで動く

`herdr-backend.md` の同名節と同じ。`-C "$PWD"` も改ざん検出のスナップショットも、
**指揮のいるディレクトリ**を実装の場所とみなす。実装が別の worktree にある状態で判事を呼ばない。

## 判事の手順

招集ごとに新しい一時ディレクトリを `mktemp -d` で作り、`<dir>` と呼ぶ（リポジトリの外。
`.claude/` にも書かない。前回の結果を誤って読まないよう使い回さない）。

### 1. 決定性チェックを指揮が実行する

生の出力（stdout・stderr・exit code）を `<dir>/evidence/<基準ID>.txt` に基準ごとに保存する。
何を実行するかは契約の種類で決まる:

- **インライン契約** — 各基準に併記された検証方法を、指揮が**そのまま**実行する（例: `<dir>/evidence/C1.txt`）。
- **spec-kit 契約**（`specs/<機能>/`）— `spec.md` の基準には検証コマンドが併記されない。
  `<judge_root>/reference/contract-speckit.md`「基準 ↔ 決定性証拠の対応づけ」の手順どおり、
  基準 ID（`FR-###`、`US<n>/AC<m>`、実装で満たせる `SC-###`）から自動テストを対応づけて特定し
  （テストコード中の基準 ID の言及 → `tasks.md` のテスト作成タスク → `quickstart.md` / `contracts/` の順）、
  基準ごとに実行して `<dir>/evidence/<基準ID>.txt` に保存する（例: `<dir>/evidence/FR-001.txt`。
  ファイル名に使えない `/` は `-` に置き換える: `US1-AC2.txt`）。どのテストをなぜ対応づけたかも同じファイルに書く。
  **対応するテストが見つからない基準は「テストなし」と保存する**（判事が RETRY にする）。
  公開後にしか測れない `SC-###` は「対象外」と保存する。

- これは**事実の採取であって判定ではない**。緑・赤の解釈も、基準を満たすかの判断も判事が行う。
- 実行できなかった検証方法は「実行不能」とその理由を保存する。黙って省かない。
- 行政の「テストは緑でした」で代用しない（`herdr-backend.md`「共通: 報告は参考情報、事実は取り直す」）。

### 2. 改ざん検出のスナップショット（前）

`herdr-backend.md`「3. 改ざん検出のスナップショット」と**同じコマンド**を、判事を呼ぶ直前に実行して控える。
`read-only` では書き込めないはずだが、サンドボックスの不具合や設定の誤りに対する保険として省かない。

### 3. 指示文を書く

`<dir>/prompt.md` に書くこと:

1. `<judge_root>/agents/judge.md` を読み、**frontmatter より下を自分の役割として従う**。
   文中の `${CLAUDE_PLUGIN_ROOT}` は `<judge_root>` に読み替える
2. (a) 契約（spec-kit の機能ディレクトリのパス、またはインライン契約の本文）、
   (b) 差分の範囲（例: `main...HEAD` と未コミットの変更）、
   (c) 証拠 — 書記の所見、`<dir>/evidence/` の決定性の出力、指揮が取った `git diff --stat`、
   および**行政の申告（未検証）**
3. **決定性チェックは指揮が実行済み。再実行しない。** 結果は `<dir>/evidence/` の生の出力から読む。
   `evidence/` に無い基準は**証拠なし**として扱い、PASS しない
4. リポジトリ内のファイルを作らない・変更しない・コミットしない（サンドボックスでも遮断されるが念押し）
5. **最終応答は schema どおりの JSON だけにする**（`verdict` と `report`。`report` には judge.md の
   出力形式の本文を入れる）

### 4. 起動する

```bash
codex exec -C "$PWD" -s read-only --ephemeral --ignore-user-config --ignore-rules \
  --color never --json [-m <model>] \
  --output-schema "${CLAUDE_PLUGIN_ROOT}/reference/codex-verdict.schema.json" \
  -o "<dir>/result.json" - < "<dir>/prompt.md" > "<dir>/events.jsonl" 2> "<dir>/stderr.txt"
```

| 引数 | 意味 |
|---|---|
| `-C "$PWD"` | 作業ディレクトリ＝指揮のいる場所（前提の節） |
| `-s read-only` | OS サンドボックスで書き込みとネットワークを遮断する（「なぜ Codex か」の表） |
| `--ephemeral` | セッションを保存しない。判事は毎回まっさらな文脈で呼ぶ |
| `--ignore-user-config` | 利用者の `config.toml`（MCP サーバ・hooks など）を読まない。**MCP サーバはサンドボックスの外で動く**ので、読み込むと read-only の外に書ける経路が残る。認証はそのまま使える |
| `--ignore-rules` | 利用者・プロジェクトの execpolicy `.rules` を読まない（承認の挙動を環境に左右させない） |
| `--color never` / `--json` | 出力を機械可読にする。`events.jsonl` に判事が何を走らせたかが残る |
| `-m <model>` | `conductor.json` に `model` があるときだけ付ける |
| `--output-schema` | 最終応答を `codex-verdict.schema.json` の JSON に固定する |
| `-o "<dir>/result.json"` | 最終応答の書き出し先（read-only でも書ける） |
| `- < "<dir>/prompt.md"` | 指示文を stdin から渡す。**stdin は必ず閉じた状態で渡す**（「既知の制約」） |

- 判定は10分を超えうる。Bash のタイムアウトに収まらないので、**バックグラウンド実行**にして
  終了の通知を待つ。タイムアウトは未完了を意味しない。**同じ指示で二重に起動しない**。

### 5. 結果を読む

```bash
jq -e 'keys == ["report","verdict"]
       and (.verdict | IN("PASS","REJECT","RETRY","ESCALATE"))
       and (.report | type == "string" and length > 0)' "<dir>/result.json"
jq -r '.report' "<dir>/result.json"
```

- キーが `verdict` と `report` だけ、`verdict` が4つの列挙値のどれか、`report` が空でない文字列であることを
  確かめてから使う。1つでも満たさなければ schema 不適合として `RETRY`（「判事が失敗したとき」）。
- `events.jsonl` の `item.completed` のうち `command_execution`（`command`・`aggregated_output`・
  `exit_code`）を、**判事が何を走らせたか**の記録として判定に添える。
  例: `jq -c 'select(.type=="item.completed" and .item.type=="command_execution") | .item | {command, exit_code}' "<dir>/events.jsonl"`

### 6. 改ざん検出のスナップショット（後）

結果を読んだ直後に手順2と同じコマンドを実行し、前と比べる。**一致しなければ判定の内容に関わらず
`ESCALATE`**。扱いは `herdr-backend.md`「3. 改ざん検出のスナップショット」と同じ（直さない・戻さない・
`git status --short` を添えて人間に渡す）。

### 7. 判定をルーティングする

判定の後のルーティング（PASS → ship など）は Task の判事と同じ。**指揮は判定を上書きしない。**
毎回 `--ephemeral` なので、同じ契約の2回目以降も前の判定の文脈は引き継がない。

## 判事が失敗したとき

| 状況 | 扱い |
|---|---|
| 認証切れ・利用上限（`stderr.txt` か `events.jsonl` の `error` に usage limit / rate limit / 429 系の文言） | **判事は動いていない。** Task の判事にフォールバックし、理由を1行表示する |
| それ以外で `result.json` が無い、空、JSON でない、手順5の `jq -e` が失敗する（キーが `verdict`・`report` 以外を含む／欠ける、`verdict` が列挙値でない、`report` が空） | **`RETRY`（証拠不足）**。PASS に倒さない |
| スナップショットが前後で不一致 | 判定に関わらず **`ESCALATE`** |

- 利用上限と認証切れのエラー文言は**未観測**。上の分類の文言は推定で、実物で確定させる。
  分類できない失敗は `RETRY` に倒す（判事が動いたか分からないものを、動かなかったとは決めつけない）。
- 失敗時は `stderr.txt` の末尾と `events.jsonl` の `error` を、理由として人間に見せる。

## 書記の手順（`scribes` に `codex-review` があるとき）

公式6観点と同じ**書記（証拠提供）**として、Codex 自身のコードレビューを取る。所見は判事に渡す証拠 (c) に含める。
判事とは別の `mktemp -d` の一時ディレクトリ `<dir>` を使う。

```bash
codex exec --color never review --base <base> --ephemeral --ignore-user-config --ignore-rules \
  -c 'sandbox_mode="read-only"' [-m <model>] \
  -o "<dir>/codex-review.md" </dev/null > "<dir>/review-events.txt" 2> "<dir>/review-stderr.txt"
```

- `<base>` は差分の基点のブランチ（通常 `main`）。
- `codex exec review` は `-s` を持たないので、サンドボックスは `-c 'sandbox_mode="read-only"'` で指定する。
- `--color` は `exec` のオプションで `review` のオプションではないので、`review` より前に置く
  （後ろに置くと引数エラーで止まる）。
- `--base` はレビュー指示（`[PROMPT]` 引数や `-` での stdin 読み取り）と併用できない（引数エラーで止まる）。
  指示は渡さず、stdin だけを `</dev/null` で閉じる（開けたままにすると止まりうる。「既知の制約」）。
- `--json` を付けないので、標準出力（`review-events.txt`）には最終所見と同じ本文がそのまま出る。
  進行の表示（実行したコマンドなど）は stderr（`review-stderr.txt`）に出る。所見として読むのは `codex-review.md`。
- 失敗したら「Codex レビュー: 未取得（理由）」と明記して進む。**書記の失敗で判事を止めない。**
- 書記なので拘束力は無い。所見を束ねて判定するのは判事。

## 既知の制約

- **cloud の routine（`loop-engine`）には適用しない。** この設定を読まない。
- **人間が途中を見られない。** herdr のペインと違い、判事の作業を目視して割り込めない。
  見たいときは `events.jsonl` を後から読む。実装を目視したいなら行政は herdr を使う。
- **クォータは事前に照会できない。** 上限に当たると実行時に失敗する（「判事が失敗したとき」）。
- **stdin が端末でない状態でプロンプトを引数に渡すと、`codex exec` は stdin を待って止まる**
  （"Reading additional input from stdin..." を出したままハングする）。指示文は `- < prompt.md` で
  stdin から渡すか、`</dev/null` で閉じる。
- **Codex は `AGENTS.md` を読み、`CLAUDE.md` は読まない。** リポジトリの規約は契約や指示文に書いて渡す。
- 判事が `read-only` で動くため（書き込みやネットワークを要するテストは失敗しうる）、判事は自分で
  決定性チェックを走らせない。決定性の証拠の質は
  指揮が実行した内容で決まる（手順1を省くと、判事は証拠なしとして PASS しない）。
