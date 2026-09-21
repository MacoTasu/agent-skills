# 自律ゲート・モデル（autonomy gates）

> 自律ループ（`/loop-engine:loop-engine`）と司法（`review-judge:judge`）が**直接 Read する参照**。
> ユーザー強調点「"条件" を明確に定義する」を満たす、各段階の通過条件＝ゲート G1〜G6。
> HOTL（Human on the Loop）= 人間はループの外から監督。ここの条件が暴走の歯止め。

## SSOT / 派生 / ハーネスの境界（最重要原則）

- **SSOT（立法）** … 人間が書いて承認（main マージ）した正典。**ボットは書き換えない**。
  軸＝「作るもの」か「守るもの」で2種に分ける:
  - **`goals/`（ゴール・作るもの）** … 変更ユニット。**`/loop-engine:loop-engine` のトリガ対象**（buildable）。
    **`status: active` のものだけ G1 が拾う**（done/example は拾わない）。
  - **`rules/`（規範・守るもの）** … 開発フロー/規約/ドメインルール。**トリガ対象外**。
    司法・`/conductor:dev` が参照し enforcement（deck の Authority Provenance）。
  - 雛形はハーネス同梱 `${CLAUDE_PLUGIN_ROOT}/skills/loop-engine/reference/{SPEC,RULE}.template.md`。更新は人間の spec/rule PR。版管理は git。
- **派生 = `./.claude/loop/`** … ボットが書く。判定ログ `judgments.md`・as-built `runs/<slug>/<run-id>/`。
- **ハーネス = `.claude/`** … 判事・本ゲート・検証カタログ・loop-engine（汎用・dotfiles で配布）。

## ループの状態は GitHub に置く（ファイルに持たない）

ループの動的状態は**リポジトリ内のファイルではなく GitHub の issue** が持つ。
cloud routine は毎回まっさらな clone から始まるため、ワーキングツリーに書いた状態は次の発火に残らない。
また、状態をファイルに持つとボットが main に書き込む必要が生じ、ボットの push 権限を
PR ブランチだけに絞れなくなる。

| 状態 | 表現 | 誰が付けるか |
|---|---|---|
| 着手してよい（GO） | issue に **`loop-ready`** ラベル | **人間**（昇格プロトコル④） |
| ループが着手中（ロック） | issue に **`loop-running`** ラベル | ループ（G1 通過時に付け、G5 完了時に外す） |
| 人間の対応待ち | issue に **`loop-escalated`** ラベル | ループ（ESCALATE 時） |
| PR 作成済み・merge 待ち | **`Closes #N` を持つ open PR の有無**で導出 | — （ラベルを持たない） |
| 試行回数（N=3 判定） | **セッション内のカウンタ**（永続化しない） | ループ |

- **`Watching` にラベルを与えない**のは、PR の存在が既に GitHub 上の事実であり、
  ラベルで二重に持つと必ずズレるため（単一の真実源）。
- **試行回数は永続化しない**。1回の発火が終わると、その issue はどの経路でも走査から除外される
  （3ラウンド使い切り＝`loop-escalated` ／ PR 作成＝`Closes #N` の open PR が存在 ／ 途中終了＝
  `loop-running` が残る）。次の発火で拾い直さない以上、前回の回数を持ち越す相手がいない。
  N=3 はセッション内のカウンタで足りる。
- **`loop-escalated` は自動で外さない**（人間の対応が要る）。代わりに毎発火で `loop-escalated` の
  付いた issue を全て報告に再掲し、ラベル付与から **3 日超**のものは `stale＝人間対応を要求`として
  浮上させる（付与時刻は GitHub のタイムラインから取る）。
- **ラベルを外せるのは、G5 正常完了時のループと、人間だけ**。これが唯一のルール。
  ループが `loop-running` を外すのは G5 を正常に完了したときに限る。それ以外の経路
  （ESCALATE・途中終了・stale 検出）でループがラベルを外すことはない。
- **stale ロック（発火が途中で死んだ場合）**: `loop-running` が付いたまま実行が終わると、
  その issue は走査から除外され続け、**静かに止まる**。`loop-running` の付与から **6 時間**を超えた
  ものは stale と見なし、**`loop-escalated` を追加して報告する**（`loop-running` は外さない）。
  **ループはロックを取り直さない** — 落ちた原因が残っている可能性があり、死んだ実行が
  ブランチや PR を作りかけていれば自動再開は二重作業になるため。再投入は人間が両方のラベルを
  外して行う。報告には後始末の材料として、**`loop/<issue番号>-*` ブランチの有無と最終コミット時刻・
  `Closes #N` の open PR の有無・ロック付与からの経過時間**を含める。
  閾値を 6 時間と長めに取るのは、正常に走っている実行を誤って stale 判定しないため
  （L2 は1発火1spec なので、6 時間走り続けていること自体が異常）。誤判定しても破壊的な操作は
  行わず、ラベルの追加と報告にとどまる。

## ゲート定義

| ゲート | 判定 | 通過条件 | 不通過 | runtime |
|---|---|---|---|---|
| **G1 トリガ** | 無人着手してよいか | `./goals/<slug>.md`（**`status: active`** のみ・rules/ は対象外）の**新規 or 更新が main にマージ済み**／`auto` 印あり／スコープが閾値以下／**security・課金・破壊的変更でない**。**対象 issue に `loop-running` が付いていないこと**（付いていれば別の発火が処理中＝スキップ）。**`loop-budget` が予算内**（exit<20。80%↑＝exit10 は新規 L2 を見送り・L1 報告は許容） | ESCALATE（人間へ）または no-op | 3.0 手動 / 3.2 autonomous-entry（cron） |
| **G2 立法** | SSOT が実装可能か | 変更ユニット(`./goals/`)に **完了基準＋検証方法＋検証サーフェス**が揃う＋**関係する製品仕様 `docs/specs/`（`product_spec`）を Read し矛盾が無い**（issue は使わない）。セッション内の試行カウンタをインクリメント（永続化しない） | 曖昧/欠落/**製品仕様と矛盾**は ESCALATE | 3.0 |
| **G3 実装** | — | driver が **Task で直接実装**（公式 feature-dev は無人駆動不可のため）。差分はスコープ内・ブランチ分離。**挙動を変えたら製品仕様 `docs/specs/<feature>.md` を新挙動に reconcile（同 PR に含める）**。更新時は差分リコンサイル＋全基準を満たす。**issue に `loop-running` ラベルを付与**（ロック取得） | スコープ逸脱で停止 | 3.0 |
| **G4 司法** | 緑か | **`review-judge:judge` PASS**（決定性緑＋サーフェス充足＋セマンティックOK＋**挙動変更なら製品仕様 reconcile 済み**）。spec パスを渡す。**セッション内カウンタが N=3 超なら司法を呼ばずロールバック/ESCALATE** | RETRY/REJECT→G3 へ（**reconcile 不足は RETRY**）。N=3 超で ロールバック/ESCALATE | 3.0 |
| **G5 PR＋as-built** | PR 化してよいか | G4 PASS ＋ **as-built/決定を `./.claude/loop/runs/<slug>/<run-id>/` に版ごと履歴で残す**（上書きせず spec の git ref を記録）＋ `gh pr create` ＋ **judgments を `gh pr comment` で添付（恒久シンク B）**。**issue から `loop-running` ラベルを外す**（以後は open PR の存在が Watching を表す）。**`.claude/loop/run-log.md` に実行サマリを追記**（run_id / slug / outcome / findings / actions / token_estimate） | 停止 | 3.0 |
| **G6 マージ** | 自動マージしてよいか | 司法 PASS ＋ **CI 緑** ＋ コンフリクトなし ＋ **`auto-merge` ラベル**（opt-in）＋ 影響度しきい値以下。**merge で `Closes #N` により issue が close ＝ Done** | 未充足は **PR で停止（人間がマージ）** | **定義のみ・runtime=3.1 はスキップ中。常に PR 停止** |

## 絶対に無人化しない（常に ESCALATE）

次に触れる場合、条件を満たしても**自動で進めない**。必ず人間へ：

- security（認証/認可/秘匿情報/入力検証）
- 課金・決済・コスト発生
- 本番データの破壊的変更・不可逆マイグレーション
- spec 自体の矛盾・欠落
- ガードレール（spec の制約節）への抵触

## 停止条件・コスト

- **N=3 ラウンド上限**（G3↔G4）。超過でロールバック or ESCALATE。無限ループを作らない。
- 司法（`review-judge:judge`）は **opus** を毎ラウンド回す＝コストが効く。頻度（Phase 3.2 の Routines）と
  N の設計でコストを抑える。
- **日次予算キャップ（`loop-budget`）**: autonomous-entry の G1 で `loop-budget` を実行し、当日の
  Claude Code 総コスト（`ccusage` 由来・全プロジェクト合算）を日次キャップと照合する。
  `LOOP_DAILY_BUDGET_USD`（既定 $20）で上書き可。**80%↑で新規 L2 を見送り（exit 10）・100% 超で full no-op（exit 20）**。
  ループは後回し可能な低優先の消費者なので、総額が高い日は自律ループを絞る。価格表は `ccusage` に委譲（DRY）。
  ccusage 不在なら予算チェックをスキップ（exit 0＝ループは止めない＝移植性優先）。
- PASS が PR 自動作成（さらに G6 で自動マージ）に繋がるため、**迷ったら PASS せず ESCALATE/RETRY**（安全側）。

## 自律レベル（autonomy）— 必ず L1 から

spec frontmatter `autonomy: L1|L2`（**省略＝L1**）で、ループがどこまで無人で進むかを **spec ごと**に制御。
記事 Loop Engineering の安全シーケンス「いきなり L3 にしない・必ず L1 から」を採用。

| レベル | ループの到達点 | 停止点 | 既定 |
|---|---|---|---|
| **L1** | active spec を検知し **報告のみ**（完了基準/スコープ/サーフェス/ESCALATE候補/既存PR/実装プラン） | **G3 手前**（実装しない＝副作用ゼロ・opus 不使用） | ✅ 既定 |
| **L2** | 実装→分離司法→PR | **G6 手前**（人間が merge＝HOTL） | per-spec opt-in |
| **L3** | ＋自動マージ | — | **閉鎖**（=3.1・未出荷） |

信頼できた spec だけ `autonomy: L2` に昇格する。intake（loop か /conductor:dev か）と autonomy（L1 か L2 か）の
**2ダイヤル**は同梱の `loop-intake-triage.md` が正典。

## フェーズ境界

- 3.0（実装済）: G1〜G5 を**ローカル手動 `/loop-engine:loop-engine <slug>`** で。**G6 手前で停止**。
  実走実証済み（PR #6 `20260621-loop-readme`）。
- 3.1（**スキップ中**）: G6 自動マージ runtime（`gh pr merge`）。ブラッシュアップまで当面導入しない。
  これによりループは常に **PR で停止**＝人間が全マージをゲート（HOTL を最も安全側に保つ）。
- 3.2（**active**）: 自動発火。**発火＝手元 session の `/loop`**（または durable `CronCreate`）で
  同梱の `routine.md` を定期実行。取り込みは `/loop-engine:loop-engine` autonomous-entry 節。
  **自動走査の対象は `loop-ready` label 付きの open issue**（そこから `Spec:` コメントで解決した
  spec が実装根拠。同梱
  `loop-intake-triage.md`）。issue は**人間が番号を指定する手動起動** `/loop-engine:loop-engine <N>` の入口として
  使える（label + `Spec:` コメントで `goals/` に解決＝実装根拠は常に spec）。label 走査の自動発火は未実装。
  既定 L1（報告のみ）で始め、spec 単位で L2 解禁。
  - **発火機構の決定**:
    - claude.ai Routine（`/schedule`/RemoteTrigger cron）= **不採用**（発火が repo 外・Claude が Claude を撃つ・
      poll であって event でない）。
    - **GitHub Actions cron = 不採用（意図的・将来再考）**。CI に API 認証 secret を置く必要・コスト/security 面・
      poll≠event の同根問題。**→ 現在は Claude Code の cloud routine（schedule トリガ）を採用**（ラップトップ非依存。
      routine には「同梱の routine.md を読んで従え」のポインタだけを置き、手順は版管理下に残す）。

### hooks — プロジェクト固有の決定性 validation 層（G4 と補完）

Stop/PostToolUse hooks は**各プロジェクトの `.claude/settings.json`（commit 対象・project スコープ）**に置き、
そのプロジェクト固有の決定性チェック（go vet / tsc / pytest / 構文 等）を宣言的に差し込む拡張点。
ハーネス（loop-engine）は汎用で project 固有コマンドを持てないので、hooks がその受け皿になる。

| 層 | 主体 | 性質 | 効く範囲 |
|---|---|---|---|
| **hooks** | ハーネスが**強制**発火 | 連続・速い・機械的（project 宣言） | `/conductor:dev` も loop も |
| **G4 司法（`review-judge:judge`）** | ループの prompt が呼ぶ | 独立・重い・意味検証込み・PR の拘束判定 | loop の PR ゲート |

→ 重複ではなく**多層防御**。hooks は「`loop-engine` がバグで G4 を呼び忘れても飛ばせない」防御も兼ねる。

- **PostToolUse**（Edit|Write）= `.claude/hooks/validate.sh`: **速い**チェック（format/lint/構文）。失敗で exit 2 → Claude が直す。
- **Stop**（完了時）= `.claude/hooks/gate.sh`: フル決定性スイート。**変更検知ガード**（未コミット差分が無ければ素通り）＋
  `stop_hook_active` ガード（無限ループ防止）で `/conductor:dev` の摩擦を抑える。失敗で exit 2 → Claude は停止せず修正続行。
- 雛形＝同梱 `reference/hooks/{validate,gate}.sh.example`・配線 snippet＝`reference/hooks/settings.hooks.json`。
  `/loop-engine:init` が `.claude/hooks/` を scaffold（既定 no-op）。project が中身を書く。dogfood＝dotfiles 自身（編集 `*.sh` に `bash -n`）。
  - **L2 解禁時の TODO**: issue のラベル（着手ロック/escalated 台帳）で
    無限再試行を防止（実装済）。予算キャップは `loop-budget`（`ccusage`・日次停止・`LOOP_DAILY_BUDGET_USD`）で実装済。
    残: 常時稼働は self-hosted runner / GitHub Actions（未実装）。
