# 規範 (Rule / SSOT) — ループ取り込みトリアージと spec の秩序

> 人間が承認した standing な規範（守るもの）。トリガ対象外。司法・`/conductor:dev`・`/loop-engine:loop-engine` が参照する。
> 「**全部を spec 駆動にしない**。自律ループに入れる仕事を選択的に絞る」ための線引き。

## 意図 (なぜこの規範が要るか)

- spec 駆動は**無人ループ (`/loop-engine:loop-engine`) の検証アンカー**としては必須だが、全タスクに課すと
  「typo に6節 spec」のように割に合わず、仕様化できない仕事に**偽の spec**を生む。
- どの仕事をループに入れ、どれを `/conductor:dev`／人間駆動に回すかの基準を明文化し、
  「迷ったら全部 spec 化」への暴走と、逆に「未仕様の仕事をループに流す」事故の両方を防ぐ。

## 規範 (守ること)

### 0. 2層 — 製品仕様（anchor）と 変更ユニット（goal）を分ける【最重要】

「spec」を2つの層に分ける。混同すると **agent のよりどころ（製品仕様）が腐る**。

| 層 | 何 | 場所 | 寿命 | 所有 |
|---|---|---|---|---|
| **製品仕様（Product Spec / anchor）** | 「この機能は**今どう振る舞うか**」現在の真実・ドメインルール | 各プロジェクトの **`docs/specs/<feature>/...`**（既定。プロジェクトで設定可） | **living**（in-place 更新・常に最新） | 人間（承認＝PR merge） |
| **変更ユニット（Change / Goal）** | 「**今回これを変える**」というデルタ・タスク | 各プロジェクトの **`goals/<YYYYMMDD-slug>.md`** | transient（`active→done` で履歴化） | 人間（goal は実行中**不可侵**） |

- **agent のよりどころは製品仕様（`docs/specs/`）**。done になった変更ユニットの山は**履歴/監査**であって製品仕様ではない。
- **reconcile 規律（anchor を生かし続ける）**: 挙動を変える変更ユニットは、その PR で **関係する製品仕様
  `docs/specs/<feature>.md` を新挙動に合わせて更新**する。これを「done」の条件に含める。
  = deck の **Specification Provenance（仕様↔テストを最新・追跡可能に保つ）**。
- **「不可侵」と「reconcile」の両立**: 実行中に動かしてはいけないのは*変更ユニット（goal）*。reconcile する
  のは*製品仕様（anchor）*で、変更の**成果物として PR に載せ人間が merge 承認**する（ボットが main の
  正典を勝手に書き換えるのではない＝SSOT は人間所有のまま）。
- 矛盾検知: 変更ユニットが製品仕様と矛盾するなら **ESCALATE**（"spec 矛盾"＝実装の根拠が無い）。
- 命名: 製品仕様=`docs/specs`（anchor）／ 変更ユニット=`goals/`（goal）。deck の SSOT
  （機能要件・ドメインルール）に当たるのは**前者**。`goals/` は変更ゴールのキューであり仕様書ではない。

### 1. 3トリアージ — 仕事の行き先

| 区分 | 入口 | spec |
|---|---|---|
| 無人化可能（検証可・境界明確・安全） | **`/loop-engine:loop-engine`** | **フル SSOT spec 必須**（＝狭い少数派） |
| 人間が見ていれば足りる大多数 | **`/conductor:dev`**（human-in-loop） | 不要〜軽量。タスク依頼で可 |
| 探索的・曖昧・判断重・blast radius 大 | 人間駆動 | 書くと嘘になる。書かない |

- spec の合格ラインは "perfect" ではなく **"完了が二値で機械判定できる" かつ "scope/guardrail で境界づけられている"**。
- spec 矛盾・欠落は**必ず ESCALATE**。security・課金・破壊的変更・認証認可は loop に入れてよいが、PR 本文で申告させる（`autonomy-gates.md`「要注意の変更」）。

#### 段階制（autonomy）は廃止

以前は intake に加えて「どこまで無人で進めるか」（`autonomy: L1|L2`）を spec ごとに決めていたが、廃止した。
loop に入れた spec は常に 実装→分離司法→PR まで進み、PR で止まる（マージは人間）。
判断するのは intake（loop に入れるか / `/conductor:dev` か / 人間駆動か）だけ。

### 2. issue は intake であって SSOT ではない（＝発見経路であり、仕様ではない）

```
issue / 観測 (起票・議論の場・可変・非バージョン)
   │  ← promotion: 人間が「やる」と決めた時点で spec を書いて承認
   ▼
goals/<spec>.md (立法・versioned・PR承認・完了基準あり)  ← 実装根拠はここだけ
   ▲
   │  ← Spec: コメント + loop-ready label が issue から spec を指す（ポインタ）
issue #N ── /loop-engine:loop-engine <N> ──▶ 司法 → PR (Closes #N) 停止 (HOTL)
```

- **実装根拠（SSOT）は常に `goals/` の `status: active`**。**issue の本文・議論から仕様を推測して
  実装しない**。issue が担うのは「どの spec を今回すか」を指す**ポインタと意思表示**だけ。
- **昇格プロトコル（人間が行う）**: ① issue で議論する（この時点では label も spec も無い。
  **`/spec-intake:grill-issue [番号]` で質問攻めにして spec に落とせる状態まで詰められる**。引数なしなら
  issue 前の段階から詰めて最後に起票）→
  ② 「fix する」と決まったら spec `goals/YYYYMMDD-slug.md` を書いて PR → main マージ →
  ③ issue に固定書式コメント `Spec: goals/YYYYMMDD-slug.md` を投稿 → ④ **`loop-ready` label** を付ける。
  - **② は `/spec-intake:spec-draft <issue番号>` で AI に起草させられる**（issue＋コードベース＋製品仕様を読んで
    検証コマンド付きで起草し、**PR で提案**する。承認＝マージは人間）。起草できない issue は
    拒否して `/conductor:dev` へ回す＝門番。**③④ は代行しない**（spec が main にマージされる前に label が
    付くと `/loop-engine:loop-engine` が main に無い spec を指して落ちるため、マージ後が正しいタイミング）。
  - **spec は「やる」と決めた瞬間に書く**（起票時ではない）。議論の結果やらなくなった提案に spec を
    書かせない＝偽 spec を作らないための順序。曖昧なまま昇格させず `/conductor:dev`／人間駆動へ流す。
  - コメント（本文編集ではなく）に書くのは、**いつ昇格したかが履歴に残る**ため。
- **起動経路は2つ、どちらも実装根拠は `goals/`**:

  | 経路 | 入口 | 拾う対象 | 状態 |
  |---|---|---|---|
  | slug 直接 | `/loop-engine:loop-engine <slug>` | `goals/<slug>.md` | 実装済み |
  | issue 経由 | `/loop-engine:loop-engine <issue番号>` | label + `Spec:` コメントで解決した `goals/` の spec | **実装済み（手動のみ）** |
  | 自動走査 | **cloud routine**（autonomous-entry） | **`loop-ready` label が付いた open issue**（`Spec:` コメントで `goals/` の spec に解決） | 実装済み |

- **`loop-ready` label が無い issue は実装しない**（＝人間がまだ昇格させていない）。label があっても
  `Spec:` コメントで `goals/` に解決できない、spec が `status: active` でない、既に `Closes #N` の
  open PR がある、のいずれかなら **ESCALATE**（詳細は `loop-engine` skill の「issue 経由の起動」）。
- **ポインタは2方向あるが、権威は片方だけ**（混同すると label ゲートが骨抜きになる）:

  | 方向 | 実体 | 誰が書く | 役割 |
  |---|---|---|---|
  | issue → spec | `loop-ready` label ＋ 行頭 `Spec:` コメント | 人間（昇格時） | **起動の権威**。loop はこれだけを見て spec を解決する |
  | spec → issue | spec frontmatter `source_issue:`（任意） | 人間（spec 執筆時） | **逆引き用の参考情報**。監査と将来の自動化（spec マージ→コメント/label 付与の代行）の布石 |

  - **`source_issue:` が書いてあることを根拠に起動してはいけない**。label と `Spec:` コメントが
    揃っていなければ ESCALATE（spec 側の記述で label ゲートを迂回させない＝人間の実行意思の確認点を守る）。
  - 両者が食い違う（spec の `source_issue` と、起動に使った issue 番号が別）場合は **ESCALATE**（どちらかが古い）。
- **ループが使うラベルは3つ**。`loop-ready`（人間が付ける GO）/ `loop-running`（ループが着手時に付ける
  ロック）/ `loop-escalated`（人間対応待ち）。**ラベルを外せるのは G5 正常完了時のループと人間だけ**。
- **将来（未実装・スコープ外）**: spec マージ時の**コメント・label 付与の自動代行**、loop が issue から
  spec を**起草して ESCALATE**（人間は生成 spec を承認するだけ）。いずれも需要が出てから作る（YAGNI）。
  label 名も当面固定（プロジェクトごとの設定機構は作らない）。

### 3. バグ修正の spec 化 — 再現テストを完了基準にする

| バグの状態 | 行き先 |
|---|---|
| 原因判明・再現テストが書ける | **薄いバグ修正 spec → loop**（完了基準＝再現テストが green） |
| 原因不明・要調査（探索的） | **`/conductor:dev`／人間駆動**。再現可能になって初めて spec 化 |

- バグ修正 spec は薄くてよい: 意図（症状・期待値）／完了基準（再現テスト T が red→green）／スコープ（fix のみ）。
- 「done＝再現テストが通る」が司法の決定性チェックの照合対象になる（テスト先行＝再現→修正の順）。

### 4. spec ファイルの命名と秩序

- **命名 = `YYYYMMDD-<kebab-slug>.md`**（例 `20260621-loop-readme.md`）。slug＝ファイル名 stem 全体で、
  `/loop-engine:loop-engine <slug>` と 1:1。日付を剥がす特別ルールは作らない。
  - 理由: 時系列ソート＝作成順。新規は末尾。Supabase migration と同 idiom。連番方式の採番衝突を回避。
- **秩序 = フラット ＋ frontmatter `status` 軸**（`active`→`done`）。ループは `status: active` だけ拾う。
  done も `goals/` 直下に残す（件数が増えたら退避を検討＝YAGNI）。カテゴリ分けは作らない。
- **例外（グランドファーザー）**: ブートストラップの `phase2 / phase2_1 / phase3_0 / phase3_2` は
  ループ自身を作る一回性の連番シリーズとして現名を維持。**本命名規則は post-bootstrap の新規 spec に適用**。

## enforcement (どう守らせるか)

- `/loop-engine:loop-engine` は本規範の 2 に従い、**実装根拠を `goals/*.md` の `status: active` に限る**
  （issue の議論から仕様を推測して実装しない）。issue 経由の起動は spec への解決を必須とし、
  解決できなければ ESCALATE する。autonomous-entry は `loop-ready` label 付き issue を走査するが、
  **拾うのはあくまで「その issue が指す spec」**であって issue 本文ではない（label は intake のキュー、
  spec が法）。
- 司法 `review-judge:judge` は、ループに乗った spec が 1（境界）に反していないか、要注意の変更が PR 本文で申告されているか、
  バグ修正なら 3 の再現テスト基準を持つかを採点観点に含める。
- 新規 spec の命名が 4 に反する（日付プレフィックス無し）場合はレビューで差し戻す。

## 適用範囲 / 例外

- 適用: dotfiles の自律ループ運用全般、および本基盤を配布した先のリポジトリ。
- 例外: 上記グランドファーザー spec の命名。`/conductor:dev` 単発タスクは本規範の spec 必須要件の対象外
  （human-in-loop で人間が検証者のため）。
