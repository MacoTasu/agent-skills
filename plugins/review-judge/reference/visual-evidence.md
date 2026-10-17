# 見た目の証拠（before / after の動画）

> 司法(`review-judge:judge`)が**直接 Read する参照**（`verification-surfaces.md` と同じ参照型）。
> 実装 PR の本文に必ず置く **「🎬 見た目の証拠」節**の書式・該当の決め方・判定表・プロジェクト側の設定（config）・
> 指揮の添付手順を定める。録画の手順そのものは行政側（`dev-crew` 同梱
> `skills/implement/reference/record-visual-evidence.md`）にある。
>
> **動画は人間向けの成果物。司法は動画の中身を見ない。** 司法が検査するのは「節があるか」「申告が差分と一致するか」
> 「動画ファイルが実在するか」「録画シナリオを自分で実行して after が緑か」までで、映像の良し悪しは判定に使わない
> （人間がマージ判断で見るためのもの）。

## 節は必ず置く（「⚠️ 要注意の変更」と同じ型）

PR 本文の「⚠️ 要注意の変更」節の直後に **`## 🎬 見た目の証拠`** を置く。該当しなくても「該当なし」と書く＝
「確認して該当なし」と「確認し忘れ」を区別する。節は次の3状態のどれか1つ。

**録画あり**（UI に触れ、before / after を撮った）:

```
## 🎬 見た目の証拠
- base: <merge-base の SHA>（before の録画元）
- シナリオ: e2e/visual/settings-page.spec.ts（`npx playwright test --project=visual-evidence`）
- before: 対応画面なし（`設定リンクをクリック` で停止。404 が映っている）
- after: 緑（3 ステップ）
- 添付: before/settings-page.webm / after/settings-page.webm（side-by-side.mp4 は ffmpeg なしのため省略）
レビューで特に見てほしい点: 保存ボタンの活性化タイミング
```

before の行は **緑 ／ 対応画面なし（`<step>` で停止）／ 録画不能（<理由>）** のどれか。「対応画面なし」は**動画があるときだけ**
書ける（止まった step はログから取る。埋めればよい欄ではない）。動画が無ければ「録画不能」に理由を書く。

**該当なし**（差分が UI に触れない）:

```
## 🎬 見た目の証拠
該当なし（差分が `ui_paths` に触れない）
```

```
## 🎬 見た目の証拠
該当なし（UI サーフェスの宣言なし＝`.claude/visual-evidence.json` が無い）
```

**未録画**（UI に触れたが撮れなかった。理由を必ず書く）:

```
## 🎬 見た目の証拠
未録画: 実行環境にブラウザなし（UI に触れた差分: src/components/Settings.tsx）
```

未録画の理由の例: 配線なし（config はあるが `scenarios` に該当するシナリオが無い／`record` が走らない）、
実行環境にブラウザなし（cloud の loop など）、after の `record` が赤で止まった、判定不能（下記の計算が失敗した）。
**「録画が面倒だった」は理由にならず、理由の無い・曖昧な未録画は司法が RETRY にする**。撮れる環境では撮る。

添付できなかったときは「添付」の行にそう書く（後述の「添付手順」）。黙って省かない。

## 該当するかは「差分 ∩ `ui_paths`」で決める（決定性）

プロジェクトが `.claude/visual-evidence.json` の `ui_paths`（glob）で「何が UI か」を宣言する。
該当の判定は**差分のファイル一覧と `ui_paths` の交わりが空かどうか**だけ。推測しない。
行政・司法とも**未コミットの作業ツリーの状態**で計算するので、差分は base と作業ツリーの二点比較（`git diff <base>`）に
未追跡の新規ファイル（`git ls-files -o`）を足す（三点ドット `<base>...HEAD` はコミット済みしか見ず、検査が素通りする）。

**計算に使う config は base（merge-base）のもの**。検査される差分が `.claude/visual-evidence.json` 自体を狭める・消すと、
行政と司法が同じ式で両方「該当なし」を出して通ってしまうので、検査の前提を検査対象が書き換えられない形にする:

1. `git show "$base":.claude/visual-evidence.json` で base の config を読む（作業ツリーの config ではなく）。
2. **base に config が無く、差分が新しく加えた場合だけ**作業ツリーの config を使う（配線を足す PR。範囲を狭める方向には働かない）。
3. **差分が `.claude/visual-evidence.json` を変更・削除している**（base に存在し、`git diff --name-only "$base" -- .claude/visual-evidence.json` が非空）
   なら、計算は base の config で行い、「config の変更あり（人間の判断が要る）」と出す。行政は節の案にそう書き、
   司法は **ESCALATE**（検査の範囲を変える変更は人間の判断＝正典の不可侵と同じ扱い）。

**行政と司法は次の式をそのまま実行する**（同じ形で計算し、同じ所で止まる）:

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

- 出力は **該当（ファイル一覧）／該当なし（2種）／判定不能（理由）** に、config の注記（「config の変更あり」「config はこの差分で追加」）が
  付くことがある。**判定不能は「該当なし」ではない**:
  行政は「未録画: 判定不能（<理由>）」の案を返し、司法は RETRY にする（jq 無し・config 不正・`ui_paths` が空・base を解決できない、
  のどれも「UI に触れていない」ことを意味しない）。
- 配列を bash で組み `"${specs[@]}"` と引用して渡すのは、シェルの glob 展開と `xargs` の空入力（BSD は何も実行せず rc=0、
  GNU は pathspec 無しで全差分を返す）を避けるため。
- config が **base にも作業ツリーにも無ければ「該当なし（UI サーフェスの宣言なし）」**（CLI・ライブラリ・このハーネス自身など。
  jq が無くてもこの結論は出る）。判定不能になるのは **base を解決できないときだけ**（base が分からないと
  「base に config があり差分が消した」と「どこにも無い」を区別できない）。`git fetch` の失敗は手元の origin ref で
  続行し「注記: fetch 失敗」を付ける。これは**節の宣言**の話で、次とは別のこと。
- config が無くても、**既存のフロント規則はそのまま効く**（`verification-surfaces.md`: 拡張子から front と推定されれば
  視覚・挙動の証拠を要求する）。そのうえで司法は所見に「UI らしい差分なのに `ui_paths` の宣言が無い」と書く。

## 判定表（司法）

| 差分 ∩ `ui_paths` | 節の宣言 | 判定 |
|---|---|---|
| 空 | 該当なし | 通す |
| 非空 | 該当なし | **RETRY**（申告不一致。要注意の変更の申告漏れと同じ扱い） |
| 非空 | 録画あり | 次が**全部**揃えば通す。欠ければ **RETRY**: ① after の動画が手元のパスに実在しサイズ > 0 ② before の動画が実在する、**または** before の行が「対応画面なし（`<step>`）」／「録画不能（<理由>）」で理由つき（決定性に確かめられる理由＝「base に録画 project なし」は base の `playwright.config.*` を見て司法が確かめる。毎回「録画不能」なら所見に出す） ③ 司法が `record` を自分で実行して after が緑 |
| 非空 | 未録画 | **未録画だけで PASS にはならない**（フロントの証拠不足）。理由で分ける: 「配線なし」→ config の `scenarios` / `record` とシナリオの実在を司法が確かめ、実在すれば申告不一致で **RETRY**。「実行環境にブラウザなし」など**再試行で変わらない環境要因** → N=3 を回さず**初回で ESCALATE**。理由が無い・曖昧 → **RETRY**。constitution に見た目の証拠の MUST があれば **ESCALATE** |
| 判定不能 | — | **RETRY**（計算が「jq が無い（config があるのに読めない）」「config 不正」「base を解決できない」で止まった。「該当なし」に倒さない。行政の申告が「未録画: 判定不能」でも司法は自分で計算し直す） |
| 差分が `.claude/visual-evidence.json` を変更・削除（base に存在） | — | **ESCALATE**（計算は base の config で行う。検査の範囲を変える変更は人間の判断＝正典の不可侵と同じ扱い。行政の節に「config の変更あり」が無くても、式の出力にあれば ESCALATE） |
| — | 節が無い（本文案は渡された） | **RETRY** |
| — | PR 本文案そのものが渡されていない | 司法が差分 ∩ `ui_paths` を自分で計算する。**非空なら RETRY**（UI に触れているが本文案が無く未検査。本文案を求める）。空なら「対象外」と明記して進む |
| config 無し・拡張子から front と推定 | 該当なし（宣言なし） | 節の宣言としては正しい。それとは別に既存のフロント規則（視覚・挙動の証拠の要求）はそのまま効き、所見で「UI らしい差分なのに `ui_paths` の宣言が無い」と指摘する |

- **厳しさの最終決定はプロジェクトの constitution に置く**。ハーネスが強制するのは
  「必ず節を書く・嘘を書かない・撮れる環境では撮る」まで。
- 動画の実在確認は **PASS 前の手元のパスだけ**で行う（司法は添付の前に動く。行政が置いた worktree 外の一時ディレクトリ）。
  司法の環境からそのパスが見えない、または `record` を自分で実行できない（ブラウザが無い）ときは
  **「未検証」と明記して PASS しない**（RETRY。恒常的に実行できない環境なら ESCALATE）。
- 「録画あり」の検査で司法が実行するのは `record`（after＝今の作業ツリー）だけ。before を撮り直す必要はない。

## before に対応画面が無いとき（新機能）

スキップしない。before（merge-base）でも**同じシナリオを必ず走らせ**、止まった段階をログから取って記録する:
「before: 対応画面なし（`<step>` で停止）」。404 や旧画面が映った動画は「無かった」ことの証拠になる。
動画が1本も出なかったときは「対応画面なし」ではなく「録画不能（<理由>）」（例: base に録画 project なし／webServer が起動しない）。
**after は緑でなければならない**（after が赤なら未録画として理由を書く＝実装が終わっていない）。

## config: `.claude/visual-evidence.json`

雛形は `loop-engine` 同梱 `reference/visual-evidence.json.example`（`/loop-engine:init` が有無と必須キーを確認して案内する。書かない）。
JSON なのでコメントは書けない。各キーの意味はここが正。**計算に使うのは base の config**（上記）。config を変える PR は
それ自体が人間の判断を要する（ESCALATE）ので、UI の変更とは別の PR にする。

| キー | 必須 | 意味 |
|---|---|---|
| `ui_paths` | 必須・**非空** | UI とみなすパスの glob の配列。差分との交わりで「該当」を決める。**空配列は config 不正＝判定不能** |
| `scenarios` | 必須 | 録画シナリオ（Playwright テスト）の glob の配列。例 `e2e/visual/**/*.spec.ts`。行政はここに置く・更新する |
| `record` | 必須 | 録画を実行するコマンド1つ。例 `npx playwright test --project=visual-evidence`。**まっさらな worktree でこのコマンド1つで走る**ことが契約 |
| `setup` | 任意 | before の一時 worktree で `record` の前に実行する準備。例 `npm ci` |
| `max_attach_mb` | 任意 | 添付する動画1本の上限 MB。既定 **10**（GitHub の free プランの動画上限）。超えるファイルは添付せず手元の場所を本文に書く |

プロジェクト側に必要なもの: Playwright の録画用 project（`video: 'on'`、`webServer` でアプリを起動）と、
`scenarios` に置く通常のテスト。**録画シナリオ＝フロントの挙動テスト**なので二重管理にならない。
ハーネスは録画コマンドを持たない（hooks と同じ: プロジェクトが `record` を宣言する）。

## 添付手順（指揮向け）

添付するのは**指揮**（`conductor` / `loop-engine`）で、司法の PASS の後に行う。行政は撮って場所を返すだけ。
`--attach` は **gh 2.99.0 以上**で `gh pr create / edit / comment`（と `gh issue …`）に付く。対応形式は PNG / JPEG / GIF / WebP / SVG /
MP4 / MOV / WebM、動画は free プランで 1 本 **10MB**、paid で **100MB**（画像・GIF は 10MB）。認証は gh の通常のトークン
（OAuth・classic PAT）。GHES では使えない。private リポジトリの添付はリポジトリの閲覧権限で制御される。

1. 版番号ではなく**機能検出**で確かめる: `gh pr create --help | grep -q -- '--attach'`。
2. `max_attach_mb`（既定 10）以内のファイルだけを添付する。

```bash
gh pr create --help | grep -q -- '--attach' || echo "添付不可（gh が --attach を持たない）"
gh pr create --title "<題>" --body-file <本文ファイル> \
  --attach <一時dir>/before/<名>.webm --attach <一時dir>/after/<名>.webm \
  [--attach <一時dir>/side-by-side.mp4]
```

3. 作成後に本文を読み戻し、添付の URL が入っていることを確かめる:
   `gh pr view <番号> --json body -q .body | grep -c user-attachments`。入っていなければ `gh pr edit <番号> --body-file <本文>` で
   「添付」の行に理由と手元の場所を書き直し、人間に伝える（司法に渡した本文との差はこの行だけ）。
4. 添付できないときは**本文の「添付」の行に理由と手元の場所を書く**。黙って省かない:
   - `gh` が `--attach` を持たない → `添付不可（gh に --attach なし）。手元 <path>`。PR 作成後に人間へ `gh` の更新（2.99.0 以上）を案内する
     （更新後に `gh pr comment --attach <path>` で後から添付できる）。
   - 上限超過 → `サイズ超過（<size>MB）。手元 <path>`。行政は次回 `record` の解像度・長さで上限内に収める。
   - `gh` が無い環境（cloud の loop）→ `添付不可（gh なし）。手元 <path>`（cloud では通常そもそも未録画になる。後述）。
5. `/commit-commands:commit-push-pr` のように `gh pr create` を自分で打たない経路で PR を作ったときは、作成後に
   `gh pr comment --attach <動画>…` で添付する（本文には「添付: コメント参照」と書く）。

## cloud（ブラウザが無い環境）

cloud の `loop-engine` はブラウザを起動できないので、行政は「未録画: 実行環境にブラウザなし」と申告する。
司法は**再試行で変わらない環境要因**として初回で ESCALATE する（N=3 ラウンドの opus を無駄にしない）。
UI に触れる仕様は人間が手元で `/conductor:dev` を回すか、下の CI 録画で補う。

## CI 録画（プロジェクトの任意）

録画を CI（PR の workflow）で取り、artifact や PR コメントに置く構成はプロジェクトの任意。ハーネスは雛形を持たない
（各プロジェクトに「2ブランチ分のアプリを CI で起動する workflow」を求めるのは重く、行政が動く worktree には
すでにアプリを起動できる環境があるため）。CI 録画を持つプロジェクトでも節の書式と判定表は同じで、
「添付」の行に CI の成果物の場所を書く。
