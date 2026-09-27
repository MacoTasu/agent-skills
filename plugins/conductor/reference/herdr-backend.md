# 実行方式: herdr ペイン

行政（implement）と司法（judge）を、Task サブエージェントではなく
[herdr](https://herdr.dev) の**隣のペインで動く別の AI コーディングツール**に担わせる手順。
**任意の実行方式**で、既定は Task のまま。

## なぜペインに出すのか

- **司法を別ベンダーのモデルにできる。** 書いたモデルと採点するモデルが同じだと、同じ盲点を
  両方が共有する。判事を別系統（例: GitHub Copilot CLI）にすると、この偏りが構造的に消える。
  Task では同じ Claude の中でしか分けられない。
- **行政の作業が見え、途中で割り込める。** 長い実装を人間がペインで直接見て、方向修正できる。

出すのは**行政と司法の2つだけ**。書記（pr-review 6観点など）は短く機械的なので Task のまま
にする。6ペインに広げても、画面が埋まり承認待ちの停止点が増えるだけで得るものが無い。

## 設定

対象リポジトリの `.claude/conductor.json`（任意。無ければ全役割 Task）:

```json
{
  "backends": {
    "implement": { "via": "herdr", "kind": "claude", "model": "opus" },
    "judge":     { "via": "herdr", "kind": "copilot" }
  }
}
```

| キー | 意味 |
|---|---|
| `via` | `task`（既定）/ `herdr` |
| `kind` | ペインで起動するツール。herdr の `agent start --kind` の値 |
| `model` | 任意。ツールの `--model` にそのまま渡す（モデル階層ポリシーの代わり） |

**対応している `kind`**（起動引数で書き込み制限を検証できたものだけ）:

| 役割 | kind |
|---|---|
| implement | `claude` |
| judge | `copilot` / `claude` |

表に無い組み合わせは **Task にフォールバック**する（未検証の起動引数を推測で渡さない）。

## フォールバック条件（1つでも欠けたら Task）

招集の直前に毎回検査し、欠けたら**理由を1行表示して Task で続行**する。黙って切り替えない。

```bash
test "${HERDR_ENV:-}" = 1            # herdr のペインの中で動いている
command -v herdr                      # herdr がある
command -v <kind>                     # 指定ツールがある（copilot / claude）
```

加えて、`kind` が上の対応表にあること。judge なら後述の `judge.md` が見つかること。

- **cloud の routine（`loop-engine`）には適用しない。** herdr が無く、この設定も読まない。
- herdr の外（普通の端末）から herdr のセッションを操作しない。`HERDR_ENV` の検査はそのため。

## 共通: ペインを開いてツールを起動する

```bash
# 1. 隣にペインを開く。フォーカスは奪わない。作業ディレクトリは今と同じ
herdr pane layout --pane "$HERDR_PANE_ID"            # 横長なら right、縦長なら down
herdr pane split --current --direction right --cwd "$PWD" --no-focus
#    → .result.pane.pane_id を控える（推測しない）

# 2. ツールを起動する。名前は役割＋契約 slug（[a-z][a-z0-9_-]{0,31}）
herdr agent start <name> --kind <kind> --pane <pane_id> -- <起動引数>
```

- 名前は `impl-<slug>` / `judge-<slug>`。32文字を超えるなら slug を切り詰める。
- **指示文は一時ファイルに書き、ペインには「そのファイルを読んで従え」とだけ送る。**
  長い指示をペインに流すと、画面の読み取りで自分の指示文と相手の出力が混ざるため。
  置き場所は `mktemp -d` で作る一時ディレクトリ（リポジトリの外。`.claude/` にも書かない）。
- 自分が開いたペイン以外は閉じない。

## 行政（implement）

起動引数（`kind: claude`）:

```bash
-- --add-dir "<指示文の一時ディレクトリ>" [--model <model>]
```

指示文ファイルに書くこと:

1. `/dev-crew:implement` を実行し、その手順に従う（同じユーザー環境なのでスキルが使える）
2. 契約のパス `./goals/<YYYYMMDD-slug>.md`
3. **司法を呼ばない・合否を宣言しない**（implement の職責どおり。念押し）
4. 最後は implement の「返す形式」で終える

```bash
herdr agent prompt impl-<slug> "<指示文ファイルのパス> を読んで、その指示に従ってください。" --wait --timeout 540000
```

- **`blocked`（承認待ち）で返ったら、代わりに答えない。** 「`impl-<slug>` のペインで承認待ちです」と
  人間に伝え、`herdr agent wait impl-<slug> --until idle --until done` で再び待つ。
- 実装は Bash のタイムアウト（最大10分）を超えうる。超えたら `herdr agent wait` を
  再発行して待ち続ける（タイムアウトは未完了を意味しない。**同じ指示を再送しない**）。
- 終わったら `herdr agent read impl-<slug> --source recent-unwrapped --lines 400` で
  「決定性の結果」を読み、証拠 (c) として扱う。
- REJECT / RETRY の差し戻しは、**同じペイン**に指摘を送る（文脈を引き継げるのが利点）。

## 司法（judge）

### 分離の担保（最重要）

Task の判事は **`Edit` / `Write` ツールを持たない**ことで「直せない」を構造的に強制している。
ペインのツールは何でも書ける。そこで**起動引数での禁止**と**事後の改ざん検出**を重ねる。

**起動引数での禁止だけでは足りない。** Copilot CLI の `--deny-tool write` はファイル編集
ツールを止めるが、**シェル経由の書き込み（`echo >` や `sed -i`）は止めない**（help に
"except shell tool invocations" と明記。Copilot CLI 1.0.88 で実測: ファイル編集ツールでの作成は
拒否され、`echo y > b.txt` は成功した）。判事はテストを走らせるためシェルを外せない。
よって**保証の本体は改ざん検出**で、起動引数は事故を減らす層に過ぎない。

**判事の自己申告も当てにしない。** 同じ実測で、ツールは「両方の書き込みが阻止された」と報告
しながら、同じ応答の中で b.txt の作成成功も認めていた。書き込んだかどうかは、判事の言葉ではなく
作業ツリーの比較で決める。

### 1. judge.md を見つける

判事の手順書は `review-judge` プラグインの `agents/judge.md`。conductor の隣にある
（インストール時は `<marketplace>/review-judge/<version>/`、リポジトリ直下では `plugins/review-judge/`）:

```bash
find "${CLAUDE_PLUGIN_ROOT}/.." "${CLAUDE_PLUGIN_ROOT}/../.." -maxdepth 4 \
     -path '*/review-judge*/agents/judge.md' 2>/dev/null \
  | while IFS= read -r f; do (cd "$(dirname "$f")/.." && pwd); done \
  | sort -uV | tail -1
```

グロブではなく `find` を使うのは、zsh では一致しないグロブがエラーで止まるため。

見つからなければ Task にフォールバックする（判事の定義なしに判定させない）。
見つかったディレクトリを `<judge_root>` と呼ぶ。

### 2. 起動引数

`kind: copilot`:

```bash
-- --add-dir "<judge_root>" --add-dir "<指示文の一時ディレクトリ>" \
   --allow-all-tools --no-ask-user \
   --deny-tool=write \
   --deny-tool='shell(git commit)' --deny-tool='shell(git push)' \
   --deny-tool='shell(git reset)' --deny-tool='shell(git checkout)' \
   --deny-tool='shell(git switch)' --deny-tool='shell(git restore)' \
   --deny-tool='shell(git stash)' --deny-tool='shell(git clean)' \
   --deny-tool='shell(git apply)' --deny-tool='shell(git rebase)' \
   --deny-tool='shell(git merge)' --deny-tool='shell(gh:*)' \
   [--model <model>]
```

- 拒否は許可より優先される（`--allow-all-tools` と併用しても拒否が勝つ）。
  `--allow-all-tools` は承認待ちでペインが止まらないようにするため。
- `--deny-tool` は可変長引数なので、**`=` で1つずつ**渡す（後続の引数を飲み込ませない）。
- `gh` を丸ごと拒否するのは、`gh api` が書き込み（POST）を持つため。CI の結果が要るなら
  conductor が先に取得して証拠 (c) に入れる。

`kind: claude`:

```bash
-- --add-dir "<judge_root>" --add-dir "<指示文の一時ディレクトリ>" \
   --disallowedTools Edit Write NotebookEdit [--model <model>]
```

### 3. 改ざん検出のスナップショット

判事を呼ぶ**直前**と、判定を読んだ**直後**に同じコマンドを実行し、出力（1行のハッシュ）を比べる:

```bash
{
  git rev-parse HEAD
  git symbolic-ref -q HEAD
  git diff HEAD --binary
  git ls-files -o --exclude-standard | while IFS= read -r f; do
    printf '%s\n' "$f"; git hash-object -- "$f"
  done
} | git hash-object --stdin
```

- HEAD・ブランチ・追跡ファイルの差分・**未追跡の新規ファイル**（未コミットの実装で作られた
  ファイルを含む）の中身を1つに畳む。gitignore された生成物（テストの出力など）は含めない。
- **前後で一致しなければ、判定の内容に関わらず `ESCALATE`（判事が作業ツリーを変更した）**。
  どちらのハッシュかと `git status --short` を添えて人間に渡す。直さない・戻さない
  （何が変わったかを人間が見る前に消さない）。
- テストが gitignore されていないファイルを生成するリポジトリでは誤検知で ESCALATE になる。
  これは安全側の失敗なので許容する（見逃しよりよい）。

### 4. 指示文と招集

指示文ファイルに書くこと:

1. `<judge_root>/agents/judge.md` を読み、**frontmatter より下を自分の役割として従う**。
   文中の `${CLAUDE_PLUGIN_ROOT}` は `<judge_root>` に読み替える
2. (a) 契約のパス、(b) 差分の範囲、(c) 証拠（行政の決定性結果・書記の所見・CI の結果）
3. ファイルを作らない・変更しない・コミットしない（judge.md の分離原則の念押し）
4. **出力の最後の行は `VERDICT: <判定>` の1行だけにする**（`<判定>` は PASS / REJECT /
   RETRY / ESCALATE のどれか1語。見出しや装飾を付けない）

```bash
herdr agent prompt judge-<slug> "<指示文ファイルのパス> を読んで、その指示に従ってください。" --wait --timeout 540000
herdr agent read judge-<slug> --source recent-unwrapped --lines 400
```

- 判定は、読み取った出力の中で**最後に現れる** `VERDICT: (PASS|REJECT|RETRY|ESCALATE)` の行から取る。
  最後の行を指定するのは、TUI が markdown の見出し（`##`）を描画して記号を消すことがあるため。
- **判定行が読み取れなければ `RETRY`（証拠不足）として扱う。** PASS に倒さない（judge の
  「証拠が無ければ PASS しない」と同じ理屈）。ペインを人間に見てもらうよう案内する。
- **判事は毎回まっさらな文脈で呼ぶ。** 前の判定の文脈を引きずると独立性が落ちるので、
  同じ契約の2回目以降は、前回自分が開いた `judge-<slug>` のペインを閉じてから開き直す。
  ペインは判定後も残し、人間が読めるようにする。
- 判定の後のルーティング（PASS → ship など）は Task の判事と同じ。指揮は判定を上書きしない。

## 既知の制約

- **判事の分離は「構造的に不可能」から「禁止＋事後検出」に弱まる。** 検出はするので
  変更された判定が PASS として通ることはないが、判事が作業ツリーを変えること自体は起こりうる。
  この差を受け入れられないなら、judge は `via: task` のままにする。
- 画面の読み取りに依存する。ツールが代替スクリーン（alternate screen）で描画していて
  `--lines` を増やしても出力を遡れない場合は、判定行を読み取れず RETRY になる。
- 承認待ち（`blocked`）には人間が答える。指揮が代わりに承認しない。
