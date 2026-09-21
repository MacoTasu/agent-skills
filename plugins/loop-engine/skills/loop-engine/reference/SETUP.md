# 手順書 — 新しいプロジェクトで loop-engine を回す

このファイルは「別のプロジェクトで loop-engine を立ち上げる」ための実践ランブック。
概念（3空間モデル・ゲート）は [`README.md`](README.md) / [`autonomy-gates.md`](autonomy-gates.md) を参照。
**鉄則: 必ず L1（報告のみ）から始め、信頼できた spec だけ L2 に昇格する。**

---

## 0. 前提（マシン単位・一度だけ）

新しい *プロジェクト* ごとではなく、その *マシン* で最初に一度だけ確認する。

| 確認 | コマンド | 無ければ |
|---|---|---|
| ハーネスが導入されている | `/plugin` で `loop-engine` が active | `/plugin marketplace add MacoTasu/agent-skills` → `/plugin install loop-engine@macotasu-agent-skills` |
| 行政と司法が導入されている | `/plugin` で `dev-crew` と `review-judge` が active | `/plugin install dev-crew@macotasu-agent-skills` / `review-judge@macotasu-agent-skills`（**loop-engine は単体では動かない**） |
| 予算ゲート用 ccusage（任意・推奨） | `command -v ccusage` | `brew install ccusage` |

> **ハーネスの更新 = `/plugin marketplace update macotasu-agent-skills` → `/plugin update`**。
> スクリプトもテンプレートもプラグインに同梱されているので、**PATH 登録も symlink も不要**。
> ライブが古いと感じたら、まず marketplace の update を疑う（最頻の落とし穴）。

---

## 1. `/loop-engine:init` を実行（プロジェクト root で）

```
/loop-engine:init
```

スラッシュコマンドを使わずに直接叩いてもよい:

```bash
cd /path/to/your-project
bash "${CLAUDE_PLUGIN_ROOT}/scripts/loop-init"
```

これ一発で揃うもの:
- `goals/` … 変更ユニット（spec）置き場
- `.claude/hooks/{validate,gate}.sh` … project 固有 validation の雛形（既定 no-op）
- `.claude/settings.json` … hooks 配線（PostToolUse=validate / Stop=gate）を自動追記（既存は壊さず jq マージ）
- `.gitignore` に `.claude/loop/judgments.md` を追記

`loop-init` は **言語を検出**（root＋backend/frontend/api/server/app/web）して、その言語向けの
validation コマンドを提案する。冪等なので何度実行しても安全。

---

## 2. hooks に project 固有の検証を書く

`init` の提案に従い `.claude/hooks/` を埋める。**ハーネスはコマンドを持たない＝ここが拡張点。**

- `validate.sh`（PostToolUse・**速い**）: 編集ファイルの format / lint / 構文（例: `gofmt -l`、`tsc --noEmit`）。
- `gate.sh`（Stop・**フル**）: build / test。**変更検知ガード＋`stop_hook_active` ガード**は雛形に内蔵済み
  （未コミット変更が無ければ素通り＝調査だけの対話では走らない）。

> **既存の lint/test/build hook があれば再利用する（DRY）**。例: 既にプッシュ前チェックのスクリプトがあるなら、その
> 正コマンド（`go build -tags integration` / `tsc -p tsconfig.app.json`）を `gate.sh` に流用した。
> 失敗時は `exit 2` ＋ stderr に理由（Claude が受け取って直す）。

hooks は G4 司法（review-judge:judge）と**重複ではなく多層防御**（hooks=連続・強制／G4=PR の拘束判定）。

---

## 3. 製品仕様（anchor）を決める

「機能が**今どう振る舞うか**」の現在の真実を `docs/specs/<feature>/...` に置く（既に有ればそれ）。
- 挙動を変える spec は、その PR で関係する製品仕様を **reconcile（更新）**する（anchor を腐らせない）。
- 製品を持たないリポジトリ（dotfiles 等）は `docs/specs/` 不要＝reconcile は効かない。

---

## 4. 最初の spec を書く（人間が立法）

**仕様の様式と起草の支援は `spec-intake` プラグインが持つ**（loop-engine は spec を実行する
もので、書き方は教えない）。

```
/spec-intake:spec-draft <issue番号>     # issue から起草して PR にする
```

手で書くなら `spec-intake` 同梱の `SPEC.template.md` を `goals/$(date +%Y%m%d)-<slug>.md` に写す。

- frontmatter: `status: active`、`autonomy:` 省略（＝L1）。挙動を変えるなら `product_spec:` に anchor を宣言。
- **完了基準は二値で機械判定できる検証コマンドで書く**（例 `cd backend && go test ./... -run TestX`）。
- スコープ / ガードレール / 停止条件を埋める。雛形のコメントに従えばよい。
- **実装根拠は常に `goals/` の `status: active`**。issue の議論から仕様を推測して実装しない
  （issue 経由で回す場合も spec が根拠＝下の §7）。**自動走査は `loop-ready` label 付き issue を拾い、
  そこから spec に解決する**（label は intake のキュー、spec が法）。

---

## 5. L1 ドライラン（報告のみ・副作用ゼロ）

そのプロジェクトの Claude session で:

```
/loop-engine:loop-engine <slug>
```

L1 は **実装・ブランチ・司法・PR を一切しない**。完了基準/スコープ/検証サーフェス/ESCALATE 候補/
既存 PR/製品仕様との整合/「L2 昇格時の実装プラン」を**報告するだけ**。

ここで確認すること:
- ループが spec とゲートを正しく読めるか。
- **その spec が既に満たされていないか**（L1 が「実は done」を実装前に検出する＝最大の価値）。
- 満たされていたら spec を `status: done` に倒して終わり（実装しない）。

---

## 6. L2 に昇格して自走させる

L1 で問題なければ spec frontmatter を `autonomy: L2` に変更し、再度:

```
/loop-engine:loop-engine <slug>
```

L2 は **実装 → 分離司法（review-judge:judge@opus）→ PR** まで自走し、**G6（自動マージ）手前で必ず停止**する。
人間が PR をレビューしてマージ（HOTL）。`gh pr merge` は自動では絶対にしない。

- N=3 ラウンド上限（実装↔司法）。超過でロールバック/ESCALATE。
- security・課金・破壊的変更・認証認可・spec 矛盾は**必ず ESCALATE**（無人化禁止）。
- 日次予算 `loop-budget`（`LOOP_DAILY_BUDGET_USD` 既定 $20）が 80% で新規 L2 を見送り。

### 定期監視（任意）

そのプロジェクトの session で `/loop 30m`（発火本文＝[`routine.md`](routine.md)）。起きている間、
`status: active` を定期的に拾って L1 報告 / L2 実装する。session 依存（laptop が起きている間だけ）。

---

## 7. GitHub issue 経由で回す（任意・議論を issue に残したいとき）

「課題を issue で議論し、やると決めた時点で spec に落として loop に投げる」運用。
**実装根拠は変わらず `goals/`**。issue は spec を指すポインタ＋「投げてよい」の意思表示。

### プロジェクト側の一度きりの準備

```bash
gh label create loop-ready -d "spec 承認済み。/loop-engine:loop-engine <issue番号> で実行してよい" -c 0E8A16
```

issue テンプレート（`.github/ISSUE_TEMPLATE/*.yml`）を置くなら、**spec パス欄は作らない**
（起票時点では spec はまだ存在しない＝議論の起点）。課題・背景と提案だけの軽量な形にする。

### 毎回の流れ

| # | 誰 | やること |
|---|---|---|
| 1 | 人間（**`/spec-intake:grill-issue`**） | issue を立てて議論する（label も spec もまだ無い）。`/spec-intake:grill-issue [番号]` で質問攻めにして spec に落とせる状態まで詰められる（引数なしなら起票前から詰めて最後に作成） |
| 2 | 人間 or **`/spec-intake:spec-draft <N>`** | 「fix する」と決めたら `goals/YYYYMMDD-slug.md` を書いて PR → main マージ（frontmatter に任意で `source_issue: <N>` を書いておくと逆引きできる）。`/spec-intake:spec-draft` は issue＋コードベース＋製品仕様を読んで検証コマンド付きで起草し PR にする（承認＝マージは人間。起草できない issue は拒否して `/conductor:dev` へ） |
| 3 | 人間 | その issue に固定書式コメント `Spec: goals/YYYYMMDD-slug.md` を投稿 |
| 4 | 人間 | issue に **`loop-ready`** label を付ける |
| 5 | 人間 | `/loop-engine:loop-engine <issue番号>` で起動 |
| 6 | loop | label 確認 → `Spec:` コメントから spec 解決 → G1〜G5（PR 本文に `Closes #<N>`） |
| 7 | 人間 | PR をレビューしてマージ（＝issue も自動 close） |

- 3〜4 を飛ばすと loop は **ESCALATE**（昇格していない issue を勝手に実装しない）。
- 手順 5 は手動起動の経路。**label 付き issue の自動走査は cloud routine が行う**（`reference/routine.md`）。
- L1/L2 の autonomy は**spec の frontmatter で決まる**（issue 経由でも同じ）。**必ず L1 から**。

---

## チェックリスト（要点）

- [ ] 0. ハーネス symlink・PATH・ccusage を確認（マシン一度だけ）。古ければ dotfiles を `git pull`。
- [ ] 1. `loop-init` 実行。
- [ ] 2. `.claude/hooks/{validate,gate}.sh` に project 固有チェック（既存 hook は再利用）。
- [ ] 3. 製品仕様 anchor（`docs/specs/`）の場所を決める（あれば）。
- [ ] 4. `goals/YYYYMMDD-<slug>.md` を書く（検証コマンド付き完了基準）。
- [ ] 5. **L1** で `/loop-engine:loop-engine <slug>`（報告のみ・既充足チェック）。
- [ ] 6. 信頼できたら `autonomy: L2` に昇格 → 実装→司法→PR。人間がマージ。
- [ ] 7.（任意）issue 運用するなら `loop-ready` label を作成し、軽量 issue テンプレートを置く。

## 落とし穴

- **いきなり L2 にしない**（必ず L1 から）。
- **ボットは `goals/` を書き換えない**（SSOT は人間所有。出力は `.claude/loop/`）。
- `runs/` は commit、`judgments.md` は gitignore。ループの動的状態はファイルではなく
  **GitHub の issue ラベル**（`loop-ready` / `loop-running` / `loop-escalated`）が持つ。
- ライブハーネスが古い → dotfiles メイン checkout で `git pull`（symlink 配布）。
- `loop-init` が bare で叩けない → `bin` が PATH に無い（`~/.zshrc` の PATH 追記）。
- 既存の hook と二重検証にしない（reconcile して再利用）。
