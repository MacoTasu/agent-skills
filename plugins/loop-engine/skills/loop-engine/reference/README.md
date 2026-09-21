# loop-engine ハーネス reference — 3空間モデルと新プロジェクト手順

`loop-engine` skill の参照物（gates / surfaces / routine / templates / triage）の置き場。
**ハーネスは汎用**で、`loop-engine` プラグインとして配布される（`/plugin install loop-engine@macotasu-agent-skills`）。
loop engineering は **dotfiles をベース定義に、各プロジェクトで current repo を対象に**回す。

## 3空間モデル（最重要）

成果物を所有者と性質で3空間に物理分離する。混ぜると「ボットが正典を書き換える」事故や監査崩壊が起きる。

| 空間 | 場所 | 所有者 | 性質 | git |
|---|---|---|---|---|
| **ハーネス（汎用）** | `loop-engine` プラグイン（本 `reference/` 含む）・判事は `review-judge:judge` | 配布物 | 判事・ゲート・検証カタログ・テンプレ・規範。全プロジェクト共通 | agent-skills で commit |
| **製品仕様（SSOT anchor）** | **各プロジェクトの** `docs/specs/<feature>/...`（既定。機能別 living） | **人間** | 「今どう振る舞うか」現在の真実＝agent のよりどころ。in-place 更新 | その repo で commit |
| **変更ユニット（goal・操作対象）** | **各プロジェクトの** `goals/<YYYYMMDD-slug>`（仕様）・`rules/`（規範） | **人間** | デルタ/タスク。実行中不可侵・done で履歴化 | その repo で commit |
| **派生（出力）** | **各プロジェクトの** `.claude/loop/runs/`（as-built）・`.claude/loop/judgments.md`（判定ログ） | ボット | SSOT に照らした結果物 | runs=commit / judgments=**gitignore** |
| **動的状態** | **GitHub の issue**（`loop-ready` / `loop-running` / `loop-escalated` ラベル） | ボット＋人間 | 着手可否・ロック・エスカレーション | GitHub が保持（ファイルに持たない） |

> **2層の区別が要**: 「製品仕様(`docs/specs`)＝anchor」と「変更ユニット(`goals/`)＝goal」は別物。
> agent のよりどころは前者。挙動を変える変更ユニットは、その PR で関係する製品仕様を **reconcile（更新）**
> すること（anchor を腐らせない）。詳細は `loop-intake-triage.md`「0. 2層」。

## reference/ のファイル

| ファイル | 役割 |
|---|---|
| `autonomy-gates.md` | 自律ゲート G1〜G6・自律レベル L1/L2/L3・ESCALATE・N=3・無人化禁止（司法が直接 Read） |
| （`verification-surfaces.md`） | 変更の接触面 → 要求する決定性証拠タイプ。**`review-judge` 側**に判事と同梱（司法が直接 Read） |
| `loop-intake-triage.md` | intake（loop/dev/人間）× autonomy（L1/L2）の2ダイヤル規範 |
| `routine.md` | cloud routine が定期実行する発火プロンプトと routine の設定手順（current repo 対象） |
| `RULE.template.md` | 規範の雛形。**仕様の雛形 `SPEC.template.md` は `spec-intake` 側**（立法の様式は立法支援が持つ） |
| `RUN-LOG.template.md` | 実行サマリの雛形（`.claude/loop/run-log.md` に追記形式で蓄積） |
| `hooks/{validate,gate}.sh.example`・`hooks/settings.hooks.json` | プロジェクト固有 validation hook の雛形＋配線 snippet（`.claude/hooks/` へ scaffold・G4 と補完） |
| `SETUP.md` | 別プロジェクトで立ち上げる実践ランブック（手順・チェックリスト・落とし穴） |

## 新しいプロジェクトで loop engineering を回す手順

> **実践ランブックは [`SETUP.md`](SETUP.md) が正典**（コマンド・チェックリスト・落とし穴つき）。
> 以下は概要。別プロジェクトで立ち上げるときは SETUP.md をそのまま辿る。

1. **製品仕様（anchor）の場所を決める**: その repo の機能仕様を **`docs/specs/<feature>/...`** に置く
   （既定。既にあるならそれを使う）。これが agent のよりどころ。loop は読む＋挙動変更時に reconcile（更新を PR に含める）。
   別パスを使うなら変更ユニットの `product_spec` で実パスを指す。
2. **変更ユニット置き場を作る**: その repo に `goals/` を作り、`spec-intake` 同梱の `SPEC.template.md` をコピーして
   `goals/YYYYMMDD-<slug>.md` を書く（人間が立法）。`status: active`、`autonomy:` 省略＝L1 から。
   挙動を変えるなら `product_spec:` に関係する `docs/specs/...` を宣言＋「製品仕様 reconcile」基準を入れる。
   **完了基準の検証コマンドはそのプロジェクト依存で書く**（go build / tsc / pytest 等）。
3. **派生の gitignore と state 初期化**: `loop-init` を実行する（`.gitignore` 更新＋`goals/` 作成）。
   （`/loop-engine:init` が自動化済み）。`judgments.md` のみ gitignore。
3.5. **hooks（プロジェクト固有 validation）**: `loop-init` が `.claude/hooks/{validate,gate}.sh`（既定 no-op）も
   scaffold する。`reference/hooks/settings.hooks.json` の snippet を `.claude/settings.json` に貼って配線し、
   `validate.sh`（PostToolUse・速い）/ `gate.sh`（Stop・フル・変更検知ガード付き）に**そのプロジェクトの決定性
   チェック**（go vet / tsc / pytest / 構文 等）を書く。G4 司法と補完する多層防御（詳細は `autonomy-gates.md`「hooks」節）。
4. **回す**: その repo の session（cwd=その repo）で `/loop <interval>` に `reference/routine.md` の発火本文を渡す。
   既定 L1 なら active spec を**報告するだけ**（副作用ゼロ）。autonomous-entry は G1 で `loop-budget`（bin/・
   `ccusage` 由来の当日 CC 総コストを日次キャップ `LOOP_DAILY_BUDGET_USD`〈既定 $20〉と照合）を実行し、
   80%↑で新規 L2 を見送り・100% 超で no-op。**`brew install ccusage` で有効化**（不在ならスキップ＝ループは止めない）。
5. **昇格**: ループが spec を正しく読めると確認できた spec だけ frontmatter を `autonomy: L2` に上げると、
   実装→分離司法→PR（G6 手前停止・人間が merge）まで進む。

> dotfiles 自身も「最初の1消費者（ドッグフード）」として同じ構造で回る（`dotfiles/goals/`）。
> dotfiles には機能仕様としての `docs/specs/` は無い（製品でないため）＝reconcile は挙動を持つ
> 製品を持つプロジェクトで効く。
