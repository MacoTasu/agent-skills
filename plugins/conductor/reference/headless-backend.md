# 実行方式: headless（`claude -p`）

行政（implement）を、Task サブエージェントでもペインでもなく、**非対話の `claude -p`** に担わせる手順。
あわせて、**指揮が Task を呼べないとき**（指揮が Claude Code でない、など）に書記と retro を
`claude -p` で回す手順も置く。**任意の実行方式**で、既定は Task のまま。

## なぜ headless か

- **使い捨ての実装にペインと対話が残らない。** `via: herdr` は実装を目視して割り込めるのが利点だが、
  見る必要の無い実装でもペインが開き、終わった後も残る。`claude -p` はプロセスが終われば何も残らない。
- **Task を呼べない指揮でも、書記と retro を回せる。** 書記（pr-review 6観点など）と retro は Task で招集する
  前提なので、指揮が Claude Code でないと置き場が無く、書記なし・retro なしで終わりうる
  （実例では retro が付かずに PR が終わった）。`claude -p` の中では Agent（Task）が使えるので、
  そこに書記の招集を丸ごと預けられる。

目視したい実装は `via: herdr`（`herdr-backend.md`）。判事を別ベンダーにしたいなら判事は `via: codex`
（`codex-backend.md`）。headless はそれらと**独立に組み合わせられる**（「Task を呼べない指揮のときの置き場」）。

### 実測（claude 2.1.302、macOS）

手順の根拠。版が上がったら確かめ直す。

| 確かめたこと | 結果 |
|---|---|
| `-p --permission-prompts none` | 承認待ちで止まらない。拒否は出力 JSON の `permission_denials` に残り、exit 0・`subtype: success`・`is_error: false` で終わる（**拒否があっても成功扱い**） |
| `-p` の中の Agent（Task） | 使える。プラグインのエージェント（`pr-review-toolkit:code-reviewer`）とスキル（`dev-crew:implement`）が見える。サブエージェントは親の権限を引き継ぐ（Bash の拒否がサブにも効いた） |
| `--agent dev-crew:retro` | retro を直接起動できる。`auto` では下書き（`mktemp` への書き込み）が通った。`dontAsk`＋許可リストではリダイレクトでの書き込みが拒否され、下書きを作れなかった |
| 拒否の記録先 | サブエージェントの中での拒否も、`--disallowedTools` で禁止した呼び出しも、最上位の `permission_denials` に載る |
| 拒否ルールの一致 | 前方一致。`Bash(git commit:*)` は `git commit …` を止めたが `git -c k=v commit …` は通った |
| `auto` の外部への書き込みの判定 | 文脈に依存する（直接の依頼では通り、サブエージェントからは拒否された例がある）。追跡中 |

## 設定

対象リポジトリの `.claude/conductor.json`（任意。無ければ全役割 Task）:

```json
{
  "backends": {
    "implement": { "via": "headless", "model": "opus" }
  }
}
```

| キー | 意味 |
|---|---|
| `backends.implement.via` | `task`（既定）/ `herdr` / `headless` |
| `backends.implement.model` | 任意。`claude -p` の `--model` にそのまま渡す（モデル階層ポリシーの代わり） |

`via: headless` は **implement だけ**に対応する。judge に指定されていたら、**理由を1行表示して Task にフォールバック**する
（Task を呼べない指揮なら、止まって人間へ）。判事の分離を `claude -p` の拒否ルールで担保できるかは未検証のため。
別ベンダーの判事は `via: codex` を使う。
書記と retro は設定で選ぶものではなく、**指揮が Task を呼べないとき**にだけこの手順で回す。

## フォールバック条件（1つでも欠けたら Task）

招集の直前に毎回検査し、欠けたら**理由を1行表示して Task で続行**する。黙って切り替えない。

```bash
command -v claude                     # claude がある
command -v jq                         # 結果の検査に使う
git branch --show-current             # 空でなく、かつ main 等でないこと（実装ブランチの上にいる）
```

- **指揮が Task を呼べないなら、「Task で続行」を「止まって人間へ」に読み替える。** フォールバック先が無いので、
  理由を1行表示して止まる。書記・retro の手順でも同じ。
- **cloud の routine（`loop-engine`）には適用しない。** この設定を読まない。

## 前提: 指揮・行政・司法は同じディレクトリで動く

`herdr-backend.md` の同名節と同じ。`claude -p` の作業ディレクトリも改ざん検出のスナップショットも、
**指揮のいるディレクトリ（`$PWD`）**を実装の場所とみなす。実装が別の worktree にある状態で招集しない。

## 共通: 呼び方と結果の受け取り

1. **招集ごとに新しい一時ディレクトリ**を `mktemp -d` で作り、`<dir>` と呼ぶ（リポジトリの外。
   `.claude/` にも書かない。前回の結果を誤って読まないよう使い回さない）。
2. 指示文を `<dir>/prompt.md` に書き、**stdin で渡す**。出力は `--output-format json` で `<dir>/out.json`、
   stderr は `<dir>/stderr.txt`。`--no-session-persistence` でセッションを残さない。
   コマンドの直後に `echo $? > "<dir>/exit"` で exit code を残す。**`<dir>/exit` が無い間は未完了**
   （バックグラウンドで走っている）。`out.json` の有無で終了を判断しない（書きかけでも存在する）。
3. **権限は全部 `--permission-mode auto --permission-prompts none`。** 承認待ちで止まらず、
   拒否は `permission_denials` に残る。拒否ルール（`--disallowedTools`）は役割ごとに足すが、
   前方一致なので**事故を減らす層であって保証ではない**。保証は事後の確認（各役割の手順）。
4. **時間の上限は置かず、バックグラウンド実行**にして終了の通知を待つ。実装は Bash のタイムアウト
   （最大10分）を超えうる。タイムアウトは未完了を意味しない。**同じ指示で二重に起動しない**。
5. 終わったら（`<dir>/exit` ができたら）、**次の順で**検査し、通ったときだけ `<dir>/result.md` を**指揮が作る**:

```bash
test "$(cat "<dir>/exit")" = 0 \
  && jq -e '.subtype == "success" and .is_error == false
            and (.result | type == "string" and length > 0)' "<dir>/out.json" >/dev/null \
  && jq -r '.result' "<dir>/out.json" > "<dir>/result.md"
jq '.permission_denials' "<dir>/out.json"           # 拒否された操作（事実として控える）
```

- `&&` で繋ぐのは、検査に落ちたときに `result.md` を作らないため。**`result.md` が無いこと＝結果不明**になり、
  空や途中の結果を報告として読み違えない。

- 受け渡しは herdr と同じ「指示文ファイル → `result.md`」の形のまま。ただし `result.md` は**モデルに書かせない**。
  モデルがファイルを書く経路を1つ減らし、書き損じで結果を失うことも無くす。
- **`permission_denials` は事実として控え、判事（行政）・人間（書記・retro）に渡す。** 拒否があっても
  `subtype` は success なので、成功の判定だけでは拒否に気づけない。

| 状況 | 扱い |
|---|---|
| `<dir>/exit` が無い | **未完了**。待つ（同じ指示で二重に起動しない） |
| `<dir>/exit` が 0 でない | **結果不明**。次の段に進まず人間へ |
| `out.json` が無い、空、JSON でない | **結果不明**。次の段に進まず人間へ |
| `subtype` が `success` でない（`error_max_turns` など）、`is_error` が true、`.result` が空 | **結果不明**。次の段に進まず人間へ |
| `success` だが `permission_denials` が空でない | 結果は使う。拒否の中身を事実として添える |

- 結果不明のときは、`stderr.txt` の末尾と `out.json` の中身（あれば）を理由として人間に見せる。
  **同じ指示で自動的に再起動しない**（作業ツリーが途中まで変わっている可能性がある）。

## 行政（implement）

招集の**直前に**、事後の比較の基準を `<dir>` に控える:

```bash
git rev-parse HEAD > "<dir>/head-before"
git status --short > "<dir>/status-before"
```

起動する（バックグラウンド実行）:

```bash
claude -p --permission-mode auto --permission-prompts none \
  --disallowedTools "Bash(git push:*)" "Bash(gh:*)" \
  --add-dir "<dir>" [--model <model>] \
  --output-format json --no-session-persistence \
  < "<dir>/prompt.md" > "<dir>/out.json" 2> "<dir>/stderr.txt"; echo $? > "<dir>/exit"
```

| 引数 | 意味 |
|---|---|
| `--permission-mode auto --permission-prompts none` | 承認待ちで止めない。拒否は `permission_denials` に残る |
| `--disallowedTools "Bash(git push:*)" "Bash(gh:*)"` | 出荷（push・PR 作成）は指揮の仕事なので行政に持たせない。`gh api` は書き込みを持つので丸ごと拒否する。可変長引数なので、後ろに別のオプションを続ける |
| `--add-dir "<dir>"` | 指示文の一時ディレクトリを読めるようにする |
| `--model <model>` | `conductor.json` に `model` があるときだけ付ける |
| `--output-format json` / `--no-session-persistence` | 結果を機械可読にする／セッションを残さない |

指示文 `<dir>/prompt.md` に書くこと（1・2 は `herdr-backend.md`「行政」の 1・2 と同じ。3 は同 3 に
「コミットしない・push しない」を足したもの。4 は結果の受け取り方が違う。5 は headless だけ）:

1. `/dev-crew:implement` を実行し、その手順に従う（同じユーザー環境なのでスキルが使える）
2. 契約 — spec-kit の機能ディレクトリのパス `specs/<機能>/`、またはインライン契約の本文
3. **司法を呼ばない・合否を宣言しない・コミットしない・push しない**（implement の職責どおり。念押し）
4. 最後は implement の「返す形式」を**最終応答として**出して終える（ファイルには書かない。指揮が `out.json` から取り出す）
5. **許可されない操作が要るなら、回避せず「未解決・判断を要する点」に書いて終える**
   （別の書き方で拒否ルールをすり抜けない。拒否ルールは前方一致なので、すり抜けは技術的には可能）

終わったら、共通の検査（`exit`・`subtype`・`is_error`・`.result` → `result.md`、`permission_denials`）のあと、指揮が事実を取り直す:

```bash
test "$(git rev-parse HEAD)" = "$(cat "<dir>/head-before")" || echo "HEAD が動いた"   # 行政がコミットしていないか
git status --short | diff "<dir>/status-before" - # 招集前からの作業ツリーの変化
git diff HEAD --stat
```

- 扱いは `herdr-backend.md`「共通: 報告は参考情報、事実は取り直す」と同じ。報告の「変えたファイル」と
  食い違えば、**食い違いを事実として**判事に渡す。決定性の結果は**行政の申告（未検証）**と明記する。
- **HEAD が動いていた**（行政がコミットした）、`permission_denials` が空でない、のどちらも事実として判事に渡す。
  指揮は裁かない。
- REJECT / RETRY の差し戻しは、**新しい `<dir>` で新しい `claude -p`** を起動する。指示文には判事の指摘と
  **前回の `result.md`** を入れる（`--no-session-persistence` なので文脈は引き継がれない。必要な文脈は指示文で渡す）。

## 書記（Task を呼べない指揮のとき）

指揮が Claude Code なら書記は今どおり Task（`SKILL.md`「レビュー招集ルール」）で、この節は使わない。
Task を呼べない指揮は、**1つの `claude -p` の中で**書記の各観点を Agent で並列に招集させる。

```bash
claude -p --permission-mode auto --permission-prompts none \
  --disallowedTools Edit Write NotebookEdit \
  --add-dir "<dir>" \
  --output-format json --no-session-persistence \
  < "<dir>/prompt.md" > "<dir>/out.json" 2> "<dir>/stderr.txt"; echo $? > "<dir>/exit"
```

- `Edit` / `Write` / `NotebookEdit` を拒否するのは、書記が所見を出すだけの役割だから（直せない）。
  サブエージェントは親の権限を引き継ぐ（実測）ので、各観点にも効く。ただしシェル経由の書き込みは止めないので、
  保証は下のスナップショット。

指示文 `<dir>/prompt.md` に書くこと:

1. 差分の範囲（例: `origin/main...HEAD` と未コミットの変更）と契約
2. `SKILL.md`「レビュー招集ルール」の観点を、**Agent で同じターンに並列に**招集する。
   各観点の `subagent_type` と `model` は同節の表どおり指示文に書き写す（モデル階層ポリシー）。
   business / domain / プロダクト観点も、同節の条件に当たるものだけ書く
3. リポジトリ内のファイルを作らない・変更しない・コミットしない
4. 各観点の所見を**観点ごとに見出しを分けて**、そのまま最終応答に並べる（束ねて判定しない。判定は判事）。
   招集できなかった観点は「未取得（理由）」と書く

前後で改ざん検出のスナップショットを取る。コマンドは `herdr-backend.md`「3. 改ざん検出のスナップショット」と同じ。
**前後で一致しなければ、判事に進まず人間へ**（直さない・戻さない。`git status --short` を添える）。
一致すれば、`result.md` を書記の所見として判事に渡す証拠 (c) に含める。

## retro（Task を呼べない指揮のとき）

指揮が Claude Code なら retro は今どおり Task（`SKILL.md`「学ぶループ」）。
Task を呼べない指揮は、PR の URL が決まったら `--agent` で retro を直接起動する。

```bash
claude -p --agent dev-crew:retro --model sonnet \
  --permission-mode auto --permission-prompts none \
  --add-dir "<dir>" \
  --output-format json --no-session-persistence \
  < "<dir>/prompt.md" > "<dir>/out.json" 2> "<dir>/stderr.txt"; echo $? > "<dir>/exit"
```

- 指示文に渡す事実は `SKILL.md`「学ぶループ」1. と同じ（PR 番号・`trigger=pr-created`・司法の全ラウンドの判定出力・
  契約に無かった書記の所見・人間の介入）。人間の介入は、契約の合意後〜PR 作成までの人間の発言を**引用（`>`）で**渡す
  （許可プロンプトの承認は含めない）。**発言が無かったときは「介入: なし」と明示し、「不足」は引用できないときだけ**に使う
  （無いことと分からないことを区別する）。ほかの事実も、無いものは「不足」と書き、推測で補わない。
- `auto` にするのは、retro が下書きを一時ファイルに書くため（`dontAsk`＋許可リストでは下書きを作れなかった。実測）。
- **非ブロッキング。** 結果不明・失敗なら「Retro: 未取得（理由）」の1行を報告に添えるだけで、PR も報告も止めない。
  PR コメント・issue の投稿が `permission_denials` に残っていたら、それも「Retro: 未取得（投稿が拒否された）」として扱う
  （`auto` の外部への書き込みの判定は文脈に依存する。追跡中）。

## Task を呼べない指揮のときの置き場

| 役割 | 置き場 | 手順 |
|---|---|---|
| 行政 | `via: headless` または `via: herdr` | この文書「行政」／`herdr-backend.md` |
| 書記 | headless | この文書「書記」 |
| 判事 | `via: codex` または `via: herdr` | `codex-backend.md`／`herdr-backend.md` |
| retro | headless | この文書「retro」 |

- 判事の `via: codex` と行政の `via: headless` は**独立に組み合わせられる**（Claude が書き、Codex が裁く）。
- どの役割も、前提が欠けたら「止まって人間へ」（フォールバック先の Task が無い）。
- 指揮が Claude Code なら、`via: headless` を選んでも書記・retro・判事は今どおり（Task、または設定した方式）。

## 既知の制約

- **拒否ルールは保証ではない。** 前方一致なので `git -c k=v commit …` のような書き方で通る（実測）。
  保証は事後の確認（行政は HEAD・`git status` の取り直し、書記はスナップショット）。
- **拒否があっても成功で終わる。** `subtype: success` だけを見ると、拒否された操作を見落とす。
  `permission_denials` を必ず読む。
- **`auto` の外部への書き込みの判定は文脈に依存する。** retro の投稿が拒否されうる（追跡中）。
- **人間が途中を見られない。** ペインと違い、作業を目視して割り込めない。見たいなら行政は `via: herdr`。
- **cloud の routine（`loop-engine`）には適用しない。** この設定を読まない。
