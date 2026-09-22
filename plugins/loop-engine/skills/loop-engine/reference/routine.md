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
> **既定は L1（報告のみ・副作用なし）**。実装まで無人で進むのは spec frontmatter に `autonomy: L2` を
> 付けたものだけ（[[loop-intake-triage]] の2ダイヤル）。
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
| トリガ | **schedule**（最小間隔は1時間。L1 だけなら短め、L2 を含むなら司法コストを見て長めに） |
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
  issue の走査に `gh` 認証は不要（`gh` CLI も使えるが、MCP の方が確実）。
- `ccusage` は**入っていない**ため `loop-budget` は exit 0（スキップ）になる＝予算ゲートは効かない。

## 発火プロンプト本文（ここから）

**起動した session の current working repo** の自律ループを1巡まわす。
※ どの repo を対象にするかは routine の設定で決まる（repo 名はハードコードしない）。

1. 前提確認: current repo が clone 済み・ハーネス（本ファイルと同階層の `SKILL.md`）が読める。
   **L2 を回すなら追加で、`Task`（サブエージェント起動）が使えること**。
   **どれか欠ければ何も実装せず ESCALATE（人間へ報告）して終了**。
   ただし**司法を呼べないだけなら L1（報告のみ）は続行してよい**＝報告に司法は要らない。
   前提確認でここを止めると報告すら出ないので、L1 を巻き添えにしないこと。
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
   - **解決した spec の `autonomy`（省略＝L1）を見て分岐**:
     - **L1（既定・報告のみ）**: その spec の 完了基準／スコープ／検証サーフェス／ESCALATE 候補／
       既存 PR の有無／「L2 昇格時の実装プラン」を**報告するだけ**。実装・ブランチ・司法・PR・
       **ラベルの変更**は一切しない（読むだけ）。
     - **L2**: 未 PR の候補を issue 番号昇順で**最古1件**だけ選び G1〜G5 を実行。
       着手時に issue へ **`loop-running`** を付け（ロック取得）、G5 完了時に外す。
       G3↔G4 のラウンドは**セッション内カウンタ**で数え、**N=3 を超えたらロールバック/ESCALATE**
       （回数は永続化しない）。
       判定は必ず**分離した司法を Task で起動**して出させる（自己採点しない）。呼び方は環境で分ける:
       - **`review-judge:judge` が `subagent_type` に居るなら**それを `model: opus` で起動する。
       - **居ないなら**（cloud はこちら）、clone した
         `/tmp/harness/plugins/review-judge/agents/judge.md` を**手順書として汎用サブエージェントに
         読ませる**。`subagent_type` は **`Explore` を第一候補**とし、`model: opus` を明示する。
         prompt は「このファイルを Read し、そこに書かれた判事としてふるまい、以下の証拠に照らして
         PASS/REJECT/RETRY/ESCALATE を出せ」＋証拠一式。
         `Explore` を選ぶのは**読み取り専用（Edit / Write を持たない）だから**で、
         「司法はコードを書かない」を指示ではなくツールレベルで担保できる
         （`judge.md` の frontmatter も `tools: Read, Grep, Glob, Bash`）。
         `Explore` の探索向けペルソナが判定の邪魔をするなら `general-purpose` に落とす。
         ただしその場合、**書き込みを防ぐのは指示だけになる**ことを判定コメントに明記すること。
       - **`Task` 自体が使えない環境なら PR を作らず ESCALATE**（自己採点に退化させない）。

       > 検証状況（2026-09-22）: cloud で `general-purpose` + `model: opus` の起動と
       > `judge.md` の読み込みまでは**実測で確認済み**。`Explore` を判事として使えるかは**未検証**。

       PASS で `runs/<slug>/<run-id>/` に as-built を記録し `gh pr create` →
       judgments を `gh pr comment` で添付。
4. **L2 は G6 手前で必ず停止する。`gh pr merge` は実行しない**（自動マージ runtime=Phase 3.1 は未出荷）。
   人間が PR をレビューしてマージする＝HOTL。
5. **state rot 防止**: 終了時に `gh issue list --label loop-escalated` を全て再掲し、ラベル付与から
   **3 日超**のものは `stale＝人間対応を要求` として報告に浮上させる（報告が人間の inbox）。
6. **stale ロックの検出**: `loop-running` が **6 時間**を超えて付いたままの issue は、発火が途中で
   死んだ疑いがある。**`loop-escalated` を追加して報告する（`loop-running` は外さず、ロックも
   取り直さない）**。自動再開は、落ちた原因が残っている場合や死んだ実行がブランチ／PR を
   作りかけている場合に二重作業になるため。報告には `loop/<issue番号>-*` ブランチの有無と
   最終コミット時刻・`Closes #N` の open PR の有無・経過時間を含める。
   **ラベルを外せるのは G5 正常完了時のループと人間だけ**＝再投入は人間が両方のラベルを外して行う。

ガードレール（厳守・L2 のとき）:
- security・課金・破壊的変更・認証認可・spec 矛盾に触れる spec は **G1 で ESCALATE**（着手しない）。
- 司法 PASS 無しに PR を作らない。G3↔G4 は **N=3 ラウンド上限**、超過は ロールバック/ESCALATE。
- **1 発火で扱う L2 は最大1 spec**（opus 司法が毎ラウンド走るためコストを抑える）。
- current repo の `goals/` は書き換えない（SSOT は人間所有。出力は派生 `./.claude/loop/` と
  issue のラベル・コメントに書く）。

## 発火プロンプト本文（ここまで）

## 運用メモ

- **cadence**: L1 は副作用ゼロなので短めでも可。L2 を含む spec があるときは opus 司法コストを意識する。
  routine の最小間隔は1時間。
- **対象 repo**: routine に設定したリポジトリ。プロジェクトごとに routine を作る。
- **昇格パス**: 信頼できた spec を `autonomy: L2` に。
- **実行履歴**: 各 run は cloud session として残るので、`/schedule list` や
  `claude.ai/code/routines` から結果を辿れる。`_last_run` のようなファイルは持たない。
- **ラベルの棚卸し**: `loop-escalated` が溜まるのは人間の対応が滞っているサイン。
  ループ側では自動で外さない。
