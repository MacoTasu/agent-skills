# 親と子: main で仕様を作り、worktree で実装する

`/conductor:dev` は起動した場所で役割が変わる。

| | 親 | 子 |
|---|---|---|
| どこで | `main` のチェックアウト | 機能ごとの worktree（ブランチ `feat/<名前>`） |
| 起動 | `/conductor:dev <依頼>` | `/conductor:dev specs/<機能>/`（親が送る、または人間が打つ） |
| 仕事 | 仕様の起草と仕様の PR、承認済み仕様の送り出し、子の様子の把握 | 実装 → 書記 → 司法 → PR |
| しないこと | コードを書く・`main` にコミットする・仕様の PR をマージする | 仕様（`spec.md`・constitution）を変える・`main` に触る |

親を `main` に置くのは、人間が親と話し続けている間も子が並行して動けるようにするため。
子が worktree の中にいるので、書記（Task）も判事も自然に実装のある場所を見る
（`herdr-backend.md`「前提: 指揮・行政・司法は同じディレクトリで動く」）。

仕様を作らない小さな変更は親子に分けない。`SKILL.md` の振り分け表どおり、インライン契約で進める。

## 前提: spec-kit が初期化されていること

親は最初に確かめ、欠けていれば**提案して止まる**（勝手に書き換えない）。

| 確認 | 無いとき |
|---|---|
| `.specify/` と `.claude/skills/speckit-specify/` がある | `specify init --here --force --non-interactive --integration claude --script sh` を人間に案内する（ブランチの上で実行してもらう） |
| `.specify/init-options.json` の `feature_numbering` が `"timestamp"` | 変更を提案する。連番（`"sequential"`）のままだと、並行して開いた仕様の PR が同じ番号を取り合う |
| `.specify/memory/constitution.md` に自動テストの原則がある | 次の原則を追加する案を示す: 「`spec.md` の各 FR と各受け入れシナリオは、それを確かめる自動テストを持たなければならない（MUST）。テスト名かテスト内に基準 ID（`FR-001`、`US1/AC2` など）を書いて対応を辿れるようにする」。spec-kit ではテストが任意なので、これが無いと司法が採点に使う証拠が作られない |

## 仕様の起草（親）

1. `main` にいて作業ツリーがきれいなことを確かめ、`git pull --ff-only` で最新にする。
2. 仕様用のブランチを切る: `git switch -c spec/<短い名前>`。
3. spec-kit で起草する。**人間と対話しながら**進め、各段の出力を人間に見せる:
   - `/speckit-specify <依頼内容>` → `specs/<タイムスタンプ-名前>/spec.md`
   - 曖昧な点があれば `/speckit-clarify`（`[NEEDS CLARIFICATION]` を残さない）
   - `/speckit-plan` → `plan.md` ほか
   - `/speckit-tasks` → `tasks.md`（テストのタスクが実装タスクより前にあること）
   - `/speckit-analyze` → 整合性の報告（読み取りのみ）。重大な指摘は直してから進む
4. `specs/<機能>/` だけをコミットして push し、`gh pr create` で**仕様の PR** を作る。
   本文には、何を作るか（`FR` の一覧）と「仕様の PR。マージが承認。実装は別の PR」と書く。
   issue から来た依頼なら本文に issue 番号を書く（`Closes` は付けない。閉じるのは実装の PR）。
5. `git switch main` で戻り、PR のリンクを人間に渡す。**マージはしない**（承認は人間）。

マージ後の渡し先は2通り。人間が親に「実装して」と言えば下の送り出し、`loop-engine` に任せるなら
issue に `Spec: specs/<機能>/` のコメントと `loop-ready` ラベルを付ける（`loop-engine` の手順）。

## 送り出し（親）

**前提の確認**（1つでも欠ければ送り出さず、何が足りないかを人間に伝える）:

- `git fetch origin` のあと、`git cat-file -e origin/main:specs/<機能>/spec.md` と
  `origin/main:specs/<機能>/tasks.md` が存在する（＝仕様の PR がマージ済み）
- `spec.md` に `[NEEDS CLARIFICATION` が残っていない
- 同じ機能の子がまだ動いていない（`herdr agent list` に `child-<名前>` が無い、`feat/<名前>` の open PR が無い）

**並行している他の機能との衝突**: 送り出す機能の `tasks.md` に出てくるファイルパスと、動いている子
（または open な `feat/*` PR）の `tasks.md` のファイルパスを比べる。重なれば人間に知らせる
（マージの時点で衝突しうる。止めるかどうかは人間が決める）。

**herdr がある場合**（`HERDR_ENV=1`）:

```bash
herdr worktree create --branch feat/<名前> --base origin/main --label <名前> --no-focus
#   → 応答の JSON から新しい workspace とその root pane の ID を読む（推測しない）
herdr agent start child-<名前> --kind claude --pane <root_pane_id>
herdr agent prompt child-<名前> "/conductor:dev specs/<機能>/"
```

- `<名前>` は機能ディレクトリ名から先頭のタイムスタンプを除いた部分（例: `user-export`）。
- herdr が Git の信頼確認（`--trust-repository`）を求めたら、付けずに人間に確認する。
- **送ったら待たずに人間との対話に戻る。** 様子は `herdr agent list` / `herdr agent get child-<名前>` で見る。
  完了を待ちたいときは `herdr agent wait child-<名前>` をバックグラウンドで実行し、通知で再開する。
- 子が `blocked`（承認待ち）なら、代わりに答えず「`child-<名前>` で承認待ち」と人間に伝える。

**herdr が無い場合**: `git worktree add ../<リポジトリ名>-<名前> -b feat/<名前> origin/main` で worktree を作り、
「そのディレクトリで `claude` を起動し `/conductor:dev specs/<機能>/` を実行してください」と人間に案内する。

## 子の手順

1. **場所の確認** — `main` の上ではないこと、`git rev-parse --show-toplevel` が自分の worktree であること。
   `main` の上なら子として動かず、親として振る舞う（送り出しを案内する）。
2. **契約が承認済みであることの確認** — `git fetch origin` のあと、`git diff --quiet origin/main -- specs/<機能>/`
   が成功すること（手元の仕様が、マージ済みの仕様と同じ）。違えば ESCALATE（未承認の仕様では実装しない）。
3. **spec-kit に機能を教える** — `.specify/feature.json` に `{"feature_directory":"specs/<機能>"}` を書く
   （spec-kit が各チェックアウト専用の状態として gitignore しているファイル。コミットされない）。
4. **Plan Mode は省く** — 合意は仕様の PR のマージで済んでいる。
5. **行政** — `dev-crew:implement` に契約 `specs/<機能>/` を渡す（`.claude/conductor.json` で `via: herdr` ならペインで）。
6. **書記** — `SKILL.md` のレビュー招集ルールどおり（Task。worktree の中なので実装を正しく見る）。
7. **司法** — 契約 `specs/<機能>/`・差分（`origin/main...HEAD`）・証拠を渡す。行政の決定性結果は「申告（未検証）」として。
   - `REJECT` / `RETRY` → 指摘を行政へ戻す（最大3ラウンド。超えたら人間へ）。
   - `ESCALATE` → 止まって人間へ。
8. **PASS なら PR** — 変更したファイルを明示してコミットし、push して `gh pr create`。
   本文には `Spec: specs/<機能>/` と「⚠️ 要注意の変更」節（`loop-engine` 同梱 `autonomy-gates.md` の書式）を入れ、
   司法の判定出力を `gh pr comment` で添付する。**マージはしない。**
9. 終わったら人間（と親）に PR のリンクを伝える。worktree の後始末はマージ後に人間が
   `/commit-commands:clean_gone` で行う。

## 人間が子に直接指示するとき

人間は herdr で子のペインに直接話しかけてよい。親を通す必要はない。

- **仕様の範囲内**（進め方の修正・ヒント・優先順位）→ そのまま従う。
- **仕様の範囲が変わる**（「ついでにこれも」「この要件は無しで」）→ **実装を止め**、「先に仕様の PR が要る」と伝える。
  子は `spec.md` を変えない（変えれば司法が ESCALATE する）。仕様の修正は親に頼むか、人間が仕様の PR を出す。
  仕様がマージされたら、子は手順2からやり直す。
