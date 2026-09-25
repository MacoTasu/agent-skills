# Routine プロンプト — loop-engine の定期発火（Claude Code cloud routine）

> **発火は Claude Code の routine（cloud）で行う。** `claude.ai/code/routines` または CLI の
> `/schedule` で schedule トリガの routine を作り、対象リポジトリを選び、プロンプトには
> **下の「routine に保存する本文」だけ**を貼る。
>
> **routine に保存するのは3行のポインタで、中身はこのファイル（＝版管理下）に置く。**
> routine の定義は claude.ai アカウント側に保存され git に残らないため、実質的な手順を
> アカウント側に置くと「なぜこの挙動なのか」が履歴から消える。ポインタだけ置けば、
> 変更は plugin の PR として残る。
>
> `loop-ready` の issue は**実装→分離司法→PR まで進み、PR で止まる**（マージは人間）。
> 段階制（spec の `autonomy: L1|L2`）は廃止した。
>
> 手元セッションの `/loop` による発火は**廃止**（セッションが起きている間しか回らないため）。
> cloud routine はラップトップを閉じても走る。

## routine に保存する本文（ここだけをコピーする）

```
このリポジトリの loop-engine を1巡まわす。

0. まず `git clone --depth 1 https://github.com/MacoTasu/agent-skills /tmp/harness` を実行する。
   プラグインは cloud セッションに同期されないため、ハーネスを public リポジトリから直接取得する
   （理由は下記「cloud にプラグインは届かない」）。clone に失敗したら何もせず ESCALATE して終了する。

1. `/tmp/harness/plugins/loop-engine/skills/loop-engine/reference/routine.md` を Read し、
   その「発火プロンプト本文」節に書かれた手順のとおりに実行すること。
   このプロンプトに書かれていない判断は、すべてそのファイルに従う。
   ただし前提確認の「3プラグインが有効」は、手順0の clone で満たされたものとして読み替える。
```

> **司法の呼び方**: `review-judge:judge` は**プラグインの agent** なので、clone しても
> `subagent_type` としては登録されない（cloud で実際に列挙されるのは
> `claude` / `claude-code-guide` / `Explore` / `general-purpose` / `Plan` / `statusline-setup` のみ）。
> だが**登録は司法の要件ではない**。分離を担保しているのは「別 Task の独立コンテキストで、
> コードを書かず、証拠に照らして判定する」ことであって、型名ではない。
> **clone した `judge.md` を手順書として汎用サブエージェントに読ませる**（詳細は下の
> 「発火プロンプト本文」手順3）。**対象 repo に `judge.md` を置く必要はない**
> （置くとハーネスがプロジェクト空間に侵入し、loop を回す全リポジトリに複製されて乖離する）。

## routine の設定

| 項目 | 値 |
|---|---|
| トリガ | **schedule**（最小間隔は1時間。発火ごとに opus の司法が走りうるので、コストを見て間隔を決める） |
| リポジトリ | 回したいリポジトリ1つ（複数repo セッションは `.claude/settings.json` を読まないため**必ず1つ**） |
| 環境 | 既定（Trusted）でよい。`github.com` / `api.github.com` は既定の許可ドメインに含まれる |
| モデル | routine のプロンプト入力にあるモデル選択で指定する |

### cloud にプラグインは届かない（2026-09-22 実測）

**`.claude/settings.json` にプラグインを宣言しても、cloud セッションにはインストールされない。**
かつて本ファイルは「repo の settings.json に宣言すれば cloud に届く」と書いていたが、**誤りだった**。
だから発火プロンプトの手順0で clone する。

takul で2回 run して観測した内容（どちらも同一結果）:

```
cat /root/.claude/plugins/installed_plugins.json  → { "version": 2, "plugins": {} }
ListPlugins {}                                    → {"results":[]}
find /root/.claude/plugins/synced -type f         → 0件（ディレクトリのみ）
```

セッションは `.claude/settings.json` を `Read` して `extraKnownMarketplaces` /
`enabledPlugins` の中身を**読めている**。宣言は届くが、インストールのトリガーになっていない。
同期先ディレクトリが `synced/<env-uuid>_<account-uuid>/` という命名で、後半が routine の
`creator.account_uuid` と一致することから、**同期はアカウント単位**でリポジトリ設定とは
無関係だと見られる。routine 側の `enabled_plugins` / `extra_marketplaces` フィールドは
API から更新しても**黙って捨てられる**（200 が返るのに値が入らない）。web の routine 編集
フォームにもプラグイン選択は無い（コネクタのみ）。

> 観測は**1アカウント・1環境で2回**。プラットフォームの仕様として断定はしない。
> アカウント側にプラグインを入れる導線が見つかれば、手順0の clone は不要になる。

**対象リポジトリ側に必要な準備**:

- `goals/` と `.claude/hooks/` は `/loop-engine:init` で生成できる。
- **`~/.claude/CLAUDE.md` は cloud に届かない**。無人実行に効かせたい規範は、
  リポジトリの `CLAUDE.md` かプラグイン側に置くこと。
- `.claude/settings.json` のプラグイン宣言（`/loop-engine:init` が追記する）は
  **ローカルセッション向け**。cloud のハーネス配送には効かないが、別マシンや他の人が
  そのリポジトリを手元で触るときに効くので残してよい。

### cloud セッションで使えるもの

- **GitHub の MCP ツール**（`mcp__github__list_issues` 等）が最初から入っている。
  **`gh` CLI は入っていない**ことがある（2026-09-25 実測）。issue の走査・ラベルの付け外し・コメント・
  PR 作成は MCP ツールで行う。本ハーネスの `gh ...` の記述は、MCP の同等の操作に読み替える。
- `git push` は対象リポジトリに対して通る（ブランチを push して PR を作れる）。

## 発火プロンプト本文（ここから）

**起動した session の current working repo** の自律ループを1巡まわす。
※ どの repo を対象にするかは routine の設定で決まる（repo 名はハードコードしない）。

1. 前提確認: current repo が clone 済み・ハーネス（本ファイルと同階層の `SKILL.md`）が読める・
   **`Task`（サブエージェント起動）が使える**（司法を分離して呼ぶため）。
   **どれか欠ければ何も実装せず ESCALATE（人間へ報告）して終了**。
2. `git fetch origin && git checkout main && git pull --ff-only` で current repo を同期する。
3. `loop-engine` skill の **autonomous-entry 節**（このファイルと同階層の `../SKILL.md`。
   プラグインとして入っているなら `${CLAUDE_PLUGIN_ROOT}/skills/loop-engine/SKILL.md`、
   手順0で clone したなら `/tmp/harness/plugins/loop-engine/skills/loop-engine/SKILL.md`）に従う:
   - **`gh issue list --label loop-ready --state open`** で候補を集める（issue 番号昇順）。
     **`loop-running`（処理中）/ `loop-escalated`（人間待ち）が付いているものは除外**。
     **該当が無ければ何もせず正常終了**（no-op）。
   - 各候補の行頭 `Spec: goals/YYYYMMDD-slug.md` コメントから **spec を解決する**。
     解決できない／spec が `status: active` でない／既に `Closes #N` の open PR がある、のいずれかなら
     **`loop-escalated` を付けて次の候補へ**。**issue 本文から仕様を推測しない**（実装根拠は spec だけ）。
   - 解決できた候補のうち **issue 番号昇順で最古1件だけ**選び G1〜G5 を実行する。
     spec frontmatter に `autonomy:` が残っていても読まない（段階制は廃止）。
     着手時に issue へ **`loop-running`** を付け（ロック取得）、G5 完了時に外す。
     G3↔G4 のラウンドは**セッション内カウンタ**で数え、**N=3 を超えたらロールバック/ESCALATE**
     （回数は永続化しない）。
     判定は必ず**分離した司法を Task で起動**して出させる（自己採点しない）。呼び方は環境で分ける:
     - **`review-judge:judge` が `subagent_type` に居るなら**それを `model: opus` で起動する。
     - **居ないなら**（cloud はこちら）、clone した
       `/tmp/harness/plugins/review-judge/agents/judge.md` を**手順書として汎用サブエージェントに
       読ませる**。`subagent_type` は **`Explore` を第一候補**とし、`model: opus` を明示する。
       prompt は「このファイルを Read し、そこに書かれた判事としてふるまい、以下の証拠に照らして
       PASS/REJECT/RETRY/ESCALATE を出せ」＋証拠一式（**PR 本文の「⚠️ 要注意の変更」節の案を含める**）。
       `Explore` を選ぶのは**読み取り専用（Edit / Write を持たない）だから**で、
       「司法はコードを書かない」を指示ではなくツールレベルで担保できる
       （`judge.md` の frontmatter も `tools: Read, Grep, Glob, Bash`）。
       `Explore` の探索向けペルソナが判定の邪魔をするなら `general-purpose` に落とす。
       ただしその場合、**書き込みを防ぐのは指示だけになる**ことを判定コメントに明記すること。
     - **`Task` 自体が使えない環境なら PR を作らず ESCALATE**（自己採点に退化させない）。

     > 検証状況（2026-09-22）: cloud で `general-purpose` + `model: opus` の起動と
     > `judge.md` の読み込みまでは**実測で確認済み**。`Explore` を判事として使えるかは**未検証**。

     PASS で `runs/<slug>/<run-id>/` に as-built を記録し、ブランチを push して PR を作る。
     **PR 本文の先頭に「⚠️ 要注意の変更」節を必ず置く**（書式は `autonomy-gates.md`「要注意の変更」。
     該当が無くても「なし」と書く）。judgments は PR にコメントで添付する。
4. **G6 手前で必ず停止する。PR をマージしない**（自動マージ runtime=Phase 3.1 は未出荷）。
   人間が PR をレビューしてマージする＝HOTL。
5. **state rot 防止**: 終了時に `gh issue list --label loop-escalated` を全て再掲し、ラベル付与から
   **3 日超**のものは `stale＝人間対応を要求` として報告に浮上させる（報告が人間の inbox）。
6. **stale ロックの検出**: `loop-running` が **6 時間**を超えて付いたままの issue は、発火が途中で
   死んだ疑いがある。**`loop-escalated` を追加して報告する（`loop-running` は外さず、ロックも
   取り直さない）**。自動再開は、落ちた原因が残っている場合や死んだ実行がブランチ／PR を
   作りかけている場合に二重作業になるため。報告には `loop/<issue番号>-*` ブランチの有無と
   最終コミット時刻・`Closes #N` の open PR の有無・経過時間を含める。
   **ラベルを外せるのは G5 正常完了時のループと人間だけ**＝再投入は人間が両方のラベルを外して行う。
7. **報告**: 発火の結果は発火の出力（と push 通知）に書く。**リポジトリのファイルには記録しない**
   （main に直接 commit・push しない。出力先は PR ブランチと issue のラベル・コメントだけ）。

ガードレール（厳守）:
- spec の矛盾・欠落、ガードレール（spec の制約節）への抵触は **G1/G2 で ESCALATE**（着手しない）。
- 要注意の変更（security・課金・破壊的変更・認証認可・公開 API の互換破壊）は進めてよいが、
  **PR 本文の先頭で申告する**。申告漏れは司法が RETRY にする。
- 司法 PASS 無しに PR を作らない。G3↔G4 は **N=3 ラウンド上限**、超過は ロールバック/ESCALATE。
- **1 発火で扱うのは最大1 spec**（opus 司法が毎ラウンド走るためコストを抑える）。
- current repo の `goals/` は書き換えない（SSOT は人間所有）。**main に直接 push しない**。

## 発火プロンプト本文（ここまで）

## 運用メモ

- **cadence**: 1 発火で1件まで。opus の司法コストを意識して間隔を決める。routine の最小間隔は1時間。
- **対象 repo**: routine に設定したリポジトリ。プロジェクトごとに routine を作る。
- **実行履歴**: 各 run は cloud session として残るので、`/schedule list` や
  `claude.ai/code/routines` から結果を辿れる。`_last_run` のようなファイルは持たない。
- **ラベルの棚卸し**: `loop-escalated` が溜まるのは人間の対応が滞っているサイン。
  ループ側では自動で外さない。
