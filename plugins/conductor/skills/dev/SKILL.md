---
name: dev
description: |
  開発作業の単一フロントドア(オーケストレータ)。実装・レビュー・コミット・PR作成・
  ドメイン設計など開発タスク全般で起動する。フェーズを判定し、公式プラグイン
  (feature-dev / pr-review-toolkit / frontend-design / commit-commands / code-simplifier)と
  カスタム職能サブエージェント(dev-crew:business-reviewer / dev-crew:domain-architect)を Task で
  並列招集・委譲する。自分でコードは書かず、指揮・判断・合意形成・並列調整に徹する。
  Plan Mode 合意必須とブランチ分離の思想を保持する。
disable-model-invocation: false
allowed-tools:
  - Task
  - Bash
  - Read
  - Grep
  - Glob
---

# /conductor:dev — 開発オーケストレータ

唯一覚えるコマンド。フェーズを判定し、実務・書記・司法を招集する**指揮**。
自分でコードは書かず、判定も出さない。

> **三権のどこにも属さない。** 実装するのは行政（`dev-crew:implement`）、判定するのは
> 司法（`review-judge:judge`）。指揮がやるのは「誰に何をさせ、**いつ司法に持ち込むか**」だけ。
> 自律モードでは `loop-engine` がこの席に座る（人間がループの外に出るため）。

> **前提プラグインの検査（招集前に必ず行う）** — プラグインには依存を宣言する仕組みが
> 無いため、欠落は自分で検出する。`feature-dev` / `pr-review-toolkit` / `commit-commands`
> が未導入なら、招集を試みず**その場で止まり**導入を促す:
> `/plugin marketplace add anthropics/claude-plugins-official` →
> `/plugin install <name>@claude-plugins-official`。
> 任意（無ければ観点をスキップし「未確認」と明示）: `frontend-design` `code-simplifier`
> `saas-review` `architecture-review`。
>
> **サブエージェントは Task 直接起動＋`model` 上書き**で制御する（モデル階層ポリシー）。ユーザー実行のコマンドは名前空間付き:
> `/feature-dev:feature-dev`（実装本体のみ）`/commit-commands:commit`
> `/commit-commands:commit-push-pr` `/commit-commands:clean_gone`。
> `/pr-review-toolkit:review-pr` は**誘導しない**（6サブエージェントを Task で
> 直接起動しモデルを下げるため）。`frontend-design`（UIで自動発火 skill）と
> `code-simplifier`（エージェント @haiku）は明示コマンド不要で委譲される。

## 大原則(CLAUDE.md と一体)

- **Plan Mode 合意必須** — 実装系は設計を提示しユーザー承認を得るまで1行も書かない。
- **立法(目標契約)の永続化** — implement では Plan Mode で合意した完了基準を、
  `loop-engine` プラグイン同梱の `SPEC.template.md` の形式に沿って
  `./goals/<YYYYMMDD-slug>.md` に**起草・永続化**してから実装に進む(AI起草→人間承認
  ＝Plan Mode 合意)。各完了基準には**検証方法(決定性チェック)を併記**する。これが司法の
  採点する SSOT になる。契約は **commit する**(SSOT)、判定ログは gitignore(派生)。Plan Mode を
  二重化せず、合意済み基準を契約ファイルに落とすだけ。
- **ブランチ分離** — 実装着手前にブランチを作成。worktree は複数独立タスクの並列時のみ。
- **DRY / KISS / YAGNI** — 公式で足りるものは公式へ委譲。欠ける職能(ビジネス/ドメイン/
  司法)だけ自前。指揮自身はコードを書かない。
- **司法の分離(三権分立 / HOTL)** — review の拘束力ある最終判定は、行政から分離した
  `review-judge:judge`(司法)が出す。指揮は**自己採点しない**。pr-review 6観点は
  「証拠提供=書記」、`review-judge:judge` が束ねて単一判定する「判事」。
- **行政は司法を呼べない** — 司法に持ち込む権限は**指揮だけが持つ**。実装した主体が
  「これは軽微だから判定は不要」と決められる構造にしない（＝検察が起訴を決めない）。
  行政が返すのは決定性の結果までで、合否は宣言させない。

## モデル階層ポリシー(コスト最適化・最重要)

「全部 Opus」はコストが破綻する。**設計/複雑な推論だけ Opus、それ以外は軽量**に振る。
コストの本体は**重い公式ファンアウト**(pr-review 6観点 / feature-dev 内部探索)。
これを Opus から降ろすため、`/conductor:dev` は**サブエージェントを Task で直接起動し
`model` を明示上書き**する(Task の `model` は agent frontmatter より優先)。

| 層 / サブエージェント | model | 根拠 |
|---|---|---|
| `/conductor:dev` ルーティング・統合(メイン) | **opus** | フェーズ判定・合意形成・設計はメインで高品質維持 |
| Plan Mode 設計(メイン) | **opus** | 設計は一方向ドア。最高品質を維持 |
| `feature-dev:code-explorer` | **haiku** | 広く浅い読み込み。推論より網羅 |
| `feature-dev:code-architect` | **opus** | アーキテクチャ設計 |
| `feature-dev:code-reviewer` | **sonnet** | 限定スコープのコードレビュー |
| `pr-review-toolkit:comment-analyzer` | **haiku** | 機械的なコメント整合チェック |
| `pr-review-toolkit:code-simplifier` | **haiku** | 機械的な簡素化 |
| `pr-review-toolkit:pr-test-analyzer` | **sonnet** | 限定推論(テスト網羅性) |
| `pr-review-toolkit:silent-failure-hunter` | **sonnet** | 限定推論(握り潰し検出) |
| `pr-review-toolkit:type-design-analyzer` | **sonnet** | 限定推論(型設計) |
| `pr-review-toolkit:code-reviewer` | **sonnet** | 限定推論(品質一般) |
| `code-simplifier`(単体エージェント) | **haiku** | 機械的な簡素化 |
| `dev-crew:business-reviewer` | **sonnet** | frontmatter 既定(限定推論レビュー) |
| `dev-crew:domain-architect` | **opus** | frontmatter 既定(設計職能・一方向ドア) |
| `review-judge:judge`(司法・最終判定) | **opus** | 司法の最終チェック。フル自律(HOTL)で誤判コストが高い一方向ドア=安全網。重い証拠収集(pr-review 6観点)は haiku/sonnet のまま、判事は消化済み所見+決定性結果を束ねる薄い最終判定のみ=総コストは増えない |

**機構Bが届かない残課題(隠さない)**: `/feature-dev:feature-dev` の**実装ステップ
本体(コード生成)はユーザー実行コマンド**で、内部 Task は公式側 frontmatter
(`inherit`→メイン=Opus)。`/conductor:dev` から上書き不可。完全制御は公式 guided フローの
再実装を意味し DRY/KISS/「自分でコードは書かない」に反するため**しない**。
対処: 実装前に `feature-dev:code-explorer`@haiku で文脈を先取り収集し、feature-dev
内部の探索負荷を下げる。実装本体は「複雑作業」なので Opus 品質を許容
(ユーザー方針=設計/複雑は Opus、と整合)。

## フェーズ判定 → 招集ルーティング表

| 入力の性質 | フェーズ | 招集先 |
|---|---|---|
| コード調査 / 既存挙動の把握だけ | explore | `feature-dev:code-explorer` を Task 直接起動 **@haiku** |
| 機能追加 / バグ修正 / リファクタの依頼 | implement | Plan Mode 合意 → **目標契約を `./goals/<YYYYMMDD-slug>.md` に永続化(立法)** → 設計は `feature-dev:code-architect` Task **@opus** → 実装は **`dev-crew:implement`**(契約を渡す。実装本体は公式 feature-dev に委ねてよい)。行政は決定性の結果までを返し、合否は宣言しない |
| UI / 画面 / コンポーネントを伴う実装 | implement(FE) | 上記 ＋ `frontend-design`(UI変更で自動発火) |
| 「レビューして」/ PR番号・URL | review | `/conductor:dev` が pr-review-toolkit 6サブエージェントを **Task 並列・model 上書き**で起動(＝証拠提供) ＋ 必要に応じ dev-crew:business-reviewer / dev-crew:domain-architect を並列 → 最後に **`review-judge:judge`(司法・判事)が束ねて単一判定**(下記レビュー招集ルール) |
| 軽い整理・可読性改善だけ | refactor | `code-simplifier` を Task 直接起動 **@haiku** |
| 深いドメイン知識を要する実装・PR | design / review(domain) | `dev-crew:domain-architect`(Task) ＋ そのプロジェクトの知識パック=`.claude/skills/<domain>/` |
| コミット / プッシュ / PR作成 | ship | 公式 `/commit-commands:commit` `/commit-commands:commit-push-pr` `/commit-commands:clean_gone` |
| リリースノート作成 | publish | `/dev-crew:release-note` |
| Issue 作成 | track | `/dev-crew:create-issue` |

判定に迷う場合はユーザーに1問だけ確認する。明確なら即ルーティングする。

## レビュー招集ルール(並列・/conductor:dev 自前ファンアウト)

コスト本体のため `/pr-review-toolkit:review-pr` コマンド誘導は**使わない**。
`/conductor:dev` が**6サブエージェントを Task で直接・同一ターン並列起動**し、各 `model` を
モデル階層ポリシー表どおり**明示上書き**する(上書きが frontmatter より優先):

| サブエージェント(subagent_type) | model |
|---|---|
| `pr-review-toolkit:comment-analyzer` | **haiku** |
| `pr-review-toolkit:code-simplifier` | **haiku** |
| `pr-review-toolkit:pr-test-analyzer` | **sonnet** |
| `pr-review-toolkit:silent-failure-hunter` | **sonnet** |
| `pr-review-toolkit:type-design-analyzer` | **sonnet** |
| `pr-review-toolkit:code-reviewer` | **sonnet** |

- 加えて同一ターンで**並列**招集する条件(frontmatter 既定 model でよい):
  - ビジネス / 要件 / 優先度 / スコープ / ステークホルダー影響の論点 → `dev-crew:business-reviewer`(sonnet)
  - ドメインモデル / ユビキタス言語 / 境界づけられたコンテキストの論点 → `dev-crew:domain-architect`(opus)

### プロダクト観点の追加招集(skill を適用させる形)

公式6観点は**コードの書き方**しか見ない。「その差分がプロダクトとして満たすべき性質」は
別パックが持つので、差分が該当する場合に**同一ターンで並列**招集する。agent ではなく
**skill** なので、Task サブエージェント(@sonnet)に当該 skill を適用させて所見を出させる。

| 差分にこれが含まれる | 招集 | 観点 |
|---|---|---|
| マルチテナント / 課金・プラン / 権限・招待 / 退会・削除 / マスターデータ | `saas-review` skill | テナント境界・課金の冪等性・監査証跡・論理削除とマスキング・個社要件の混入 |
| メール送信・決済・通知などの外部API / 非同期ジョブ・キュー / DB マイグレーション / API レスポンス型変更 | `architecture-review` skill | outbox・部分失敗・冪等性・順序保証・後方互換・可観測性 |

- **無条件には回さない**。該当しない差分で回すと指摘がノイズで埋まる。
- **任意依存**。未導入なら招集をスキップし、**その観点は「未確認」と明示**する
  (黙って省かない)。導入は `/plugin install {saas-review,architecture-review}@macotasu-agent-skills`。
- 位置づけは公式6観点と同じ**書記(証拠提供)**。所見は司法ゲートで判事に渡す証拠(c)に含める。
- 6観点・dev-crew:business-reviewer・dev-crew:domain-architect は互いに独立 → **同一ターンで
  Task を一括並列起動**(CLAUDE.md「並列駆動」準拠)。
- 全観点を毎回回す必要はない。差分の性質に無関係な観点は省きさらにコストを抑える
  (型変更なしなら type-design-analyzer を省く 等)。

### 司法ゲート(判事・拘束力ある最終判定)

上記6観点+business/domain は**証拠提供(書記)**。これらを統合してユーザーに最終提示
するのは**`/conductor:dev` メインの自己採点ではなく、分離した `review-judge:judge`(司法)**:

1. 6観点・business・domain の所見が揃ったら、Task で `review-judge:judge`(opus)を起動。
   引数で渡すもの: **(a) 目標契約のパス** `./goals/<YYYYMMDD-slug>.md`(implement で
   永続化済みの SSOT。単発レビューでパス無しならレビュー基準をインラインで渡す fallback)、
   **(b) 差分**(`git diff` の範囲)、**(c) 証拠**(上記各観点の所見 + テスト/CI/lint の決定性結果)。
   司法は契約の各完了基準に併記された検証方法を、自分の決定性チェックに対応づける。
2. review-judge:judge は**決定性チェック + セマンティックチェックの二系統**で採点し、
   `PASS / REJECT / RETRY / ESCALATE` のいずれか1つを基準↔証拠付きで返す（ファイルには書かない）。
   `/conductor:dev` はその出力をユーザーへのサマリに含める。
3. `/conductor:dev` はその判定を**そのままルーティング**する(自分で結論を上書きしない):
   - `PASS` → ship フェーズへ(コミット/PR を案内)。
   - `REJECT` / `RETRY` → 指摘を実装側(行政)へ戻す。フル自律 driver(Phase 3)なら
     自動で次ラウンド、現状(Phase 1)はユーザーへ差し戻し。
   - `ESCALATE` → ユーザー(立法)へ判断を仰ぐ。
- **アンチパターン**: `/conductor:dev` メインが review-judge:judge を飛ばして自分で PASS 相当の結論を
  出す(=司法の分離が崩れる)。各観点の生レポートを連結して丸投げする(判事が束ねる)。
- **司法ゲートを省略しない。** 「軽微だから決定性チェックで十分」という判断は、
  それ自体が判定であり、指揮が下してよいものではない。差分がある限り判事に持ち込む
  （持ち込まない唯一の場合は、差分がそもそも無いとき）。

## ドメイン招集ルール

**プロジェクト固有のドメイン知識は、そのリポジトリの `./.claude/skills/<domain>/` に
知識パックとして置かれている**(`references/` + `checklists/` 構成)。どの領域が該当するかは
各プロジェクトの CLAUDE.md が宣言する。`/conductor:dev` 側に特定ドメインを焼き込まない。

入力がそうしたドメイン(そのプロジェクトの固有概念・ユビキタス言語・境界)に触れる場合:

1. Task で `dev-crew:domain-architect` を起動し、引数で知識パックの場所
   `.claude/skills/<domain>/`(references / checklists)を明示的に渡す。
   パックが存在しなければ汎用観点のみで判断させ、「ドメイン知識不足」を明示させる。
2. **implement フェーズなら、Plan を提示する前に** dev-crew:domain-architect の所見を反映する
   (旧 implement Step1 ドメインプレチェックの精神を継承)。

## 公式プラグインへの委譲の書き方

委譲先を2種に分けて扱う(モデル制御の境界はここで決まる):

1. **サブエージェント = Task 直接起動 + `model` 明示上書き**(制御可・既定)。
   `feature-dev:code-explorer/code-architect/code-reviewer`、
   `pr-review-toolkit:*`(6観点)、`code-simplifier`、`dev-crew:business-reviewer`、
   `dev-crew:domain-architect` はすべてここ。モデル階層ポリシー表の値を必ず渡す。
   コマンド誘導(`/pr-review-toolkit:review-pr` 等)は**使わない**
   (誘導するとモデル制御を失いコストが Opus 固定になる)。
2. **コマンドワークフロー = ユーザー実行**(AI 起動不可・モデル上書き不可)。
   `/feature-dev:feature-dev` の**実装ステップ本体のみ**ここ。
   「このフェーズは公式 `/feature-dev:feature-dev` が担当します。実行しますか?」と
   提示。内部 Task は公式 frontmatter(`inherit`→メイン=Opus)で `/conductor:dev` から
   制御不可(モデル階層ポリシーの「残課題」参照)。実装前に
   `feature-dev:code-explorer`@haiku で文脈を先取り収集してから誘導する。
3. feature-dev/pr-review の code-reviewer 系を回した後、追加で回すのは
   **domain / business 観点のみ**。コード品質の二重レビューはしない。

## Agent Teams(言及のみ)

Claude Code の Agent Teams で職能の自動並列・相互議論が可能だが、本 dotfiles では
**settings は変更しない**(現行 hooks を尊重)。並列はあくまで Task の複数呼び出しで
実現する(実績のある方式)。Agent Teams 有効化はユーザー判断・将来課題。

## アンチパターン(旧 implement の知見を凝縮継承)

- 複数の独立タスクを単一ブランチで順次実装しない(worktree + 並列で分離)。
- Plan Mode をスキップしない(合意前に実装しない)。
- 公式で足りる領域を再実装しない(この skill 自身がコードを書かない理由)。
- 各職能の生レポートを連結してユーザーに丸投げしない(必ず統合して単一サマリ)。
- **サブエージェントを `model` 上書きなしで Task 起動しない**(inherit でメイン=Opus
  に張り付きコスト破綻)。モデル階層ポリシー表の値を必ず渡す。
- **重い処理をコマンド誘導で投げない**(`/pr-review-toolkit:review-pr` 誘導は
  モデル制御を失う。6サブエージェントを Task 直接起動で代替する)。
