#!/usr/bin/env bash
# 親のタブの列（横に並んだペイン）の幅をそろえる。parent-child.md「herdr がある場合（HERDR_ENV=1）」の手順 4。
# 使い方: equalize-columns.sh <親のペイン ID>
# ペインの大きさを変えるだけで、開く・閉じる・動かすはしない。
# 終了コード: 0 = そろえた、または列が 1 つでそろえる必要が無い ／ 3 = そろえずに終えた（理由を stderr に出す） ／
#             それ以外 = herdr か jq の失敗（stderr に出る）
set -euo pipefail
pane=${1:?usage: equalize-columns.sh <pane_id>}

# herdr の resize は「指定ペインのその側の境界」を動かす（left で ratio を減らし、right で増やす）。
# herdr の文書には無く、試験用のタブで実測して確かめた挙動。
# 分割の ratio は分割の中での割合なので、外側の分割から 1 本ずつ直し、直すたびに layout を取り直す。
next_resize() {
  jq -r '
    .area as $a | .panes as $ps
    | [.splits[] | select(.direction == "right")] as $r
    | if any($r[]; .rect.y != $a.y or .rect.height != $a.height) then "skip" else
      [ $r | sort_by(-.rect.width)[]
        | (.rect.x + .ratio * .rect.width) as $b
        | .rect as $rc
        | [$ps[] | select(.rect.y == $a.y and .rect.x >= $rc.x and .rect.x < $rc.x + $rc.width)] as $in
        | ([$in[] | select(.rect.x + .rect.width / 2 < $b) | .rect.x] | unique | length) as $left
        | ([$in[] | .rect.x] | unique | length) as $all
        | ($left / $all - .ratio) as $d
        | if $d < -0.01 then {pane: ([$in[] | select(.rect.x + .rect.width / 2 > $b)] | min_by(.rect.x) | .pane_id), dir: "left", amt: -$d}
          elif $d > 0.01 then {pane: ([$in[] | select(.rect.x + .rect.width / 2 < $b)] | max_by(.rect.x) | .pane_id), dir: "right", amt: $d}
          else empty end
        | select(.pane != null)
        | "\(.pane) \(.dir) \(.amt)" ] | first // empty
      end'
}

# 列は多くて 5 なので分割は 4 本。1 本に 1 回で足りるが、丸めの揺れに備えて少し余裕を持たせる
for _ in 1 2 3 4 5 6 7 8; do
  step=$(herdr pane layout --pane "$pane" | jq '.result.layout' | next_resize)
  [ -z "$step" ] && exit 0
  if [ "$step" = skip ]; then
    # 全高でない左右分割（列の一部だけを左右に割ったもの）がある。人間のレイアウトを壊さないよう、そろえずに知らせる
    echo "幅はそろえていない（列の一部だけを左右に割ったペインがある）" >&2
    exit 3
  fi
  read -r target dir amt <<<"$step"
  herdr pane resize --pane "$target" --direction "$dir" --amount "$amt" >/dev/null
done
echo "幅をそろえきれなかった（8 回で収束せず）" >&2
exit 3
