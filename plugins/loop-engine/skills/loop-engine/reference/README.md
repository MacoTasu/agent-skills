# loop-engine ハーネス reference — 3空間モデルと新プロジェクト手順

`loop-engine` skill の参照物（gates / routine / triage / hooks）の置き場。
**ハーネスは汎用**で、`loop-engine` プラグインとして配布される（`/plugin install loop-engine@macotasu-agent-skills`）。
仕様は各プロジェクトの spec-kit の成果物で、ループはそれを current repo に対して回す。

## 3空間モデル（最重要）

成果物を所有者と性質で分ける。混ぜると「ボットが正典を書き換える」事故や監査崩壊が起きる。

| 空間 | 場所 | 所有者 | 性質 | git |
|---|---|---|---|---|
| **ハーネス（汎用）** | `loop-engine` プラグイン（本 `reference/` 含む）・行政の手順は `dev-crew:implement`・判事は `review-judge:judge` | 配布物 | ゲート・手順・検証カタログ。全プロジェクト共通 | agent-skills で commit |
| **仕様（SSOT）** | **各プロジェクトの** `specs/<機能>/`（作るもの）と `.specify/memory/constitution.md`（守るもの） | **人間** | Living Spec。`spec.md` が契約。承認は仕様の PR のマージ | その repo で commit |
| **出力** | **各プロジェクトの** PR（本文・司法判定のコメント） | ボット | 仕様に照らした結果物 | ファイルには書かない |
| **動的状態** | **GitHub の issue**（`loop-ready` / `loop-running` / `loop-escalated` ラベル） | ボット＋人間 | 着手可否・ロック・エスカレーション | GitHub が保持（ファイルに持たない） |

## reference/ のファイル

| ファイル | 役割 |
|---|---|
| `autonomy-gates.md` | 自律ゲート G1〜G6・ESCALATE・N=3・要注意の変更の申告（司法が直接 Read） |
| （`verification-surfaces.md` / `contract-speckit.md`） | 要求する決定性証拠タイプと、spec-kit の仕様の採点方法。**`review-judge` 側**に判事と同梱 |
| `loop-intake-triage.md` | intake（loop/dev/人間）のトリアージ規範 |
| `routine.md` | cloud routine が定期実行する発火プロンプトと routine の設定手順（current repo 対象） |
| `hooks/{validate,gate}.sh.example`・`hooks/settings.hooks.json` | プロジェクト固有 validation hook の雛形＋配線 snippet（`.claude/hooks/` へ scaffold・G4 と補完） |
| `SETUP.md` | 別プロジェクトで立ち上げる実践ランブック（手順・チェックリスト・落とし穴） |

## 新しいプロジェクトで loop engineering を回す手順

> **実践ランブックは [`SETUP.md`](SETUP.md) が正典**。以下は概要。

1. **spec-kit を初期化する**: `specify init --here --force --non-interactive --integration claude --script sh`。
   `.specify/init-options.json` の `feature_numbering` を `"timestamp"` にし、constitution に
   「各 FR と受け入れシナリオは自動テストで検証する（MUST）」を入れる。`.specify/` と `.claude/skills/speckit-*` はコミットする
   （cloud の routine にはプラグインが届かないが、リポジトリにコミットされたスキルは届く）。
2. **初期化**: `/loop-engine:init` を実行する（spec-kit の設定の確認・hooks の scaffold・settings の配線）。
3. **hooks（プロジェクト固有 validation）**: `.claude/hooks/{validate,gate}.sh` にそのプロジェクトの決定性チェックを書く。
4. **最初の仕様を書く**: `/conductor:dev` の親、または `/spec-intake:spec-draft <issue番号>` で spec-kit の仕様を起草し、
   仕様の PR をマージする（人間が立法）。
5. **回す**: issue に `Spec: specs/<機能>/` と `loop-ready` を付け、手動 `/loop-engine:loop-engine <N>` か
   cloud routine（`routine.md`）で、実装→分離司法→PR（G6 手前停止・人間が merge）まで進める。
