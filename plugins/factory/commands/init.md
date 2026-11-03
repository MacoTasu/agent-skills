---
description: "このリポジトリで factory を回すための初期セットアップ（ラベル・掲示板・サブスクの確認）"
---

現在のリポジトリに factory の作業票の置き場を用意する。冪等なので何度実行しても安全（既存のラベル・掲示板は触らない）。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/factory-init"
```

| 対象 | 役割 |
|---|---|
| ラベル `factory:intake` / `factory:drafting` / `factory:spec-review` / `factory:board` | factory の工程の状態 |
| ラベル `loop-ready` / `loop-running` / `loop-escalated` / `retro` | loop-engine と retro と共有（同じ名前のまま使う） |
| `factory:board` の issue | 掲示板。発火ごとに本文を書き直す |
| `check-subscription` | AI の利用がサブスクだけを通るか。ng なら直してから発火する |

前提は loop-engine と同じ（spec-kit の初期化・hooks）。まだなら先に `/loop-engine:init`。

発火は次のどちらか:

- **cloud routine**（ラップトップを閉じても回る）: `${CLAUDE_PLUGIN_ROOT}/skills/factory/reference/routine.md` の 3 行を routine に貼る
- **手元**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/factory-tick" <リポジトリのパス>` を cron / launchd に載せる

あとは仕様にしたい issue に `factory:intake` を付けるだけ。
