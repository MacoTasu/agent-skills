# 手順書 — 新しいプロジェクトで loop-engine を回す

このファイルは「別のプロジェクトで loop-engine を立ち上げる」ための実践ランブック。
概念（3空間モデル・ゲート）は [`README.md`](README.md) / [`autonomy-gates.md`](autonomy-gates.md) を参照。
**流れ: spec-kit で仕様を書いて仕様の PR をマージし、issue に `loop-ready` を付ければ、ループが実装→司法→PR まで
進めて PR で止まる。マージは人間。**

---

## 0. 前提（マシン単位・一度だけ）

| 確認 | コマンド | 無ければ |
|---|---|---|
| ハーネスが導入されている | `/plugin` で `loop-engine` が active | `/plugin marketplace add MacoTasu/agent-skills` → `/plugin install loop-engine@macotasu-agent-skills` |
| 行政と司法が導入されている | `/plugin` で `dev-crew` と `review-judge` が active | `/plugin install dev-crew@macotasu-agent-skills` / `review-judge@macotasu-agent-skills`（**loop-engine は単体では動かない**） |
| spec-kit の CLI がある | `specify version` | `uv tool install specify-cli`（版を固定するなら `specify-cli==<版>`） |

> **ハーネスの更新 = `/plugin marketplace update macotasu-agent-skills` → `/plugin update`**。
> ライブが古いと感じたら、まず marketplace の update を疑う（最頻の落とし穴）。

---

## 1. spec-kit を初期化する（プロジェクト root で・ブランチの上で）

```bash
git switch -c chore/speckit-init
specify init --here --force --non-interactive --integration claude --script sh
```

続けて次の2つを設定し、`.specify/` と `.claude/skills/speckit-*` をコミットする:

- **`.specify/init-options.json` の `feature_numbering` を `"timestamp"` にする** — 並行して開いた仕様の PR が
  連番を取り合わないように。
- **constitution に自動テストの原則を入れる**（`/speckit-constitution` で編集してよい）:
  「`spec.md` の各 FR と各受け入れシナリオは、それを確かめる自動テストを持たなければならない（MUST）。
  テスト名かテスト内に基準 ID（`FR-001`、`US1/AC2` など）を書いて対応を辿れるようにする」。
  spec-kit ではテストが任意なので、これが無いと司法が採点に使う証拠が作られず、毎回 RETRY になる。

> cloud の routine にはプラグインが届かないが、**リポジトリにコミットされた `.claude/skills/speckit-*` は届く**。
> だからコミットが必要。

---

## 2. `/loop-engine:init` を実行（プロジェクト root で）

```
/loop-engine:init
```

これで揃う・確認されるもの:
- spec-kit の設定の確認（`.specify/` の有無・タイムスタンプ方式・constitution）。**足りなければ案内するだけで書き換えない**
- `.claude/hooks/{validate,gate}.sh` … project 固有 validation の雛形（既定 no-op）
- `.claude/settings.json` … hooks 配線（PostToolUse=validate / Stop=gate）とプラグイン宣言を追記（既存は壊さず jq マージ）

`loop-init` は **言語を検出**して、その言語向けの validation コマンドを提案する。冪等なので何度実行しても安全。

---

## 3. hooks に project 固有の検証を書く

`init` の提案に従い `.claude/hooks/` を埋める。**ハーネスはコマンドを持たない＝ここが拡張点。**

- `validate.sh`（PostToolUse・**速い**）: 編集ファイルの format / lint / 構文（例: `gofmt -l`、`tsc --noEmit`）。
- `gate.sh`（Stop・**フル**）: build / test。**変更検知ガード＋`stop_hook_active` ガード**は雛形に内蔵済み。

> **既存の lint/test/build hook があれば再利用する（DRY）**。失敗時は `exit 2` ＋ stderr に理由（Claude が受け取って直す）。

hooks は G4 司法（review-judge:judge）と**重複ではなく多層防御**（hooks=連続・強制／G4=PR の拘束判定）。

---

## 4. 最初の仕様を書く（人間が立法）

次のどれかで spec-kit の仕様（`spec.md`・`plan.md`・`tasks.md`）を作り、**仕様の PR をマージする**:

- `/conductor:dev <作りたいもの>`（main 上の親が spec-kit の手順で起草して仕様の PR を作る）
- `/spec-intake:spec-draft <issue番号>`（issue から起草して仕様の PR を作る）
- spec-kit のコマンドを手で（`/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze`）

- `[NEEDS CLARIFICATION]` を残さない（残ればループは G2 で ESCALATE）。
- `tasks.md` にはテストのタスクを実装タスクより前に置く。
- **実装根拠は常に main にマージ済みの `specs/<機能>/`**。issue の議論から仕様を推測して実装しない。

---

## 5. 回す

そのプロジェクトの Claude session で:

```
/loop-engine:loop-engine <機能>          # specs/<機能>/ を直接指定
/loop-engine:loop-engine <issue番号>     # issue 経由（下の §6）
```

**実装 → 分離司法（review-judge:judge@opus）→ PR** まで進み、**G6（自動マージ）手前で必ず停止**する。

- N=3 ラウンド上限（実装↔司法）。超過でロールバック/ESCALATE。
- 仕様の矛盾・欠落は**必ず ESCALATE**。
- security・課金・破壊的変更・認証認可に触れる変更も PR までは進むが、**PR 本文の先頭で「⚠️ 要注意の変更」として申告**される。

### 定期監視（任意）

Claude Code の cloud routine で定期発火させる（発火本文と設定＝[`routine.md`](routine.md)）。
`loop-ready` label 付きの issue を拾い、1 発火で1件ずつ PR まで進める。

---

## 6. GitHub issue 経由で回す

### プロジェクト側の一度きりの準備

```bash
gh label create loop-ready -d "仕様承認済み。loop に投げてよい" -c 0E8A16
```

issue テンプレートを置くなら、**仕様パス欄は作らない**（起票時点では仕様はまだ存在しない）。

### 毎回の流れ

| # | 誰 | やること |
|---|---|---|
| 1 | 人間（**`/spec-intake:grill-issue`**） | issue を立てて議論する。質問攻めにして仕様に落とせる状態まで詰められる |
| 2 | 人間 / **`/spec-intake:spec-draft <N>`** / `/conductor:dev` の親 | 「やる」と決めたら spec-kit で仕様を書いて仕様の PR → main マージ |
| 3 | 人間 | その issue に固定書式コメント `Spec: specs/<機能>/` を投稿 |
| 4 | 人間 | issue に **`loop-ready`** label を付ける |
| 5 | 人間 or routine | `/loop-engine:loop-engine <issue番号>`、または cloud routine が拾う |
| 6 | loop | label 確認 → `Spec:` コメントから仕様を解決 → G1〜G5（PR 本文に `Closes #<N>`） |
| 7 | 人間 | PR をレビューしてマージ（＝issue も自動 close） |

- 3〜4 を飛ばすと loop は **ESCALATE**（昇格していない issue を勝手に実装しない）。

---

## チェックリスト（要点）

- [ ] 0. ハーネス（プラグイン）と spec-kit の CLI を確認（マシン一度だけ）。
- [ ] 1. `specify init`、タイムスタンプ方式、constitution のテスト原則、コミット。
- [ ] 2. `/loop-engine:init`。
- [ ] 3. `.claude/hooks/{validate,gate}.sh` に project 固有チェック。
- [ ] 4. 仕様を書いて仕様の PR をマージ。
- [ ] 5. `/loop-engine:loop-engine <機能>` → 実装→司法→PR。人間がマージ。
- [ ] 6.（任意）issue 運用するなら `loop-ready` label を作成。

## 落とし穴

- **要注意の変更の PR はマージ前に「⚠️ 要注意の変更」節を必ず読む**（ループは止めずに申告だけする）。
- **ボットは `spec.md`・`plan.md`・constitution を書き換えない**（SSOT は人間所有。振る舞いの変更は先に仕様の PR）。
- ボットはリポジトリに記録ファイルを書かない。ループの動的状態は **GitHub の issue ラベル**が持つ。
- constitution にテストの原則が無いと、`tasks.md` にテストが入らず、司法が毎回 RETRY する。
- 既存の hook と二重検証にしない（再利用する）。
