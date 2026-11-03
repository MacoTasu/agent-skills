# Routine プロンプト — factory の定期発火（Claude Code cloud routine）

> **cloud routine は claude.ai のアカウントで走り、サブスクの利用枠を使う**（API の従量課金ではない）。
> だから factory の定期発火は routine を正とする。手元で回すなら `scripts/factory-tick`（同じくサブスクのログインを確かめてから `claude -p`）。
> GitHub Actions は使わない（API キーを secret に置く運用になりやすく、サブスクの条件を外から確かめられない）。
>
> 作り方は `loop-engine` の `reference/routine.md` と同じ: `claude.ai/code/routines` か `/schedule` で schedule トリガの routine を作り、
> リポジトリを 1 つ選び、**下の 3 行だけ**を貼る。中身はこのファイル（版管理下）に置く。
> **routine を factory に切り替えたら、同じリポジトリの loop-engine の routine は止める**（製造は factory の中で回る。二重に回すとロックを取り合う）。

## routine に保存する本文（ここだけをコピーする）

```
このリポジトリの factory を1巡まわす。

0. `git clone --depth 1 https://github.com/MacoTasu/agent-skills /tmp/harness` を実行する。失敗したら何もせず報告して終了する。
1. `/tmp/harness/plugins/factory/skills/factory/reference/routine.md` を Read し、その「発火プロンプト本文」節のとおりに実行する。
```

## routine の設定

| 項目 | 値 |
|---|---|
| トリガ | schedule。最小 1 時間。**1 発火で重い工程は 1 件**なので、1 日の処理量 ≒ 発火回数。サブスクの利用枠を見て間隔を決める（まずは 1 日数回から） |
| リポジトリ | 回したいリポジトリ 1 つ |
| 環境 | 既定（Trusted）。**環境変数に `ANTHROPIC_API_KEY` などを入れない**（入っていると手順 0 で止まる） |
| モデル | routine のモデル選択。司法は手順の中で `opus` を指定する |

## 発火プロンプト本文（ここから）

`/tmp/harness/plugins/factory/skills/factory/SKILL.md` を Read し、その「手順（1 巡）」を実行する。cloud なので次のとおり読み替える。

- **`<factory>`** は `/tmp/harness/plugins/factory`、**`<loop-engine>`** は `/tmp/harness/plugins/loop-engine`、
  **`<spec-intake>`** は `/tmp/harness/plugins/spec-intake`、`dev-crew` は `/tmp/harness/plugins/dev-crew`。
- **手順 0 の関門は `bash /tmp/harness/plugins/factory/scripts/check-subscription --env`。**
  routine 自体は claude.ai のアカウントで走るので、見るのは「中から従量課金の経路を開ける環境変数と、リポジトリの設定（`apiKeyHelper`・`env` の上書き）が無いこと」だけ。
- **プラグインの agent は `subagent_type` に居ない。** 司法・retro・行政の呼び方は `/tmp/harness/plugins/loop-engine/skills/loop-engine/reference/routine.md`
  の「発火プロンプト本文」節の読み替え（`judge.md` / `retro.md` を手順書として汎用サブエージェントに読ませる）に従う。
  retro の prompt には `destination=self` を必ず含める。
- **`gh` が無ければ GitHub の MCP ツール**（issue の一覧・ラベル・コメント・本文の更新、PR の一覧と作成）に読み替える。
  掲示板の本文の書き直しは issue の更新（body の置き換え）で行う。
- 受付の `spec-draft` は clone した `/tmp/harness/plugins/spec-intake/skills/spec-draft/SKILL.md` を手順書として読み、その「無人モード」で実行する。
  spec-kit のスキル（`/speckit-specify` など）は対象リポジトリにコミットされたもの（`.claude/skills/speckit-*`）を使う。無ければ受付は拒否扱い
  （`loop-escalated` ＋「spec-kit が未初期化」）にせず、**受付だけを飛ばして**報告に書く（issue の不備ではないため）。

## 発火プロンプト本文（ここまで）

## 検証状況

- `check-subscription` は手元（claude 2.1.317、macOS）で確かめた: 環境変数なしで ok、`ANTHROPIC_API_KEY` を入れると ng
  （そのとき `claude auth status` の `authMethod` も `api_key` に変わる＝ログイン済みでも従量課金に流れることを観測）。
  リポジトリの `.claude/settings.json` に `apiKeyHelper` を置くと `authMethod` は `api_key_helper` になる（司法が観測）。`--env` でも ng にする。
- cloud での 1 巡の通し実行は**未実測**。`loop-engine` の cloud 部分（司法の読み替え）は同ファイルの検証状況に従う。
