#!/bin/zsh
# App Store screenshots. See AppStoreListing.md.
# shoot.sh <sim-udid> <outdir> — runs the standard six shots.
SIM=$1; OUT=$2
mkdir -p "$OUT"
one() {
  local name=$1; shift
  xcrun simctl terminate $SIM memorizethebible.aarontrank.com 2>/dev/null
  xcrun simctl launch $SIM memorizethebible.aarontrank.com -uiDebug -debugOnboarded "$@" >/dev/null
  sleep 6
  xcrun simctl io $SIM screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "  $name $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2 | tr -d ' \n')"
}
one 1-ladder      -debugBook PSA -debugChapter 23 -debugSeed ladder2
one 2-full-mask   -debugBook PSA -debugChapter 23 -debugSeed ladder4
one 3-home        -debugScreen dashboard -debugBook PSA -debugChapter 23 -debugSeed partial -debugCompletePlan builtin.roman-road
one 4-plans       -debugScreen plans -debugSeedPlans
one 5-plan-detail -debugScreen plan -debugPlan builtin.roman-road -debugWorkedThrough 3
one 6-review      -debugBook PSA -debugChapter 23 -debugSeed memorized -debugScreen review -debugLevel 2
