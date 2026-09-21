---
name: loop-engine
description: |
  自律ループのフロントドア（HOTL = Human on the Loop）。リポジトリ内の仕様
  ./goals/<slug>.md を起点に、拾い上げ→実装→司法検証→PR を無人で回す。
  /conductor:dev（単発・human-in-loop）と並立する自律ループの入口。手動起動: /loop-engine:loop-engine <slug>
  または /loop-engine:loop-engine <issue番号>（GitHub issue 経由。label + Spec: コメントから spec を解決）。
  進行は本 skill 同梱の reference/autonomy-gates.md のゲート G1〜G6 を正として行う。手動 /loop-engine:loop-engine <slug>
  に加え、autonomous-entry（Claude Code の cloud routine で定期発火し、loop-ready label が付いた
  issue を走査する・手順は reference/routine.md）がある。自律は spec の autonomy: L1|L2（省略=L1=報告のみ）で spec ごとに制御。L2 でも G6(自動マージ)
  手前=PR作成で停止する（自動マージ runtime は Phase 3.1 で未出荷）。
disable-model-invocation: true
allowed-tools:
  - Task
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
  - Write
---

# /loop-engine:loop-engine — 自律ループのフロントドア（雛形・PR停止）

**人間が書いた仕様（SSOT）を起点に、行政（実装）⇄司法（検証）を無人で回す**入口。
`/conductor:dev` が単発・human-in-loop なのに対し、これは**自律ループ・HOTL**。コードは自分でも書くが、
**判定は必ず分離した司法 `review-judge:judge` に出させる**（自己採点しない）。

> **範囲**: 手動 `/loop-engine:loop-engine <slug>` ＋ autonomous-entry（cloud routine で定期発火・`loop-ready` label 付き issue を走査）。
> **既定は L1（報告のみ・副作用なし）**。`autonomy: L2` の spec だけ G1〜G5 を回し
> **G6（自動マージ）手前で停止**する。**自動マージ runtime（3.1）は未出荷**。

## バケツの分離（ハーネス / 操作対象 / 派生）

このループは **「定義＝dotfiles のハーネス／実行＝任意のプロジェクト」**。3つを混同しない:

- **ハーネス（汎用・本 skill に同梱）** = この skill ディレクトリの `reference/`（gates / surfaces /
  routine / templates / triage）。プラグインとして配布され、全プロジェクトで使える。
  cwd に依存せず **skill-relative の `reference/<file>`** で読む。
- **操作対象（プロジェクト SSOT）** = **cwd の current repo** の `./goals/*.md`（人間所有）。
- **派生（出力）** = current repo の `./.claude/loop/runs/`（as-built・commit）・`./.claude/loop/judgments.md`
  （判定ログ・gitignore）。

## 正とする参照（起動時に必ず Read。すべて skill 同梱 = `reference/`）

- `reference/autonomy-gates.md` … ゲート G1〜G6 の通過条件・自律レベル・ESCALATE・N 上限・無人化禁止。
- サーフェス→要求証拠タイプのカタログは **`review-judge` プラグイン側**（判事と同梱）。
  司法が自分で Read するので、ここから渡す必要はない。
- `reference/loop-intake-triage.md` … intake×autonomy の2ダイヤル。
- `reference/RULE.template.md` … 規範の形式。仕様の様式は `spec-intake` プラグイン同梱の `SPEC.template.md`。
- `reference/README.md` … 3空間モデルと **新プロジェクトで回す手順**。

## 大原則（CLAUDE.md / autonomy-gates と一体）

- **SSOT は人間所有**。current repo の `./goals/` を**書き換えない**。出力は派生＝`./.claude/loop/` に書く。
- **判定は分離した司法**（`review-judge:judge`@opus を Task 起動）。`/loop-engine:loop-engine` は自己採点しない。
- **無人化禁止対象**（security・課金・破壊的変更・認証認可・spec 矛盾）は**必ず ESCALATE**。
- **N=3 ラウンド上限**。超過でロールバック/ESCALATE。無限ループを作らない。
- **迷ったら PASS せず ESCALATE/RETRY**（PASS が PR→（将来）自動マージに繋がるため安全側）。

## 手順（`/loop-engine:loop-engine <slug>` / `/loop-engine:loop-engine <issue番号>`）

0. **引数の解決（issue 番号が渡されたときだけ）** — 引数が数字のみなら GitHub issue 番号とみなし、
   下の「issue 経由の起動」節に従って **slug を解決**してから 1. へ進む。引数が slug ならこの手順は不要。

1. **G1 トリガ判定** — `./goals/<slug>.md` を Read。無ければ停止。autonomy-gates の G1 条件
   （`auto` 印・スコープ・**security/課金/破壊的でない**）を判定。外れたら ESCALATE で人間へ。
2. **G2 立法確認** — 変更ユニット spec を読み、完了基準＋検証方法＋検証サーフェスが揃うか確認。
   **`product_spec` に挙げた製品仕様 `docs/specs/<feature>.md` を Read し、矛盾が無いか確認**
   （矛盾は "spec 矛盾"＝ESCALATE）。欠落/曖昧も ESCALATE。更新時は現状実装との差分を把握。
3. **G3 実装** — ブランチ分離の上、spec どおり実装（直接 or Task サブエージェント）。
   ブランチ名は slug 起動なら従来どおり、**issue 経由なら `loop/<issue番号>-<kebab-desc>`**
   （loop が作ったブランチだと一目で分かるようにする）。`<kebab-desc>` は**解決した spec の slug から
   日付プレフィックスを除いた部分**を使う（例: spec `20260622-bio-too-long` ＋ issue #489
   → `loop/489-bio-too-long`）。issue タイトルからは作らない（spec が実装根拠だから）。
   **挙動を変えたら、その PR で製品仕様 `docs/specs/<feature>.md` を新挙動に reconcile（更新）する**
   （anchor を腐らせない＝Specification Provenance。製品仕様は人間が merge 承認）。
   差分はスコープ内に保つ（逸脱は停止）。
4. **G4 司法** — Task で `review-judge:judge`(opus) を起動し、**引数に spec パス `./goals/<slug>.md`**・
   差分・証拠を渡す。判定を受ける:
   - `PASS` → G5 へ。
   - `RETRY`/`REJECT` → 指摘で修正し G3↔G4 を再試行（**最大 N=3**）。超過は ロールバック/ESCALATE。
   - `ESCALATE` → 停止して人間へ。
5. **G5 PR＋as-built** — PASS で:
   - ① as-built/決定を `./.claude/loop/runs/<slug>/<run-id>/` に**版ごと履歴**で残す
     （上書きせず、対象 spec の git ref を記録）。
   - ② `gh pr create` で PR 作成。**issue 経由なら PR 本文に `Closes #<issue番号>` を含める**
     （マージで issue が自動 close＝二重管理を作らない。未マージの間は open のまま残る）。
   - ③ `gh pr comment` で司法判定（judgments）を PR に添付（恒久シンク B＝別端末からも見える）。
   - ④ G5 完了時に issue から `loop-running` を外す（以後は open PR の存在が merge 待ちを表す）
     （spec の frontmatter は書き換えない＝SSOT は人間所有のまま）。
6. **G6 手前で停止** — **マージはしない**（`gh pr merge` を実行しない）。自動マージは Phase 3.1。
   人間が PR をレビューしてマージする。

## issue 経由の起動（`/loop-engine:loop-engine <issue番号>`）

**GitHub issue を「議論の場＋実行トリガ」として使う経路**。issue は SSOT ではない — SSOT は
あくまで `./goals/<slug>.md` のままで、**issue は spec への発見経路（ポインタ）**にすぎない
（詳細な位置づけは同梱 `loop-intake-triage.md` の「2. issue は intake であって SSOT ではない」）。

### 前提となる人間側の昇格プロトコル

issue は最初から実行可能である必要はない。**議論して「やる」と決まった時点**で人間が昇格させる:

1. issue を立てて議論する（この時点では label も spec も無い＝ただの提案・観測）。
2. 「fix する」と決まったら **spec `goals/YYYYMMDD-slug.md` を書いて PR → main マージ**
   （立法の承認。`status: active`）。**`/spec-intake:spec-draft <issue番号>` で AI に起草させてもよい**
   （issue＋コードベース＋製品仕様を読み、検証コマンド付きで起草して PR にする。承認＝マージは人間。
   起草できない issue は拒否して `/conductor:dev` へ回す）。
3. その issue に **固定書式のコメント**を1件投稿する: `Spec: goals/YYYYMMDD-slug.md`
   （本文編集ではなく**コメント**＝いつ昇格したかが履歴に残る）。
4. issue に **`loop-ready` label** を付ける（＝「loop に投げてよい」の意思表示）。

### 解決手順（手順 0 の実体・すべて満たさなければ ESCALATE）

引数が数字のみなら issue 番号とみなし、次を**順に**判定する。**1つでも欠ければ実装に進まず
ESCALATE**（人間に何が足りないかを具体的に伝える）:

1. **label 確認** — `gh issue view <N> --json labels` に **`loop-ready` が無ければ ESCALATE**
   （「まだ昇格していない issue を loop が勝手に実装する」事故の防止）。
2. **spec パス解決** — `gh issue view <N> --json comments` の**コメント**を
   固定書式でパースする（**OP 本文ではなくコメントを見る**）。
   - **書式は「行頭 `Spec:` ＋ 空白 ＋ `goals/` 配下のパス」1行**。正規表現なら
     `^\s*Spec:\s+(goals/\S+\.md)\s*$`（行頭一致・前後の空白のみ許容・大文字小文字は区別する）。
     **1行として独立していない言及（文中の "Spec: ..." 等）は拾わない**＝誤検出を作らない。
   - 該当が**複数あれば最新のコメントを採用**（昇格し直した場合に後勝ちでよい）。
   - 該当が**無ければ ESCALATE**（自由形式から推測して拾わない）。
3. **spec 実在・status 確認** — 解決したパスを Read。**存在しない、または `status: active` でなければ
   ESCALATE**（issue の label と spec の status の不整合＝どちらかが古い。人間に整合させてもらう）。
   - spec に任意項目 `source_issue:` があり、**起動に使った `<N>` と食い違うなら ESCALATE**（どちらかが古い）。
   - **`source_issue:` は起動の根拠にしない**。起動の権威は 1（label）と 2（`Spec:` コメント）だけ。
     spec 側の記述で label ゲートを迂回させない（＝人間の実行意思の確認点を守る）。
4. **重複実行の防止** — その issue を閉じる PR が**既に open なら ESCALATE**（二重ブランチ・二重 PR を
   作らない）。**2段構えで判定する**:
   - ① `gh issue view <N> --json closedByPullRequestsReferences -q '.closedByPullRequestsReferences[].number'`
     で、closing keyword（`Closes #<N>` 等）で**実際にリンクされた PR 番号**を取る。
   - ② 得られた各番号に `gh pr view <num> --json state -q .state` を実行し、**`OPEN` が1つでもあれば ESCALATE**
     （`MERGED`/`CLOSED` だけなら続行してよい）。①のフィールドは `state` を返さないため②が要る。
   - **`gh pr list --search "<N>"` は使わない**。番号を全文検索の数字トークンとして雑にマッチするため、
     無関係な PR を拾う（誤 ESCALATE）／本命を取り逃す（二重 PR）双方の事故を起こす。
5. 以降は**通常どおり G1〜G5**。issue 番号は G3 のブランチ名と G5 の `Closes #<N>` に引き継ぐ。

**この段階（1〜4）での ESCALATE の記録**: **issue に `loop-escalated` ラベルを付け、理由をコメントする**。
slug がまだ解決できていない段階でも issue 番号は確定しているので、記録先に困らない。
手動起動の ESCALATE も同じようにラベルを付ける＝routine の「毎発火で再掲・3日超は stale」に乗り、
ターミナル出力だけで消えない（state rot 防止）。

> **スコープ（現時点）**: **人間が issue 番号を指定する手動起動のみ**。`loop-ready` label が付いた
> issue を**自動で走査する（ポーリング / routine 化）のは未実装＝将来**。autonomous-entry が自動で
> 拾う対象は引き続き `goals/` の `status: active` だけ（下記）。
> label 名は当面 `loop-ready` 固定（プロジェクトごとの設定機構は需要が出るまで作らない＝YAGNI）。
>
> **見直しトリガー（"需要が出たら" の判定基準）**: 次のどれかを観測したら自動化を検討する。
> 漠然と「そのうち」にせず、これを満たすまでは手動のままでよい:
> - 昇格（手順 3〜4）を **月に5件以上**行っている＝手作業のコストが積み上がっている。
> - 手順 3 または 4 の**失念による ESCALATE が繰り返し**起きる＝人間の記憶に依存しすぎている。
> - `loop-ready` を付けてから起動するまでの**放置が常態化**している＝自動走査の価値が出ている。

## autonomous-entry（定期監視・cold-start）

**手元の Claude session の `/loop <interval>`**（または durable `CronCreate`）から、セッション文脈なしで
定期起動されるモード。引数 slug を取らず、自分で対象 spec を選ぶ。発火プロンプトは自己完結な
`reference/routine.md`。session が起きている間だけ回る（laptop 依存。常時稼働は将来の課題）。

> **自律レベル（autonomy）**: spec frontmatter の `autonomy: L1|L2`（**省略時＝L1**）で、ループが
> どこまで無人で進むかを **spec ごと**に決める。既定は L1（報告のみ）。記事の安全シーケンス
> 「必ず L1 から」に従い、信頼できた spec だけ `autonomy: L2` に昇格させる。詳細は
> [[loop-intake-triage]] の「2ダイヤル」、各レベルの停止点は `reference/autonomy-gates.md`。

1. **前提確認** — 対象 repo（dotfiles）が checkout 済み・harness（本 skill / gates / `review-judge:judge`）が
   存在するか確認。L2 を回すなら追加で `gh` 認証も確認。欠ければ **ESCALATE/no-op で安全終了**。
2. **同期** — `git fetch origin && git checkout main && git pull --ff-only`。
3. **予算ゲート** — `${CLAUDE_PLUGIN_ROOT}/scripts/loop-budget` を実行する（当日の CC 総コストを `ccusage` で取得し日次キャップと照合）。
   **exit 20（100% 超）なら full no-op で終了**。exit 10（80%↑）なら**新規 L2 を見送り**（L1 報告のみ続行）。
   ccusage 不在（exit 0・警告）なら予算チェックをスキップしてループは止めない。
4. **走査** — `gh issue list --label loop-ready --state open` で候補を集める（issue 番号昇順＝時系列）。
   **`loop-running` または `loop-escalated` が付いているものは除外**（前者は処理中、後者は人間待ち）。
   該当ゼロなら **no-op で正常終了**。
   各候補について、行頭 `Spec: goals/YYYYMMDD-slug.md` コメントから **spec を解決する**。
   解決できない／spec が `status: active` でない／既に `Closes #N` の open PR がある、のいずれかなら
   **その issue は ESCALATE**（`loop-escalated` を付けて次へ）。
   **実装根拠は解決した spec であって issue 本文ではない**（[[loop-intake-triage]]）。
6. **レベル分岐（spec ごと）** — 各 active spec の `autonomy` を見る:
   - **L1（既定・報告のみ）**: その spec の 完了基準／スコープ／検証サーフェス／ESCALATE 候補
     （security・課金・破壊的 等）／既存 PR の有無／**関係する製品仕様 `docs/specs/`（`product_spec`）との
     整合・reconcile が要りそうな箇所**／「L2 昇格時の実装プラン」を**報告するだけ**。
     **実装・ブランチ・司法・PR は一切しない＝副作用ゼロ・opus 不使用**（製品仕様も読むだけ・書かない）。
     **副作用はラベルを触らないこと**（L1 は読むだけ）。報告は issue にコメントせず、発火の出力に書く。
   - **L2**: 下の「手順」G1〜G5 を実行（実装→分離司法→PR、**G6 手前で停止**）。**未 PR の L2 候補を
     issue 番号昇順で最古1件だけ**扱う（1 発火 1 spec＝コスト・レビュー負荷を抑える）。
     G1 通過後すぐ issue に **`loop-running`** を付け（ロック取得）、G5 完了後に外す。
     G3↔G4 のラウンドは**セッション内のカウンタ**で数え、N=3 を超えたらロールバック/ESCALATE
     （回数は永続化しない。次の発火でこの issue は除外されるため持ち越す相手がいない）。
7. **run-log 記録＋Escalated 再掲** — 発火の結果（outcome / findings / actions / escalations / token_estimate）を
   `.claude/loop/run-log.md` に**追記**する（上書きしない。commit 対象なので PR に含める）。
   テンプレートは同梱 `reference/RUN-LOG.template.md`。L1・L2 問わず毎回書く。あわせて
   **`gh issue list --label loop-escalated` を全て報告に再掲**し、ラベル付与から **3 日超**のものは
   `stale＝人間対応を要求`として浮上させる（付与時刻は `gh issue view --json timelineItems` 等で取る）。
   あわせて **`loop-running` が 6 時間を超えて付いたままの issue**（＝発火が途中で死んだ疑い）に
   `loop-escalated` を追加して報告する。**ロックは取り直さない**（自動再開は二重作業になりうる）。
   報告には `loop/<issue番号>-*` ブランチの有無と最終コミット時刻・`Closes #N` の open PR の有無・
   ロック付与からの経過時間を含める。**ラベルを外せるのは G5 正常完了時のループと人間だけ**。
8. **停止** — L1 は報告で終わり。L2 は PR 作成で停止（**自動マージしない**＝3.1 未出荷・HOTL）。

無人化の歯止め（autonomy-gates と一体・L2 のとき）:
- security・課金・破壊的・認証認可・spec 矛盾に触れる spec は G1 で **ESCALATE**（着手しない）。
- 司法 PASS 無しに PR を作らない。N=3 超で ロールバック/ESCALATE。
- **自動マージは絶対にしない**（3.1 未出荷）。人間が PR をマージする＝HOTL。
- Task/サブエージェント起動が使えない環境なら、L2 でも PR を作らず **ESCALATE**（自己採点に退化させない）。

## アンチパターン

- 司法（`review-judge:judge`）を飛ばして PR を作る／自分で PASS 相当の結論を出す（自己採点）。
- N 上限を無視して無限に G3↔G4 を回す。
- ESCALATE 対象（security・課金・破壊的変更 等）を無人で進める。
- **`./goals/` を書き換える**（SSOT は人間所有。ボットは `.claude/loop/` に書く）。
- `gh pr merge` を実行する（本フェーズは PR 停止。自動マージは 3.1）。
- **issue 本文/コメントを spec の代わりに実装根拠にする**（issue は発見経路であって SSOT ではない。
  `Spec:` コメントで `goals/` に解決できなければ ESCALATE。issue の議論から仕様を推測して実装しない）。
- **`loop-ready` label の無い issue を実装する**（昇格していない＝人間がまだ「やる」と決めていない）。
