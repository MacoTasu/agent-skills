# agent-skills

**📖 [ドキュメント](https://macotasu.github.io/agent-skills/)** — 収録プラグイン・レビューの構造・決定の記録

AI エージェント向けのレビュー知識パック集。

公式の `pr-review-toolkit` をはじめとする既存のレビュー支援は、いずれも**コードの書き方**
（命名・型設計・テスト網羅・コメント・エラーハンドリング）を見る。このリポジトリが扱うのは
**その差分がプロダクトとして満たすべき性質**のほうで、両者は重ならない。
「型は綺麗でテストも通るが、他テナントのデータが見える」「リトライで二重課金する」
——そういう差分を止めるための観点を置いている。

## 収録

| プラグイン | 内容 |
|---|---|
| `saas-review` | **マルチテナント SaaS に固有**の観点5軸（テナント境界 / 課金・メータリング / 権限・監査ログ / データ保持と削除・マスキング / 個社要件と汎用性） |
| `architecture-review` | **事業形態に依存しない**観点3軸（外部連携とトランザクション整合＝outbox / API・スキーマの後方互換 / 観測性と障害時の運用） |
| `review-judge` | レビューの**拘束力ある最終判定だけ**を下す司法。`Edit` / `Write` を持たないので直せない |
| `spec-intake` | **立法の支援**。issue での議論を、実装根拠になる spec-kit の仕様まで持ち上げる。`grill-issue` が曖昧な issue を詰め、`spec-draft` が spec-kit で仕様を起草して仕様の PR にする。承認は必ず人間 |
| `conductor` | 開発の単一フロントドア＝**指揮**。`main` の親が spec-kit で仕様を起草して仕様の PR を作り、承認された仕様を worktree の子に送り出す。子は行政に実装させ、書記に証拠を出させ、**司法に持ち込む**。自分ではコードを書かず、判定も出さない |
| `dev-crew` | **行政（実務）**。契約に沿って実装し、ビルド・型・lint・テストの決定性証拠を揃えるところまで。判定は出さず、証拠を揃えて指揮に返す。出荷・運用と書記の職能エージェントも同梱 |
| `loop-engine` | 人間が承認した spec-kit の仕様を起点に、拾い上げ→実装→司法検証→PR を回す自律ループ（HOTL）。必ず PR で停止する |
| `spec-page` | 説明書・仕様書・設計文書を HTML 1枚にまとめる。一覧ではなく**構造と決定の理由**を伝える形式に落とす |

レビュー観点の2つの境界は「**マルチテナントで課金して継続提供するという事業形態に固有か**」で
引いている。SaaS のバックエンドを触る PR では両方が効く。

## インストール（Claude Code）

```
/plugin marketplace add MacoTasu/agent-skills
/plugin install saas-review@macotasu-agent-skills
/plugin install architecture-review@macotasu-agent-skills
/plugin install review-judge@macotasu-agent-skills
/plugin install spec-intake@macotasu-agent-skills
/plugin install dev-crew@macotasu-agent-skills
/plugin install conductor@macotasu-agent-skills
/plugin install loop-engine@macotasu-agent-skills

# ドキュメント。依存ゼロ
/plugin install spec-page@macotasu-agent-skills
```

必要なものだけ入れればよい。**レビュー観点の2つは依存ゼロで単体で使える。**

### 依存関係

```
spec-intake     立法支援  依存: spec-kit（外部）／ grilling（外部・任意）
dev-crew        行政      依存: 公式 feature-dev ／ spec-kit（仕様を契約にするとき）
review-judge    司法      依存なし

conductor       指揮   必須: dev-crew / review-judge
                       ＋ 公式 pr-review-toolkit / commit-commands
                       任意: frontend-design / code-simplifier
                             saas-review / architecture-review

                       仕様を作るなら: spec-kit（外部）／ 並行実行: herdr（外部・任意）

loop-engine     自律   必須: dev-crew / review-judge ／ spec-kit（外部）
                       （自律モードでは loop-engine 自身が指揮の席に座る）
```

外部の [spec-kit](https://github.com/github/spec-kit) は**同梱しない**。使うリポジトリで
`specify init --here --integration claude` して、`.specify/` と `.claude/skills/speckit-*` をコミットする。

**行政と司法は葉、指揮が根**。行政から司法への矢印が無いのが要点で、
**実装した主体は自分の成果を判事に持ち込む権限を持たない**。
「これは軽微だから判定は不要」という判断自体が判定であり、行政には属さない。

司法が独立した配布単位なのも同じ理由。行政のプラグインに同梱すると、
分離を主張しながら行政が司法を配ることになる。

プラグインには依存を宣言する仕組みが無いので、`conductor:dev` は招集の前に
前提プラグインの有無を自分で検査し、欠けていれば導入を促して止まる。

## Claude Code 以外で使う

中身は [Agent Skills](https://code.claude.com/docs/en/skills) 形式の素の Markdown で、
特定のランタイムに依存する記述を本文に持たない。`plugins/*/skills/*/` を
そのままコピーするか、`checklists/*.md` を任意のエージェントのコンテキストに渡せば使える。
プラグイン／マーケットプレイスの仕組みだけが Claude Code 固有。

## 役割の分離

4つの役に分けてある。3つは三権、1つはそのどれでもない。

| 役 | 誰 | 持たないもの |
|---|---|---|
| **立法** | 人間が承認した spec-kit の仕様 `specs/<機能>/` と constitution（起草は `conductor` の親か `spec-intake`） | — ボットは承認しない |
| **行政** | `dev-crew:implement`（＋公式 feature-dev）。**自己レビューまでが仕事** | **司法を呼ぶ権限**と**合否を宣言する権限** |
| **司法** | `review-judge:judge` | **`Edit` / `Write` ツール**。直せない |
| 指揮 | `conductor:dev`（手動） / `loop-engine`（自律） | コードを書かない。判定も出さない |
| 書記 | pr-review 6観点 / `business-reviewer` / `domain-architect` / `saas-review` / `architecture-review` | 拘束力。所見を出すだけ |

**それぞれの「持たないもの」が分離を支えている。**
判事が `Edit` / `Write` を持たないのは、修正できてしまえば実行と検証が同一主体になるから。
行政が司法を呼べないのは、実装した主体が「これは軽微だ」と判定を回避できてしまうから。
どちらも規約で禁じるのではなく、**権限を与えないことで構造的に強制している**。

### 任意: 行政と司法を herdr のペインで動かす

`conductor:dev` は、行政と司法を Task の代わりに [herdr](https://herdr.dev) の隣のペインで
動く別の AI コーディングツールに担わせられる（例: 実装は Claude Code、判事は GitHub Copilot CLI）。
判事を別ベンダーのモデルにすると、書いたモデルと採点するモデルが盲点を共有しなくなる。
対象リポジトリの `.claude/conductor.json` で役割ごとに選ぶ。既定は Task のままで、herdr が無ければ自動で Task に戻る。

**この場合、判事の分離は弱まる。** ペインのツールはシェル経由で書き込めるので、
「直せない」を権限の不在では強制できない。代わりに判事の前後で作業ツリーを比較し、
変わっていれば判定を無効にして人間へ上げる（禁止＋事後検出）。
手順と制約は [`plugins/conductor/reference/herdr-backend.md`](plugins/conductor/reference/herdr-backend.md)。

## spec-kit との分担

立法（仕様）には [spec-kit](https://github.com/github/spec-kit) を使い、そのレールに乗る。
`/speckit-specify` → `clarify` → `plan` → `tasks` → `analyze` で仕様を作り、**仕様を先に PR にして人間がマージ**
してから実装する（Living Spec: `spec.md` が契約で、振る舞いを変えるなら先に `spec.md` を直す）。
小さな変更は仕様を作らず `/conductor:dev` で直接進める。

**ただし実装コマンドの `/speckit-implement` は使わない。** 実装は `dev-crew:implement` が `tasks.md` を読んで行う。

| `/speckit-implement` の振る舞い | 何とぶつかるか |
|---|---|
| 技術スタックを検出して `.gitignore` などを毎回作成・追記する | **スコープ外の差分**が毎回混ざる |
| `checklists/` に未チェックがあると人間に yes/no を聞いて止まる | **無人ループが固まる** |
| 基準ごとの証拠を返さない | 司法に渡す**証拠の形が無い** |

最後に自分で完了を検証する手順もあるが、これは良い自己レビューで、不採用の理由ではない
（後ろに必ず司法を置くので、自己検証で工程が終わる作りでも実害は出ない）。

成果物の形式（`tasks.md` のタスク ID・`[P]`・`[X]`）には従うので、`/speckit-analyze` や `/speckit-converge` は
そのまま使える（`converge` は行政の自己点検として使い、完了の判定には使わない）。
spec-kit 自身の工程エンジン（`workflow.yml`）も最後が `/speckit-implement` で判事がいないため使わず、工程は指揮が持つ。

## 設計方針

- **1項目＝固定4フィールド**（観点 / なぜ危険か / どう検出するか / よくある間違った実装）。
  特に「どう検出するか」は grep やコマンドなど、**エージェントが実際に実行できる形**で書く。
  これが書けない項目は、レビューで実行できないので採用しない。
- **初期の観点は実地の裏付けを持たない**。最初の軸は一般知識で書き起こしたもので、
  実際の PR に当てて空振りしたら直す前提でいる。以後に追加される項目は、下の育て方の
  とおり「見逃しかけた実例」から来るので、その時点で裏付けを持っている。
- **増やさない**。追記するのは「このパックに無かったせいで見逃しかけた観点」だけ。
  良い指摘を全部書き足すとチェックリストが膨張し、かえって発火精度が落ちる。

## 育て方

レビューで、このパックに載っていない観点のせいで問題を見逃しかけたら、その観点を
4フィールドの形にして追記する。手順は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。

## backlog（未収録の軸）

オンボーディング・トライアル / 通知・メール配信 / レート制限 / フィーチャーフラグ運用。

## ライセンス

MIT
