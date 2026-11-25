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
| `review-judge` | レビューの**拘束力ある最終判定だけ**を下す司法。`Edit` / `Write` を持たないので直せない。PR 本文の「要注意の変更」「見た目の証拠」の申告が差分と一致するかも検査する |
| `spec-intake` | **立法の支援**。issue での議論を、実装根拠になる spec-kit の仕様まで持ち上げる。`grill-issue` が曖昧な issue を詰め、`spec-draft` が spec-kit で仕様を起草して仕様の PR にする。承認は必ず人間 |
| `conductor` | 開発の単一フロントドア＝**指揮**。`main` の親は依頼を分類して worktree の子に送り出し、子が仕様の起草、または Plan Mode 合意→実装→書記→司法→PR を回す。子は行政に実装させ、書記に証拠を出させ、**司法に持ち込む**。自分ではコードを書かず、判定も出さない |
| `dev-crew` | **行政（実務）**。契約に沿って実装し、ビルド・型・lint・テストの決定性証拠を揃えるところまで。UI に触れたら before / after の動画（見た目の証拠）も撮る。判定は出さず、証拠を揃えて指揮に返す。出荷・運用と書記の職能エージェントも同梱 |
| `loop-engine` | 人間が承認した spec-kit の仕様を起点に、拾い上げ→実装→司法検証→PR を回す自律ループ（HOTL）。必ず PR で停止する |
| `spec-page` | 説明書・仕様書・設計文書を HTML 1枚にまとめる。一覧ではなく**構造と決定の理由**を伝える形式に落とす |
| `pr-kit` | **PR まわりの道具 4 つ**（`write-pr-description` / `merge-risk` / `resolve-merge-conflicts` / `diagnose-ci-failures`）。外部の公開スキル集（MIT）から、版を固定した写しとして借りている。各役が使う道具で、**合否は出さない**。`merge-risk` は人間がマージを決めるときの材料で、司法（`review-judge:judge`）の判定の代わりではない。`diagnose-ci-failures` は調べて計画を出すだけで、直さない |
| `session-review` | **手元の会話の履歴を採点して、スキルを直す案を出す**。効率 / コードの質 / 手順の遵守 / 文章の量の 4 つの基準で採点し、失敗と判定した会話を根拠に、戻し先（できなくする / 機械で止める / そのプロジェクトに書く / スキルの文面）を選んだ案をテキストで返す。外部の公開スキル集（MIT）から、版を固定した写しとして、一部を外して借りている。**案を出すだけで、ファイルは書き換えず、変更の合否（司法の判定）も出さない**（会話に付ける点数は、案の根拠）。Claude Code 本体の `/skill-doctor` は「何が使われていないか」（利用回数とコンテキストの費用）を見るもので、これは「使われたスキルが効いているか」を会話の中身から見る別物。集めた抜粋は伏せ字にならないので、出力先はリポジトリの外に置く |
| `calendar-tasks` | **Google カレンダー 1 本でタスクを管理**する窓口と夜間処理。タスクは接頭辞付きの終日予定、毎晩 未完了を次の営業日へ繰り越し、慢性的な繰越は保留にして月末に集める。データは Google カレンダーの中だけ |

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

# PR まわりの道具。依存は gh（衝突の解決は python3 も）
/plugin install pr-kit@macotasu-agent-skills

# 会話の履歴からスキルを見直す道具。依存は python3 と git
/plugin install session-review@macotasu-agent-skills

# 個人の運用。依存は Google カレンダー連携（夜間処理を自動で回すなら cloud routine も）
/plugin install calendar-tasks@macotasu-agent-skills
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

pr-kit          道具   依存: gh（GitHub CLI）／ python3（resolve-merge-conflicts の同梱スクリプト）

session-review  道具   依存: python3（3.9 以上。同梱スクリプト）／ git
                       直す案を実際に反映するとき: conductor（任意）

calendar-tasks  運用   依存: Google カレンダー連携（claude.ai コネクタ）／ cloud routine（夜間処理を自動で回すとき）
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

### `dev-crew` が入れる hook（作業中の操作を確認に回す）

`dev-crew` を入れると、**そのプラグインが有効な全セッション・全リポジトリ**（サブエージェントの中を含む）で、
Bash の実行の前に `hooks/guard-broad-op.sh`（PreToolUse）が走る。次の形のコマンドは、実行の前に**確認**に回る
（拒否ではない。理由と、代わりにすることを添える）。

| 確認に回る形 | 回らない形（例） |
|---|---|
| `pkill` / `killall`、`kill $(pgrep ...)`・`kill $(lsof ...)`、`pgrep ... \| xargs kill` など、条件で探した相手を止める形 | `kill <pid>`、`kill "$PID"`、`kill $(cat <PID を控えたファイル>)` |
| `gofmt -w` / `prettier --write` にディレクトリを渡す、`go fmt ./...` | ファイルを名指しで渡す、`gofmt -l .`、`prettier --check .` |
| `git reset --soft origin/<ブランチ>`・`@{u}`（上流の先頭が HEAD の祖先でないとき） | `git reset --soft "$(git merge-base origin/<ブランチ> HEAD)"` |
| `git add -A` / `--all` / `.`（未追跡のファイルがあるとき） | `git add <ファイル>`、`git add -u`、`git add -p .` |

実際の動き:

- **状態を見るのは、hook が受け取った作業ディレクトリのリポジトリだけ。** 同じコマンドの中で `cd` した後や、
  `git -C`・`--git-dir`・`--work-tree`、前置きの `GIT_DIR=`・`GIT_WORK_TREE=`・`env -C` があるときは、
  状態を見ずに常に確認に回す（未追跡が 0 件でも、祖先であっても）。git のリポジトリでない場所でも確認に回る。
- **`git reset --soft` の祖先の判定は、実行する前の、手元にある上流に対するもの。** 同じコマンドの中で先に
  `git fetch`・`git pull`・`git remote update` があるときは、判定せずに確認に回す。
- 状態を見る git は読むだけ（index を書き換えない）。2 秒で返らないときは、確認に回す。
- **見ていない形**: `bash -c "…"`・`sh -c`・`ssh <ホスト> "…"`・`eval`・`$(…)` の中の命令、スクリプトや `make`・`npm run` 経由、
  `env -S`、`gofmt`・`prettier` 以外の整形、glob や変数で渡した対象、`git reset` の `--hard`、
  `origin/`・`@{u}` 以外の上流の書き方（`upstream/…`・`refs/remotes/…`）、`git add *`・`git add <ディレクトリ>`。
- `jq` が要る（無ければ検査せずに通す）。壊れた入力・20000 バイトを超えるコマンド・入れ子が深すぎるコマンドも通す。
  最後の砦ではなく、取りこぼしを減らす仕組み。規則の足し方はスクリプトの先頭のコメント。
- スクリプトの部品（`hooks/lib/`・`hooks/rules/` のファイル）が読み込めないときは、検査の対象になるコマンドを、中身を見ずに確認に回す（それ以外のコマンドは通す）。

人が答えられないとき:

- `claude -p`（非対話）では、誰も確認に答えられないので、Claude Code が呼び出しを拒否し、理由が Claude に返る
  （[公式の hooks の説明](https://code.claude.com/docs/en/hooks)の範囲）。
- **未確認**: 権限モードが `bypassPermissions`・`dontAsk`・`acceptEdits` のとき、およびサブエージェントの中で、
  hook の「確認」がどう扱われるか。実際のセッションに組み込んでの確認もしていない。

無効にする: 環境変数 `DEV_CREW_GUARD_BROAD_OP=off`（**小文字の `off`** だけ。`settings.json` の `env` に書ける）。この hook だけが止まる。
`"disableAllHooks": true` はすべての hook を、プラグインの無効化は `dev-crew` 全体を止める。

## Claude Code 以外で使う

中身は [Agent Skills](https://code.claude.com/docs/en/skills) 形式の素の Markdown で、
特定のランタイムに依存する記述を本文に持たない。`plugins/*/skills/*/` を
そのままコピーするか、`checklists/*.md` を任意のエージェントのコンテキストに渡せば使える。
プラグイン／マーケットプレイスの仕組みだけが Claude Code 固有。

## 役割の分離

5つの役に分けてある。太字の3つが三権（立法・行政・司法）。

| 役 | 誰 | 持たないもの |
|---|---|---|
| **立法** | 人間が承認した spec-kit の仕様 `specs/<機能>/` と constitution（起草は `conductor` の親が送り出す子（`spec-<名前>`）か `spec-intake`） | — ボットは承認しない |
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

**判事を別ベンダーにしたいだけなら、Codex CLI を使う（ペイン不要）。** `.claude/conductor.json` で
`judge` を `via: codex` にすると、判事を `codex exec -s read-only` で動かす。OS のサンドボックスが
シェル経由の書き込みも遮断するので、「直せない」が再び構造的に強制される（事後検出も保険として残す）。
read-only では書き込み（キャッシュ・ビルド成果物・`$TMPDIR`）やネットワークを要するテストは失敗しうるので、
決定性チェックは指揮が実行して生の出力を判事に渡す。
`scribes` に `codex-review` を足すと、`codex exec review` の所見も書記として証拠に加わる。
手順と制約は [`plugins/conductor/reference/codex-backend.md`](plugins/conductor/reference/codex-backend.md)。

**目視の要らない実装は、`claude -p` で走らせられる（ペイン不要）。** `implement` を `via: headless` にすると、
行政を非対話の `claude -p` で動かし、プロセスが終われば何も残らない。権限は承認待ちで止めない設定にし、
拒否された操作は結果の JSON から事実として拾う。拒否ルールは前方一致ですり抜けうるので、
保証は事後の確認（HEAD と作業ツリーの取り直し）に置く。指揮が Task を呼べない（Claude Code でない）ときは、
書記も同じ手段で回す。判事の `via: codex` とは独立に組み合わせられる。
手順と制約は [`plugins/conductor/reference/headless-backend.md`](plugins/conductor/reference/headless-backend.md)。

**隔離環境の中で実装させたいときは、利用者が設定したコマンドに担わせられる。** `implement` を `via: command` にし、
コマンドは利用者の `~/.claude/conductor.json` の `commands.<名前>`（配列）に書く。対象リポジトリの設定には名前だけを書き、
リポジトリの側に書かれたコマンドは読まない（他人のリポジトリを開いただけで任意のコマンドが動かないようにするため）。
コマンドは、worktree を作業ディレクトリに、依頼を標準入力で受け取り、実装をコミットされていない変更として入れ、報告を標準出力に出して 0 で終わる。
コミットはせず、実装は変更として届く。指揮は事実を取り直す。利用者の設定の `commands` には、実装の役のためのコマンドだけを置く（リポジトリ側は、登録済みの名前のどれでも指名できる）。守られるのは実装の役だけで、受け取ったあとの手元での実行には隔離は及ばない。
手順と制約は [`plugins/conductor/reference/command-backend.md`](plugins/conductor/reference/command-backend.md)。

## spec-kit との分担

立法（仕様）には [spec-kit](https://github.com/github/spec-kit) を使い、そのレールに乗る。
`/speckit-specify` → `clarify` → `plan` → `tasks` → `analyze` で仕様を作り、**仕様を先に PR にして人間がマージ**
してから実装する（Living Spec: `spec.md` が契約で、振る舞いを変えるなら先に `spec.md` を直す）。
実装の途中で気づいた仕様の誤り・不足や、人間が途中で出した範囲の変わる指示は、`/conductor:dev` では同じ PR の中で `spec.md` を直してよい（変更は PR 本文で申告し、判事が申告と差分を突き合わせる。自律ループでは直さず止まる）。
小さな変更は仕様を作らないが、これも `/conductor:dev` の親が worktree の子に送り出し、子の pane で Plan Mode 合意→実装と進める。

**実装コマンドの `/speckit-implement` は、`dev-crew:implement` の枠の中で使う。** コードを書く部分は spec-kit に任せ、
その前後を `dev-crew:implement` が受け持つ（直接は呼ばない）。

| | 担当 | 何をするか |
|---|---|---|
| 前の確認 | `dev-crew:implement` | 仕様が確定しているか（未解決の点・未チェックの checklists）、拡張フックの有無 |
| 書く | `/speckit-implement` | `tasks.md` の順（テスト先行）に実装し `[X]` を付ける |
| 後の確認 | `dev-crew:implement` | 範囲外の変更の検出と巻き戻し、自己レビュー、`/speckit-converge` での点検、要件ごとの証拠表 |

枠が要るのは、`/speckit-implement` を単体で使うと次が素通りするため:

| `/speckit-implement` の振る舞い | 枠がどう防ぐか |
|---|---|
| `checklists/` に未チェックがあると人間に yes/no を聞いて止まる | 前の確認で先に差し戻すので、枠の中では起きない |
| ignore ファイル（`.gitignore` など）に足りないパターンを追記・無ければ作成する（`.vscode/` など、コミットしたいものまで無視されうる） | 後の確認で、タスクに無い ignore ファイルの変更を元に戻して報告する |
| 要件ごとの証拠を返さない | 後の確認で証拠表を作る |

最後に自分で完了を検証する手順は良い自己レビューとして活かす。その「完了」は判定ではなく、合否は判事が出す。
spec-kit 自身の工程エンジン（`workflow.yml`）は最後が `/speckit-implement` で判事がいないため使わず、工程は指揮が持つ。

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

`pr-kit` のスキルは外部の公開スキル集から借りた写しで、元のライセンス（MIT）の全文と出どころを
[plugins/pr-kit/NOTICE.md](plugins/pr-kit/NOTICE.md) と同じディレクトリの `LICENSE-THIRD-PARTY*` に同梱している。
`session-review` も同じ形で、[plugins/session-review/NOTICE.md](plugins/session-review/NOTICE.md) と `LICENSE-THIRD-PARTY` にある。
