---
name: loop-engine
description: |
  自律ループのフロントドア（HOTL = Human on the Loop）。人間がマージして承認した spec-kit の仕様
  specs/<機能>/ を起点に、拾い上げ→実装→司法検証→PR を無人で回す。
  /conductor:dev（単発・human-in-loop）と並立する自律ループの入口。手動起動: /loop-engine:loop-engine <機能>
  または /loop-engine:loop-engine <issue番号>（GitHub issue 経由。label + Spec: コメントから仕様を解決）。
  進行は本 skill 同梱の reference/autonomy-gates.md のゲート G1〜G6 を正として行う。手動起動
  に加え、autonomous-entry（Claude Code の cloud routine で定期発火し、loop-ready label が付いた
  issue を走査する・手順は reference/routine.md）がある。loop-ready の issue は実装→司法→PR まで進み、
  常に G6(自動マージ)手前=PR作成で停止する（自動マージ runtime は Phase 3.1 で未出荷）。
disable-model-invocation: true
allowed-tools:
  - Task
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Skill
---

# /loop-engine:loop-engine — 自律ループのフロントドア（PR停止）

**人間が承認した仕様（SSOT）を起点に、行政（実装）⇄司法（検証）を無人で回す**入口。
`/conductor:dev` が単発・human-in-loop なのに対し、これは**自律ループ・HOTL**。自律モードでは
このスキルが指揮の席に座る。実装は行政（`dev-crew:implement` の手順）にさせ、
**判定は必ず分離した司法 `review-judge:judge` に出させる**（自己採点しない）。

> **範囲**: 手動 `/loop-engine:loop-engine <機能>` / `<issue番号>` ＋ autonomous-entry（cloud routine で定期発火・
> `loop-ready` label 付き issue を走査）。対象の仕様は G1〜G5 を回し、**G6（自動マージ）手前で停止**する。

## バケツの分離（ハーネス / 操作対象 / 出力）

- **ハーネス（汎用・本 skill に同梱）** = この skill ディレクトリの `reference/`（gates / routine / triage / hooks）。
  cwd に依存せず **skill-relative の `reference/<file>`** で読む。
- **操作対象（プロジェクト SSOT）** = **cwd の current repo** の spec-kit の成果物。
  作るもの＝`specs/<機能>/`（`spec.md` が契約、`plan.md` / `tasks.md` は派生）、
  守るもの＝`.specify/memory/constitution.md`。どちらも人間の所有物で、承認は仕様の PR のマージ。
- **出力** = PR（ブランチ・本文・司法判定のコメント）と issue のラベル・コメントだけ。
  **リポジトリのファイルに記録を残さない**。

## 正とする参照（起動時に必ず Read。すべて skill 同梱 = `reference/`）

- `reference/autonomy-gates.md` … ゲート G1〜G6 の通過条件・ESCALATE・N 上限・要注意の変更の申告。
- `reference/loop-intake-triage.md` … loop に入れるか / `/conductor:dev` か / 人間駆動かの判定。
- `reference/README.md` … 3空間モデルと **新プロジェクトで回す手順**。
- 仕様の様式は **spec-kit のテンプレート**（対象リポジトリの `.specify/templates/`）。loop-engine は書き方を教えない。
- サーフェス→要求証拠タイプのカタログと、spec-kit 契約の採点方法は **`review-judge` プラグイン側**（司法が自分で Read する）。

## 大原則（autonomy-gates と一体）

- **SSOT は人間所有**。`specs/<機能>/spec.md`・`plan.md` と constitution を**書き換えない**。
  `tasks.md` への `[X]` と `/speckit-converge` の追記は行政の作業記録として PR ブランチ上でのみ行う。
- **判定は分離した司法**（`review-judge:judge`@opus を Task 起動）。自己採点しない。
- **要注意の変更**（security・課金・破壊的変更・認証認可）も PR までは進める。ただし **PR 本文の先頭で申告する**。
- **仕様の矛盾・欠落**（`[NEEDS CLARIFICATION]` の残存、`/speckit-analyze` の重大な指摘）は**必ず ESCALATE**。
- **N=3 ラウンド上限**。超過でロールバック/ESCALATE。無限ループを作らない。
- **迷ったら PASS せず ESCALATE/RETRY**。

## 手順（`/loop-engine:loop-engine <機能>` / `/loop-engine:loop-engine <issue番号>`）

0. **引数の解決** — 数字のみなら GitHub issue 番号とみなし、下の「issue 経由の起動」で仕様のディレクトリを
   解決してから 1. へ。それ以外は `specs/<機能>/` またはディレクトリ名（`<タイムスタンプ>-<名前>`）として扱う。

1. **G1 トリガ判定** — `git fetch origin` のうえで、仕様が **`origin/main` にマージ済み**であることを確かめる:
   `git cat-file -e origin/main:specs/<機能>/spec.md` と `…/plan.md` と `…/tasks.md` がすべて成功すること。
   対象リポジトリに spec-kit が初期化されていること（`.specify/` がある）。欠ければ ESCALATE。
   あわせて仕様と想定差分が**要注意の変更**に当たるかを見立てておく（止めはしない。G5 の申告に使う）。
2. **G2 立法確認** — 仕様が実装可能かを確かめる。次のどれかなら ESCALATE:
   - `spec.md` に `[NEEDS CLARIFICATION` が残っている
   - `specs/<機能>/checklists/` に未チェックの項目がある
   - `/speckit-analyze` の報告に CRITICAL の指摘がある（読み取りのみのコマンド）
   - constitution の MUST の原則や仕様の制約と、仕様どうしが矛盾している
3. **G3 実装** — `origin/main` から作業ブランチを切る。ブランチ名は機能ディレクトリ名から先頭の
   タイムスタンプを除いた `<名前>` を使い、**issue 経由なら `loop/<issue番号>-<名前>`、直接なら `loop/<名前>`**。
   `.specify/feature.json` に `{"feature_directory":"specs/<機能>"}` を書く（gitignore されたチェックアウト専用の状態）。
   **`dev-crew:implement` の手順で実装する**（プラグインが無い cloud では clone した
   `plugins/dev-crew/skills/implement/SKILL.md` を手順書として読む。`routine.md`）。
   `tasks.md` の順にテスト先行で実装し、`/speckit-converge` で作り残しを点検する（**`/speckit-implement` は使わない**。理由は同 SKILL.md）。
   差分はスコープ内に保つ（逸脱は停止）。
4. **G4 司法** — Task で `review-judge:judge`(opus) を起動し、**契約 `specs/<機能>/`**・差分（`origin/main...HEAD`）・
   証拠（行政の決定性結果は「申告（未検証）」として）を渡す。判定を受ける:
   - `PASS` → G5 へ。
   - `RETRY`/`REJECT` → 指摘で修正し G3↔G4 を再試行（**最大 N=3**）。超過は ロールバック/ESCALATE。
   - `ESCALATE` → 停止して人間へ。
5. **G5 PR** — PASS で:
   - ① `gh pr create` で PR 作成。**PR 本文の先頭に「⚠️ 要注意の変更」節を必ず置く**
     （書式は autonomy-gates「要注意の変更」。該当が無くても「なし」と書く）。本文に `Spec: specs/<機能>/` を書く。
     **issue 経由なら `Closes #<issue番号>` を含める**。
   - ② `gh pr comment` で司法の判定出力を PR に添付（恒久の記録）。
   - ③ issue から `loop-running` を外す（以後は open PR の存在が merge 待ちを表す）。
6. **G6 手前で停止** — **マージはしない**（`gh pr merge` を実行しない）。人間が PR をレビューしてマージする。

## issue 経由の起動（`/loop-engine:loop-engine <issue番号>`）

**GitHub issue を「議論の場＋実行トリガ」として使う経路**。issue は SSOT ではない — SSOT は
あくまで `specs/<機能>/` で、**issue は仕様への発見経路（ポインタ）**にすぎない
（位置づけは同梱 `loop-intake-triage.md` の「2. issue は intake であって SSOT ではない」）。

### 前提となる人間側の昇格プロトコル

1. issue を立てて議論する（この時点では label も仕様も無い＝ただの提案・観測）。
   `/spec-intake:grill-issue [番号]` で仕様に落とせる状態まで詰められる。
2. 「やる」と決まったら **spec-kit で仕様を書いて仕様の PR → main マージ**（立法の承認）。
   `/spec-intake:spec-draft <issue番号>` で起草させてもよいし、`/conductor:dev` の親で起草してもよい。
3. その issue に **固定書式のコメント**を1件投稿する: `Spec: specs/<機能>/`
   （本文編集ではなく**コメント**＝いつ昇格したかが履歴に残る）。
4. issue に **`loop-ready` label** を付ける（＝「loop に投げてよい」の意思表示）。

### 解決手順（手順 0 の実体・すべて満たさなければ ESCALATE）

1. **label 確認** — `gh issue view <N> --json labels` に **`loop-ready` が無ければ ESCALATE**。
2. **仕様パス解決** — `gh issue view <N> --json comments` の**コメント**を固定書式でパースする（OP 本文は見ない）。
   - **書式は「行頭 `Spec:` ＋ 空白 ＋ `specs/` 配下のディレクトリ」1行**。正規表現なら
     `^\s*Spec:\s+(specs/[^/\s]+)/?\s*$`（行頭一致・前後の空白のみ許容・大文字小文字は区別する）。
     **1行として独立していない言及は拾わない**。
   - 該当が**複数あれば最新のコメントを採用**。該当が**無ければ ESCALATE**（自由形式から推測しない）。
3. **仕様の承認確認** — G1 と同じく `origin/main` に `spec.md` / `plan.md` / `tasks.md` があること。無ければ ESCALATE
   （label と仕様の状態の不整合。人間に整合させてもらう）。
4. **重複実行の防止** — その issue を閉じる PR が**既に open なら ESCALATE**。**2段構えで判定する**:
   - ① `gh issue view <N> --json closedByPullRequestsReferences -q '.closedByPullRequestsReferences[].number'`
     で、closing keyword で**実際にリンクされた PR 番号**を取る。
   - ② 各番号に `gh pr view <num> --json state -q .state` を実行し、**`OPEN` が1つでもあれば ESCALATE**。
   - **`gh pr list --search "<N>"` は使わない**（数字トークンの全文検索で無関係な PR を拾う/本命を取り逃す）。
5. 以降は**通常どおり G1〜G5**。issue 番号は G3 のブランチ名と G5 の `Closes #<N>` に引き継ぐ。

**この段階での ESCALATE の記録**: **issue に `loop-escalated` ラベルを付け、理由をコメントする**。

## autonomous-entry（定期監視・cold-start）

**Claude Code の cloud routine**（schedule トリガ）から、セッション文脈なしで定期起動されるモード。
発火プロンプトは自己完結な `reference/routine.md`。ラップトップを閉じていても回る。

1. **前提確認** — 対象 repo が checkout 済み・harness（本 skill / gates / 判事 / 行政の手順書）が存在し、
   issue を読めるか確認。欠ければ **ESCALATE/no-op で安全終了**。
2. **同期** — `git fetch origin && git checkout main && git pull --ff-only`。
3. **走査** — `gh issue list --label loop-ready --state open` で候補を集める（issue 番号昇順）。
   **`loop-running` または `loop-escalated` が付いているものは除外**。該当ゼロなら **no-op で正常終了**。
   各候補について、行頭 `Spec: specs/<機能>/` コメントから **仕様を解決する**。
   解決できない／仕様が main に無い／既に `Closes #N` の open PR がある、のいずれかなら
   **その issue は ESCALATE**（`loop-escalated` を付けて次へ）。**実装根拠は解決した仕様であって issue 本文ではない**。
4. **実行** — 解決できた候補のうち **issue 番号昇順で最古1件だけ** G1〜G5 を実行する（**G6 手前で停止**）。
   G1 通過後すぐ issue に **`loop-running`** を付け（ロック取得）、G5 完了後に外す。
   G3↔G4 のラウンドは**セッション内のカウンタ**で数え、N=3 を超えたらロールバック/ESCALATE。
5. **Escalated 再掲** — **`gh issue list --label loop-escalated` を全て報告に再掲**し、ラベル付与から
   **3 日超**のものは `stale＝人間対応を要求`として浮上させる。
   **`loop-running` が 6 時間を超えて付いたままの issue** に `loop-escalated` を追加して報告する（ロックは取り直さない）。
   報告には `loop/<issue番号>-*` ブランチの有無と最終コミット時刻・`Closes #N` の open PR の有無・経過時間を含める。
   **ラベルを外せるのは G5 正常完了時のループと人間だけ**。報告は発火の出力に書く（リポジトリのファイルに記録しない）。
6. **停止** — PR 作成で停止（**自動マージしない**）。

無人化の歯止め（autonomy-gates と一体）:
- 仕様の矛盾・欠落、constitution への抵触は G1/G2 で **ESCALATE**（着手しない）。
- 要注意の変更は進めてよいが、**PR 本文の先頭で申告**する。申告漏れは司法が RETRY にする。
- 司法 PASS 無しに PR を作らない。N=3 超で ロールバック/ESCALATE。
- **自動マージは絶対にしない**。人間が PR をマージする＝HOTL。
- Task/サブエージェント起動が使えない環境なら、PR を作らず **ESCALATE**（自己採点に退化させない）。

## アンチパターン

- 司法（`review-judge:judge`）を飛ばして PR を作る／自分で PASS 相当の結論を出す（自己採点）。
- N 上限を無視して無限に G3↔G4 を回す。
- 要注意の変更を PR 本文で申告せずに出す。
- main に直接 commit・push する（出力は PR ブランチと issue に限る）。
- **`spec.md`・`plan.md`・constitution を書き換える**（SSOT は人間所有。振る舞いの変更は先に仕様の PR）。
- **main にマージされていない仕様で実装する**（未承認の仕様は立法ではない）。
- **`/speckit-implement` で実装する**（自己採点・スコープ外の差分・無人での停止を持ち込む）。
- **`.claude/` に記録ファイルを書く**（無人実行が許可待ちで止まり、中身は PR と重複する）。
- `gh pr merge` を実行する。
- **issue 本文/コメントを仕様の代わりに実装根拠にする**（`Spec:` コメントで `specs/` に解決できなければ ESCALATE）。
- **`loop-ready` label の無い issue を実装する**（人間がまだ「やる」と決めていない）。
