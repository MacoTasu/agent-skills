---
name: spec-draft
description: |
  GitHub issue から変更ユニット spec（./goals/YYYYMMDD-slug.md）を起草し、PR にするスキル。
  昇格プロトコルの「② spec 執筆」だけを担う（③ Spec: コメント・④ loop-ready label は
  spec が main にマージされた後に人間が行う）。起草できない issue は拒否して /conductor:dev へ回す。
  手動起動: /spec-intake:spec-draft <issue番号>。
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Write
  - Edit
  - Task
---

# /spec-intake:spec-draft — issue から spec を起草して PR にする

`/loop-engine:loop-engine` が **spec を実行する**のに対し、これは **spec を作る**。役割が違うので別コマンド。

昇格プロトコル（`loop-engine` skill の「issue 経由の起動」）のうち、**② だけ**を担当する:

| # | 誰 | やること | このコマンド |
|---|---|---|---|
| ① | 人間 | issue で議論する | 対象外 |
| **②** | 人間 / **本コマンド** | **spec `goals/YYYYMMDD-slug.md` を書いて PR → main マージ** | **✅ ここ（PR 作成まで。マージは人間）** |
| ③ | 人間 | issue に `Spec: goals/...md` コメント投稿 | 対象外（最後に貼れる形で出力する） |
| ④ | 人間 | issue に `loop-ready` label 付与 | 同上 |
| ⑤ | 人間 | `/loop-engine:loop-engine <issue番号>` | 対象外 |

> **なぜ ③④ をやらないか**: G1 は spec が **main にマージ済み**であることを要求する。マージ前に
> label を付けると `/loop-engine:loop-engine <N>` が main に無い spec を指して落ちる。③④ は**マージ後**が正しい
> タイミングであり、本コマンドの実行時点ではまだ来ていない。

## 大原則

- **SSOT は人間所有**。`goals/` に直接コミットせず、**必ず PR で提案**する。マージ＝立法の承認。
- **書けないなら書かない**。二値で機械判定できる完了基準を作れない issue は**起草を拒否**して
  `/conductor:dev`／人間駆動へ回す（穴の空いた spec がマージされると偽 spec になり、司法が PASS を出せなくなる）。
- **検証コマンドは実在を確かめてから書く**。「それらしいテスト名」を捏造しない（後述の自己検証）。
- **起草する spec は必ず `autonomy: L1`**。いきなり L2 にしない（`autonomy-gates.md` の安全シーケンス）。

## 手順

### 1. 前提確認

- `gh auth status` が OK。current repo に `goals/` がある（無ければ `loop-init` を案内して終了）。
- `gh issue view <N>` が引けること。引けなければ停止。

### 2. 材料収集（ここがこのコマンドの価値の本体）

**issue 本文だけから書かない**。実際に動く検証コマンドを書くために現物を読む:

1. `gh issue view <N> --json title,body,comments,labels` で issue 本文と**議論の経緯**を読む
   （結論がコメントで覆っていることがある。最新の合意を採る）。
   - **issue に「## 調べて分かっている現状」節があれば `/spec-intake:grill-issue` が調査済み**。
     そこを**起点にし、再調査は差分（その後に変わった箇所・書かれていない箇所）だけに留める**
     （同じ探索を2回やらない）。節が無ければ以下をゼロから行う。
2. **コードベースを探索**する。対象の実装・既存テスト・テストの実行方法（`Makefile` / `package.json` /
   `go test` の慣行）を特定する。広く浅く見るなら `Task` で `Explore` / `code-explorer` を **haiku** で起動してよい。
3. **製品仕様（anchor）を特定**する。`docs/specs/` 配下から関係する機能の仕様を探す
   （プロジェクトにあれば）。挙動を変える spec なら `product_spec:` に宣言する＝reconcile 対象。

### 3. トリアージ（起草してよい issue かを判定する）

`loop-engine` プラグインが導入されていれば、同梱の `loop-intake-triage.md` を Read し、
その3トリアージに照らす。導入されていない場合は下の要点で判断する（全部を spec 駆動にしない）。

> **3トリアージの要点** — ① 完了基準が二値で機械判定でき、検証コマンドが書けるなら spec 化する。
> ② 探索や設計の議論が先に要るもの（原因不明のバグ・方針が割れている提案）は spec 化せず
> `/conductor:dev` か人間駆動へ回す。③ 曖昧なまま昇格させない（偽 spec を作らない）。
**次のいずれかに当たるなら起草せず、理由を添えて `/conductor:dev`／人間駆動を案内して終了する**:

- **無人化禁止対象** — security（認証/認可/秘匿情報/入力検証）・課金・破壊的変更/不可逆マイグレーション。
  条件を満たしても loop に乗せない（`autonomy-gates.md`「絶対に無人化しない」）。
- **完了基準を二値で機械判定できない** — 「使いやすくする」「速くする（目標値なし）」等。
  検証コマンドに落とせないものは spec にならない。
- **原因不明・要調査のバグ** — 再現テストが書けないなら探索が先（`loop-intake-triage` 3）。
  再現可能になって初めて spec 化する。
- **議論が未決着** — issue のコメントで結論が出ていない。仕様を勝手に決めない。

> 拒否は失敗ではなく**設計どおりの動作**。「typo に6節 spec」を作らないための門番。
> 何が足りないか（どの情報が揃えば起草できるか）を具体的に伝える。
>
> **拒否したら詰め直す手段を案内する**。曖昧さ・議論未決着が理由なら **`/spec-intake:grill-issue <N>`**
> （質問攻めで issue を spec に落とせる状態まで鋭くする）を案内し、そこから戻ってきてもらう。
> 無人化禁止対象・要調査のバグが理由なら `/conductor:dev`／人間駆動へ回す（詰めても loop 向きにはならない）。

### 4. 起草

`${CLAUDE_PLUGIN_ROOT}/reference/SPEC.template.md` を Read し、**その形式に従って**書く
（テンプレの内容をこの skill に写経しない＝DRY。テンプレが更新されたら自動で追従する）。

- **ファイル名** — `goals/YYYYMMDD-<kebab-slug>.md`。`YYYYMMDD` は**今日**（`date +%Y%m%d`）。
  slug は issue の主題を kebab-case で簡潔に。**既存ファイルと衝突しないか `ls goals/` で確認**する。
- **frontmatter** — `status: active` / **`autonomy: L1`（必ず）** / `source_issue: <N>` /
  挙動を変えるなら `product_spec:` に anchor のパス。
- **完了基準** — 各基準に**実行コマンドを併記**する（`cd backend && go test ./internal/handler/ -run TestX`）。
  ここが司法の決定性チェックと1対1で対応する。
- **スコープ** — In / Out を明記。Out を書かないと司法が「スコープ逸脱」を判定できない。
- 迷ったら**薄く**書く。フル機能 spec の節を全部埋める必要はない（バグ修正なら再現テスト1本で足りる）。

### 5. 自己検証（起草した spec が"嘘"でないことを確かめる）

**書いた検証コマンドを実際に流す**。これをやらないと、実在しないテスト名を書いた spec が
そのままマージされ、司法が永久に PASS を出せなくなる。

> **exit code を信じてはいけない（最重要）**。テストランナーの多くは、**指定した名前のテストが
> 1件も無くても成功終了する**。「実行できた」と「実際に検証された」は別物。
>
> ```
> $ go test ./internal/handler/ -run TestDoesNotExist99999
> ok   github.com/.../internal/handler  0.249s [no tests to run]   ← EXIT=0
> ```
>
> **実例（このワナは実在した）**: ある spec が検証コマンドに
> `go test ./internal/handler/ -run TestProfileBioBoundary -v` を書いていた。テスト自体は実在したが
> `//go:build integration` タグ付きで、**タグ無しのこのコマンドはテストを1件も実行せず `ok` を返していた**
> （＝存在しないテストと同じ出力）。spec は「完了」と判定されたが、根拠コマンドは何も検証していなかった。

**まず、その完了基準がどちらの型かを決める**。確かめ方が変わる:

| 型 | いつ | 確かめること |
|---|---|---|
| **A: これから作るテスト**（**変更ユニット spec の最頻形**） | 「再現テスト T を追加して green にする」等 | **テストはまだ無くてよい**。下の「型 A の確認」へ |
| **B: 既にあるテスト** | 既存テストの継続 green を条件に含める | 実在確認＋今 green か。下の「型 B の確認」へ |

> **禁止**: 完了基準を埋めるために、**既に green の既存テストを流用する**こと。
> 「テストが無いから、代わりに今通っているテストを基準にしよう」は、**司法が無作業で PASS を出す
> 別種の偽 spec**を作る。テストがこれから要るなら、型 A として正直に書く。
>
> **本 skill は spec しか書かない（実装もテストも書かない＝手順7）**。型 A で「テストが存在しない」
> のは**正常**であり、書き直しの理由にはならない。

#### 型 A の確認（これから作るテスト）

テスト名は存在しなくてよいが、**コマンドの器が正しいこと**を確かめる（ここを外すと永久に走らない）:

1. **置き場所を決めて spec に書く** — テストを置く**ファイルパスとテスト名**を明記する
   （実装側が迷わないように。例: `backend/internal/handler/xxx_test.go` の `TestX`）。
2. **パッケージ／ディレクトリが実在するか** — `ls` で確認。パスが違うとコマンド自体が誤り。
3. **build tag / マーカーが要るか** — 同じディレクトリの既存テストの冒頭を読む
   （`//go:build integration` など）。**要るならタグを検証コマンドに含める**。
4. **コマンドを流し、「テストが無い」と正しく報告されるか** — 型 A では
   `no tests to run`（Go）/ `no tests ran`（pytest）が出るのが**正解**。
   **パッケージが無い・パスが違う・タグ指定が誤り**の場合は、それとは**別のエラー**が出る。
   その違いを見分ける（`build constraints exclude all Go files` / `no such file or directory` 等）。
5. spec の完了基準には「**実装後にこのコマンドで `=== RUN TestX` が出て PASS する**」と書く
   （＝司法が「走ったこと」を確認できる形にする）。

#### 型 B の確認（既にあるテスト）

**① を飛ばして ③ から始めない**:

1. **ソースに実在するかを先に確認する** — `grep -rn "func TestX" --include="*_test.go"` /
   `grep -rn "def test_x" --include="*_test.py"` 等。見つからなければ**名前が間違っている**
   （または本当は型 A）。
2. **build tag / マーカーを確認する** — Go なら対象ファイル冒頭の `//go:build <tag>`、
   pytest なら `@pytest.mark.<marker>`。**必要なタグを検証コマンドに含める**
   （`go test -tags integration ...`）。**ここが最も踏みやすい**。
3. **実行して「実際に走った」ことを確認する** — `-v` を付け、**テストが起動した証跡**を見る:

   | ランナー | 走った証跡 | 走っていない印（＝その検証コマンドは嘘） |
   |---|---|---|
   | Go | `=== RUN   TestX` が出る | `no tests to run` / `[no tests to run]`（**exit 0**） |
   | pytest | `collected N items` の N ≥ 1 | `no tests ran`（exit 5） |
   | jest / vitest | `Tests: N passed` の N ≥ 1 | `No tests found` / `0 matched` |

4. **今 green か**を確認する（型 B は既存テストなので通っているはず）。
   red なら**そのテストは今壊れている**＝spec の前提が違う。人間に報告する。

> **red と「走っていない」を混同しない（両型に共通）**。実装前のテストが red なのは**正しい**。
> 問題なのは `no tests to run` ＝**そもそも走っていない**こと。前者は赤信号、後者は信号機が無い。
>
> **exit code だけで判断しない**。タグで除外された Go テストは `-v` を付けても
> `testing: warning: no tests to run` に続けて **`PASS`** と表示される。
> 判別子は `PASS` ではなく **`=== RUN   TestX` が出ること**。

型 B で実在しない・走らないと分かったら、**名前を直すか、型 A として書き直す**。確かめずに次へ進まない。

### 6. 人間に提示して合意（PR を作る前）

起草した spec の**全文**と、次をターミナルに提示して**合意を取る**:

- どの issue のどのコメントを根拠にしたか（議論が覆っている場合は特にここ）。
- 完了基準ごとの検証コマンドと、手順 5 の**実行結果**（実在確認できた証拠）。
- 判断に迷った点・仮定を置いた点（ここを人間に潰してもらう）。

spec は司法の採点基準そのもので、間違ったまま流すと後続が全部ずれる。PR 後に直すより安い。
**合意が取れるまで PR を作らない。**

### 7. ブランチ + PR

- ブランチ名 `spec/<issue番号>-<kebab-desc>`（実装ブランチ `loop/<N>-...` と区別する）。
- **spec ファイル1つだけ**をコミットする（実装は一切しない。ここは立法であって行政ではない）。
- PR 本文に: 起草元 issue へのリンク（**`Closes` は書かない**。issue を閉じるのは実装 PR であって
  spec PR ではない）／ 完了基準と検証コマンド ／ 手順 5 の検証結果 ／ トリアージの判断。

### 8. マージ後の手順を出力して終了

最後に、**人間が spec PR をマージした後に流すコマンド**をそのまま貼れる形で出す:

```bash
# ③ issue に spec を指すコメントを投稿（行頭 Spec: が固定書式）
gh issue comment <N> --body "Spec: goals/YYYYMMDD-<slug>.md"

# ④ loop に投げてよいという意思表示
gh issue edit <N> --add-label loop-ready

# ⑤ 起動（まず L1 = 報告のみ。信頼できたら spec を autonomy: L2 に上げる）
# /loop-engine:loop-engine <N>
```

## アンチパターン

- **`goals/` に直接コミット/push する**（SSOT は人間所有。必ず PR で提案しマージを人間に委ねる）。
- **検証コマンドを確かめずに書く**（実在しないテスト名＝司法が永久に PASS を出せない偽 spec）。
- **曖昧な issue を無理に spec 化する**（拒否が正しい動作。`/conductor:dev`／人間駆動へ回す）。
- **spec と一緒に実装してしまう**（このコマンドは立法のみ。実装は `/loop-engine:loop-engine` or `/conductor:dev`）。
- **`autonomy: L2` で起草する**（必ず L1 から。昇格は人間が L1 の結果を見て判断する）。
- **③④ まで代行する**（spec が main にマージされる前に label が付くと `/loop-engine:loop-engine` が落ちる）。
- **issue の議論を spec の代わりにする**（spec に書かれていないことは実装根拠にならない）。
