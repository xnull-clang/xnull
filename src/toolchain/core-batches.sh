#!/bin/sh
# Unattended T0 core closure driver.
#
# One command, one user-visible stop:
#   src/toolchain/core-batches.sh
#
# It runs batch 0 (core integration), then io -> collections -> text -> fs -> sys,
# rebuilds mini, runs both gates, commits per batch, and re-invokes the agent
# whenever a batch does not reach its acceptance predicate. It does not accept
# Partial / "todo" / "freeze" / "skip" as an end state.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BRANCH=${CORE_BRANCH:-core-closure}
WT=${CORE_WORKTREE:-$ROOT/../XNull-core-closure}
ATTEMPTS=${CORE_ATTEMPTS:-3}
MODEL=${CORE_MODEL:-deepseek/deepseek-flash}
LOG_DIR="$ROOT/.cache/core-batches"
mkdir -p "$LOG_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/$STAMP.log"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

log "log: $LOG"
log "worktree: $WT ($BRANCH), model: $MODEL"

if [ ! -e "$WT/.git" ]; then
    log "creating worktree: $WT ($BRANCH)"
    if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git -C "$ROOT" worktree add "$WT" "$BRANCH"
    else
        git -C "$ROOT" worktree add -b "$BRANCH" "$WT" HEAD
    fi
fi

# LOCAL_RULES.md is gitignored by design; carry it into the worktree.
cp "$ROOT/LOCAL_RULES.md" "$WT/LOCAL_RULES.md"

cd "$WT"

if [ -n "$(git status --porcelain)" ]; then
    log "FATAL: worktree is dirty before start"
    git status --short | tee -a "$LOG"
    exit 1
fi

log "building mini"
src/mini/build.sh >>"$LOG" 2>&1

run_agent() {
    session=$1
    prompt=$2
    log "--- agent: $session ($MODEL) ---"
    opencode run --auto --model "$MODEL" --session "$session" "$prompt" 2>&1 | tee -a "$LOG" || true
}

dirty() { [ -n "$(git status --porcelain)" ]; }

gates() {
    src/mini/build.sh >>"$LOG" 2>&1 &&
        src/mini/tests/xdk.sh >>"$LOG" 2>&1 &&
        src/mini/tests/xdk_core.sh >>"$LOG" 2>&1
}

verified() {
    grep -q '^| 当前状态 | Verified' "docs/design/t0/$1.md"
}

finish() {
    session=$1
    if dirty; then
        run_agent "$session" "批内还有未提交改动。按第 5 号收尾：跑门禁、更新文档与镜像、提交一次。不要解释，不要列待办，直接做完。"
    fi
    if ! gates; then
        return 1
    fi
    if dirty; then
        run_agent "$session" "门禁已过但工作区不干净。提交本批改动，不要留未提交文件。"
    fi
    ! dirty
}

batch() {
    name=$1
    doc=$2
    prompt=$3
    attempt=1
    session="ses-core-$name-$STAMP"

    while [ "$attempt" -le "$ATTEMPTS" ]; do
        log "=== $name attempt $attempt/$ATTEMPTS ==="
        run_agent "$session" "$prompt"
        if finish "$session"; then
            if [ "$name" = "core-integration" ] || verified "$doc"; then
                log "=== $name PASS ==="
                return 0
            fi
            log "=== $name gates green but status is not Verified ==="
        else
            log "=== $name RED ==="
        fi
        prompt="上一轮没有收口。继续本批：$name（$doc）。完成条件：门禁全绿、该包状态 Verified、工作区干净。不要汇报，不要列待办/冻结/跳过；发现缺口就地补。"
        attempt=$((attempt + 1))
    done

    log "=== $name FAILED after $ATTEMPTS attempts ==="
    return 1
}

pkg_prompt() {
    pkg=$1
    doc=$2
    extra=$3
    printf '%s\n' \
        "开工前先读 LOCAL_RULES.md 第 5/6 号与 docs/design/t0/CORE-CLOSURE.md。" \
        "本批 = $pkg T0-X 收口，一次做完再停。" \
        "范围 = docs/design/t0/$doc 的全部 T0-X 条目，不缩范围、不跳过。" \
        "$extra" \
        "实现后扩展 src/mini/tests/xdk_core.x 覆盖该包新面，并同步更新 xdk_core.out；不得删除旧断言，不得改期望值迁就实现。" \
        "批内不跑门禁、不提交、不汇报、不列待办；批末跑一次 src/mini/build.sh + src/mini/tests/xdk.sh + src/mini/tests/xdk_core.sh，更新该文档、AUDIT.md、src/xdk/PLAN.md 与 xdk/lib 镜像，提交一次。" \
        "结束条件：该包状态 Verified、两道门禁绿、工作区干净。只有红门修不了、必须改变产品方向的决策、破坏性操作才停。"
}

INTEGRATION_PROMPT="开工前先读 LOCAL_RULES.md 第 5/6 号与 docs/design/t0/CORE-CLOSURE.md。
本批 = 核心层集成收口（批 0），一次做完再停。
目标：src/mini/tests/xdk_core.sh 绿。
范围：修 docs/design/t0/CORE-CLOSURE.md §3.1 的全部红点，以及 xdk_core.sh 暴露的其他缺口。
已知红点：List<String> 的 sortBy(a < b) 不排序，且旧期望值把错误顺序固化了；writeText 返回 0，而 10-fs.md 要求字节数。
禁止：改 xdk_core.x 的断言或 xdk_core.out 的期望值来迁就实现；禁止删断言、换弱断言。
允许：给 String 增加可用的比较/排序 API、修编译器/运行时、修正错误期望值；API 变更同步设计文档。
批内不跑门禁、不提交、不汇报；批末跑一次 src/mini/build.sh + xdk.sh + xdk_core.sh，更新文档与镜像，提交一次。
只有红门修不了、必须改变产品方向的决策、破坏性操作才停。"

batch "core-integration" "" "$INTEGRATION_PROMPT" || exit 1

batch "io" "09-io.md" "$(pkg_prompt io 09-io.md '重点：readU8 的 EOF 语义改为 checked/panic，禁止 0 哨兵；toBytes 副本；tryReadU8/readExact；Buffered/Chain/Tee/Limit/LineReader；flush/close。')" || exit 1

batch "collections" "06-collections.md" "$(pkg_prompt collections 06-collections.md '重点：任意 K/V 的 Map.entries 值对象、groupBy/groupByInt、OrderedMap/BTreeMap、通用 Set<T>、joinWith。会改编译器/运行时：改完必须重建 mini。')" || exit 1

batch "text" "05-text.md" "$(pkg_prompt text 05-text.md '重点：Unicode UTF-8/UTF-16/code point、POSIX ERE 子集、printf Format、参数命名。Regex 是独立工程，但必须在同一批内完成，不得拆到下批。')" || exit 1

batch "fs" "10-fs.md" "$(pkg_prompt fs 10-fs.md '重点：read/write 改为 Result 面、File/Dir/Path、Long offset、atomic/temp/walk/glob、metadata、权限/链接。')" || exit 1

batch "sys" "11-sys.md" "$(pkg_prompt sys 11-sys.md '重点：Result 面、File/Dir/Process、stdio 管道、信号、环境枚举、进程组、内嵌资源读取子集。')" || exit 1

log "=== final acceptance ==="
ok=1
for doc in 05-text.md 06-collections.md 09-io.md 10-fs.md 11-sys.md; do
    if verified "$doc"; then
        log "Verified: $doc"
    else
        log "NOT VERIFIED: $doc"
        ok=0
    fi
done

if ! gates; then
    log "final gates: RED"
    ok=0
fi

if dirty; then
    log "final: worktree dirty"
    ok=0
fi

if [ "$ok" != 1 ]; then
    log "CORE CLOSURE: FAIL"
    exit 1
fi

log "CORE CLOSURE: PASS"
git log --oneline -20 | tee -a "$LOG"
log "merge into main: git -C \"$ROOT\" merge --no-ff \"$BRANCH\""
