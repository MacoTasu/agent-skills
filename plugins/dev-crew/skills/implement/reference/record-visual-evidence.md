# 見た目の証拠を撮る（行政の手順）

> `dev-crew:implement` の後の確認「見た目の証拠（UI に触れたとき）」の手順。
> 書式・判定表・config のキーの正は **`review-judge` 同梱 `reference/visual-evidence.md`**（司法が同じものを読む）。
> ここは「どう撮るか」だけ。

**撮るのは行政、添付するのは指揮、申告と実物の一致を検査するのが司法。** 動画は人間がマージ判断で見るための
成果物で、司法は中身を見ない。行政がここで返すのは「節の案」と「動画ファイルの場所」まで。

> 下のコードブロックは `$cfg` `$out` `$base` `$before_dir` などの変数と関数 `fail` を共有する。**ツールのシェルは呼び出し間で状態を持たない**ので、
> 値を控えて次の呼び出しで再設定するか、1 回の実行にまとめる。

## 0. 前提

- 対象リポジトリに `.claude/visual-evidence.json` があること（base または作業ツリー。1. の式が判定する）。
  **base にも作業ツリーにも無ければ「該当なし（UI サーフェスの宣言なし）」の案を返して終わり**（CLI・ライブラリ・ハーネス自身など。
  jq が無くてもこの結論は出る。判定不能になるのは base を解決できないときだけ）。拡張子から UI らしく見えても、宣言が無い限り録画は求められていない。
- ブラウザが起動できる環境であること。cloud の loop など起動できない環境では、1. で該当と分かった時点で
  **「未録画: 実行環境にブラウザなし（UI に触れた差分: …）」**の案を返す。嘘を書かない。

## 1. 差分 ∩ `ui_paths` を計算する（司法と同じ式）

`visual-evidence.md`「該当するかは『差分 ∩ ui_paths』で決める」の式を**そのまま**実行する（再掲）。
失敗は「該当なし」に倒れず「判定不能」で止まる（判定不能になるのは jq が無いのに config がある・config 不正・base を解決できない、のとき。
config がどこにも無ければ jq が無くても「該当なし（宣言なし）」。`git fetch` の失敗は手元の origin ref で続行し注記を付ける）。
**config は base（merge-base）のものを読む**: 自分の差分が
`.claude/visual-evidence.json` を狭める・消すと検査の前提が変わってしまうので、作業ツリーの config を使うのは
base に config が無く、この差分で新しく加えた場合だけ。base に config があって差分がそれを変更・削除していれば、
計算は base の config で行い、節の案に「config の変更あり（人間の判断が要る）」と書く（司法は ESCALATE する）。

```bash
set -o pipefail
fail() { echo "判定不能: $*"; exit 2; }        # 失敗を「該当なし」に倒さない
# ① base の解決。fetch に失敗しても手元の origin ref があれば注記を付けて続行する。ref がどこにも無ければ判定不能
note=""
git fetch origin >/dev/null 2>&1 || note="注記: fetch 失敗（手元の origin ref を使用）"
base_ref=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
base=$(git merge-base "$base_ref" HEAD 2>/dev/null) || fail "base を解決できない（${base_ref}）"
# ② config の有無を jq なしで判定。base のものを読む（検査される差分が検査の前提を狭められないように）。base に無く差分が足した場合だけ作業ツリーのもの
cfg=$(mktemp) || fail "mktemp が失敗"
cfg_note=""
if git show "$base":.claude/visual-evidence.json >"$cfg" 2>/dev/null; then
  [ -z "$(git diff --name-only "$base" -- .claude/visual-evidence.json)" ] || cfg_note="config の変更あり（人間の判断が要る）"
elif [ -f .claude/visual-evidence.json ]; then
  cp .claude/visual-evidence.json "$cfg" || fail "config を読めない"; cfg_note="config はこの差分で追加"
else
  [ -n "$note" ] && echo "$note"
  echo "該当なし（UI サーフェスの宣言なし）"; exit 0          # ③ どこにも無ければ jq 不要で終わり
fi
# ④ ここから先で初めて config を読む
command -v jq >/dev/null 2>&1 || fail "jq が無い（config があるのに読めない）"
jq -e '(.ui_paths|type=="array" and length>0) and (.scenarios|type=="array") and (.record|type=="string" and length>0)' "$cfg" >/dev/null 2>&1 \
  || fail "config が不正（ui_paths は非空配列、scenarios は配列、record は非空文字列）"
specs=(); while IFS= read -r p; do [ -n "$p" ] && specs+=(":(glob)$p"); done < <(jq -r '.ui_paths[]' "$cfg")
[ "${#specs[@]}" -gt 0 ] || fail "ui_paths を読めない"
hits=$( { git diff --name-only "$base" -- "${specs[@]}" && git ls-files -o --exclude-standard -- "${specs[@]}"; } | sort -u ) \
  || fail "git diff / ls-files が失敗"
[ -n "$note" ] && echo "$note"
[ -n "$cfg_note" ] && echo "$cfg_note"
if [ -n "$hits" ]; then echo "該当:"; echo "$hits"; else echo "該当なし（差分が ui_paths に触れない）"; fi
```

- **該当なし（2種）なら、その文言の案を返して終わり。**
- **判定不能なら「未録画: 判定不能（<理由>）」の案を返して終わり**（司法は RETRY にする。嘘の「該当なし」を書かない）。
- **「config の変更あり」が出たら**、以降は base の config（`$cfg`）で進め、節の案の先頭に「config の変更あり（人間の判断が要る）」と書く。
- 該当なら `$hits` の一覧を控えて 2. へ（節の案と「未録画」の理由に使う）。残りの config も `$cfg`（base のもの）から読む:

```bash
record=$(jq -r '.record' "$cfg")
setup=$(jq -r '.setup // empty' "$cfg")
max_mb=$(jq -r '.max_attach_mb // 10' "$cfg")
out=$(mktemp -d) || fail "mktemp が失敗"   # worktree 外の一時ディレクトリ。動画・ログ・状態はすべてここ
```

## 2. 録画シナリオを用意・更新する

シナリオは `scenarios` の glob 配下に置く**通常の Playwright テスト**（録画シナリオ＝フロントの挙動テスト。二重管理にしない）。
変更した画面に対応するシナリオが無ければ作り、あれば変更に合わせて更新する。
司法は後でこのシナリオを自分で実行して緑を確かめるので、**録画のためだけの手順（待ち時間など）は最小限**にする。

用意できたら、該当するシナリオを**存在するものだけ**列挙して控える（before への複製と節の案に使う。
`git ls-files` は作業ツリーで削除済みのファイルも返すので `[ -e ]` で絞る）:

```bash
sspecs=(); while IFS= read -r p; do [ -n "$p" ] && sspecs+=(":(glob)$p"); done < <(jq -r '.scenarios[]' "$cfg")
git ls-files -z --cached --others --exclude-standard -- "${sspecs[@]}" \
  | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done > "$out/scenarios.nul"
[ -s "$out/scenarios.nul" ] || echo "未録画: 配線なし（scenarios に該当するシナリオが無い）"   # → 案を返して終わり。3. に進まない
```

プロジェクト側の前提（無ければ「未録画: 配線なし（<何が無いか>）」として返す。行政がプロジェクトの Playwright 設定を
勝手に組み替えない）:

- `playwright.config.*` に録画用の project（例 `visual-evidence`）があり、`use: { video: 'on' }` と、
  アプリを起動する `webServer` を持つ。
- `record` コマンド（例 `npx playwright test --project=visual-evidence`）が、**まっさらな worktree でこの1つで走る**。

## 3. after を録画する（自分の worktree）

Playwright の動画は**テストごとのディレクトリの中の `video.webm`** で同名になる。テストのディレクトリ名を付けて一意に移す。
出力ディレクトリは `test-results/` を既定とし、プロジェクトの `outputDir` が違えばそれに従う（以下の `test-results` を読み替える）。

```bash
collect() {   # $1 = Playwright の出力ディレクトリ, $2 = 置き先。<テストdir名>.webm で一意にする
  mkdir -p "$2"
  find "$1" -name '*.webm' -print0 2>/dev/null \
    | while IFS= read -r -d '' v; do mv "$v" "$2/$(basename "$(dirname "$v")").webm"; done
}
rm -rf test-results   # 古い動画を after として拾わない。Playwright の outputDir は実行ごとに消される生成物なので安全。別の用途に使うプロジェクトなら読み替える
sh -c "$record" >"$out/after.log" 2>&1; echo "after rc=$?" >"$out/after.status"
collect test-results "$out/after"
cat "$out/after.status"; find "$out/after" -name '*.webm' -size +0 | wc -l
```

- **after は緑（rc=0）でなければならない**。rc≠0 なら実装が終わっていない。直してから撮り直す。直せなければ
  「未録画: after の `record` が赤（<`after.log` から失敗したテスト>）」として返す。
- 動画が1本も出なければ `video: 'on'` の project を使っていない（2. の前提の不備）。「未録画: 配線なし（録画 project なし）」。

## 4. before を録画する（merge-base の一時 worktree）

```bash
before_root=$(mktemp -d) || fail "mktemp が失敗"   # worktree の外に置く
before_dir="$before_root/before-worktree"
if ! git worktree add --detach "$before_dir" "$base" >"$out/before.log" 2>&1; then
  echo "before=worktree_add_failed" >"$out/before.status"           # 以降は走らせない
elif ! tar -c --null -T "$out/scenarios.nul" -f - | tar -x -C "$before_dir" -f -; then
  echo "before=copy_failed" >"$out/before.status"                   # head のシナリオの複製に失敗（pipefail 下なので tar のどちらの失敗も拾う）
else
  (
    cd "$before_dir" || { echo "before=cd_failed" >"$out/before.status"; exit 1; }   # cd に失敗したら setup/record を絶対に走らせない
    if [ -n "$setup" ] && ! sh -c "$setup" >"$out/before-setup.log" 2>&1; then
      echo "before=setup_failed" >"$out/before.status"; exit 0                        # setup が失敗したら record は走らせない
    fi
    rm -rf test-results
    sh -c "$record" >"$out/before.log" 2>&1; echo "before=record rc=$?" >"$out/before.status"   # 終了コードと出力を残す（捨てない）
  )
  collect "$before_dir/test-results" "$out/before"
fi
case "$before_dir" in "$before_root"/*) [ -d "$before_dir" ] && git worktree remove --force "$before_dir" ;; esac   # 自分が作った一時 dir の中だけ消す
rm -rf "$before_root"
cat "$out/before.status"; find "$out/before" -name '*.webm' -size +0 2>/dev/null | wc -l
```

`cd` を `|| exit` で守るのは、失敗して**元の worktree で `npm ci` や `record` が走ると行政自身の環境を壊す**ため。

**before の行は `before.status` と動画の有無で分類する**（埋めればよい欄ではない）:

| `before.status` | 動画 | before の行 |
|---|---|---|
| `record rc=0` | あり | 緑 |
| `record rc≠0` | **あり** | 対応画面なし（`<step>` で停止）— step は `before.log` の失敗したテストの出力から取る |
| `record rc≠0` | なし | 録画不能（<理由を `before.log` から: record 自体が失敗・webServer が起動せず など>） |
| `record rc≠0` で base に録画 project が無い（この PR で配線を足した場合） | なし | 録画不能（base に録画 project なし）— `git show "$base":playwright.config.ts` に project が無いことを確かめて書く |
| `setup_failed` | — | 録画不能（setup が失敗: <`before-setup.log` の要約>） |
| `worktree_add_failed` / `cd_failed` | — | 録画不能（worktree 作成失敗: <`before.log` の要約>） |
| `copy_failed` | — | 録画不能（シナリオの複製に失敗） |

- **before に対応画面が無くてもスキップしない。** 「対応画面なし」は**動画があるときだけ**。404 や旧画面が映った動画が「無かった」ことの証拠になる。
- before が「録画不能」でも節は「録画あり」で書き、before の行に理由を書く（after が緑で実在する限り）。
- `git worktree remove` を忘れない。残ると次の `git worktree add` が衝突し、他のセッションの邪魔になる。
  途中で止まったら `git worktree prune` と `$before_root` の削除で後始末する。

## 5. 任意: ffmpeg で並べる

`ffmpeg` があれば before と after を横に並べた1本を作る（同じ `<テストdir名>` の組ごと、または代表1組）。
無ければ作らない。before / after を別々に添付すれば GitHub が2つのプレイヤーを縦に並べる。**ffmpeg を必須にしない。**

```bash
if command -v ffmpeg >/dev/null; then
  if ! ffmpeg -y -i "$out/before/<名>.webm" -i "$out/after/<名>.webm" \
       -filter_complex "[0:v]scale=-2:720[l];[1:v]scale=-2:720[r];[l][r]hstack=inputs=2" \
       -c:v libx264 -pix_fmt yuv420p "$out/side-by-side.mp4" >"$out/ffmpeg.log" 2>&1 \
     || [ ! -s "$out/side-by-side.mp4" ]; then
    rm -f "$out/side-by-side.mp4"      # 節には「side-by-side.mp4 は ffmpeg 失敗のため省略」と書く
  fi
fi
```

`scale=-2:720` で高さを揃える。`hstack` の既定（`shortest=0`）では出力は長い方の長さになる。先に終わった側がどう映るか
（最終フレームの繰り返しか）は ffmpeg の版で確かめる。サイズ 0 のファイルを「あり」にしない。

## 6. サイズと実在を確かめ、節の案を返す

```bash
find "$out" -name '*.webm' -o -name '*.mp4' | while read -r f; do [ -s "$f" ] && du -m "$f"; done
```

- 節の案に載せるのは**実在しサイズ > 0 のファイルだけ**。
- `max_attach_mb`（既定 10）を超えるファイルは添付されない。節の案の「添付」に「サイズ超過（<size>MB）。手元 <path>」と書き、
  次回は `record` の解像度（`viewport`）・シナリオの長さで上限内に収める。
- 「返す形式」の `## 🎬 見た目の証拠（案）` に、書式どおり（`visual-evidence.md`）書く:
  base の SHA、シナリオのパスと `record` コマンド、before の行（上の分類表）、after の結果（緑・ステップ数）、
  動画ファイルの一覧（`$out` 配下のパスとサイズ）、`side-by-side.mp4` の有無。1. で「config の変更あり」が出ていれば先頭にそれを書く。
- 指揮がこの案を「⚠️ 要注意の変更」と合わせて PR 本文案にし、司法に渡し、PASS で `gh pr create --attach` する。
  行政は添付も PR 作成もしない。

## してはいけないこと

- **動画をリポジトリにコミットする／`.gitignore` を触る**。動画は `$out`（worktree 外）に置くだけ。
- **before を省く**（「新機能だから before は無い」は記録であって省略の理由ではない）。
- **UI に触れたのに「該当なし」と書く／計算が失敗したのに「該当なし」と書く**。該当は差分 ∩ `ui_paths` で決まり、司法が同じ式で計算する。失敗は「判定不能」。
- **「対応画面なし」を動画無しで書く**。動画が無ければ「録画不能（理由）」。
- **撮れなかった理由を曖昧にする**。「未録画」には必ず理由（配線なし／実行環境にブラウザなし／after が赤／判定不能）と、UI に触れた差分の一覧を書く。
- **プロジェクトの Playwright 設定を勝手に組み替える**。録画用 project が無いのはプロジェクトの配線の不備で、行政はそれを「未録画: 配線なし」として返す（直すのは人間の判断）。
