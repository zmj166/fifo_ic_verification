#!/bin/bash
# ==============================================================================
# 文件名 : scripts/run_all.sh
# 功  能 : 一键运行全部回归测试（Regression Test）并汇总结果
#
# ── 什么是回归测试 ────────────────────────────────────────────────────────────
#   回归测试（Regression Test）是指：
#   每次修改了设计或验证代码后，把所有测试用例全部重新跑一遍，
#   确保新改动没有破坏原来已经通过的功能。
#   这个脚本把三个测试场景打包成一条命令，方便快速验证全套功能。
#
# ── 使用方法 ──────────────────────────────────────────────────────────────────
#   # 第一次使用前赋予可执行权限
#   chmod +x scripts/run_all.sh
#
#   # 使用 VCS 运行所有测试（默认）
#   cd ~/async_fifo_verification-3
#   ./scripts/run_all.sh
#
#   # 使用 QuestaSIM 运行所有测试
#   ./scripts/run_all.sh questa
#
# ── 脚本退出状态 ──────────────────────────────────────────────────────────────
#   exit 0 : 全部测试通过（可用于 CI/CD 判断）
#   exit 1 : 至少有一个测试失败
# ==============================================================================

# ── 终端颜色定义 ─────────────────────────────────────────────────────────────
# ANSI 转义码，让终端输出有颜色，更容易区分 PASS/FAIL
# \033[  : 转义序列开始
# 0;31m  : 0=正常样式，31=红色前景色
# 0;32m  : 0=正常样式，32=绿色前景色
# 1;33m  : 1=粗体，33=黄色前景色
# 0m     : 重置所有颜色和样式（用于 NC = No Color）
RED='\033[0;31m'     # 红色（用于 FAIL/ERROR）
GREEN='\033[0;32m'   # 绿色（用于 PASS）
YELLOW='\033[1;33m'  # 黄色粗体（用于标题和分隔线）
NC='\033[0m'         # 无颜色（重置）


# ── 仿真工具选择 ─────────────────────────────────────────────────────────────
# $1 是命令行第一个参数
# ${1:-vcs} 表示：如果 $1 未定义或为空，则默认用 vcs
# 用法：
#   ./run_all.sh        → TOOL=vcs
#   ./run_all.sh questa → TOOL=questa
TOOL=${1:-vcs}

# echo -e 启用转义字符解析（让 \033 等颜色代码生效）
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Async FIFO Verification Suite         ${NC}"
echo -e "${YELLOW}  Tool: $TOOL                           ${NC}"
echo -e "${YELLOW}========================================${NC}"


# ── 设置仿真目录 ─────────────────────────────────────────────────────────────
# 根据选择的工具，进入对应的仿真目录
# scripts/ 和 sim/ 都在项目根目录下，所以用 ../sim/工具名
if [ "$TOOL" == "questa" ]; then
    SIM_DIR="../sim/questa"
else
    # VCS（或任何未知工具名）都走 VCS 目录
    SIM_DIR="../sim/vcs"
fi

# 切换到仿真目录（Makefile 依赖相对路径，必须在正确目录下执行）
cd $SIM_DIR


# ── 测试列表和统计变量 ───────────────────────────────────────────────────────
# 定义要运行的三个测试场景
# 括号 () 定义数组，空格分隔元素
TESTS=("normal" "full_empty" "random")

PASS_COUNT=0    # 通过的测试数量
FAIL_COUNT=0    # 失败的测试数量
RESULTS=()      # 存储每个测试的结果字符串（用于最后汇总打印）


# ── 循环运行每个测试 ─────────────────────────────────────────────────────────
# "${TESTS[@]}" 展开数组所有元素（加引号防止元素内有空格时被分割）
for TEST in "${TESTS[@]}"; do
    echo ""
    echo -e "${YELLOW}--- Running: $TEST test ---${NC}"

    # 运行仿真，把所有输出重定向到临时日志文件
    # > /tmp/sim_${TEST}.log  : 标准输出写入文件（覆盖模式）
    # 2>&1                    : 标准错误也合并到同一文件
    # 这样不会在终端显示大量仿真 log，只看最终 PASS/FAIL 结果
    make sim TEST=$TEST > /tmp/sim_${TEST}.log 2>&1

    # $? 是上一条命令的退出状态：0=成功，非0=失败
    # make 失败（编译错误等）时 STATUS 非0
    STATUS=$?

    if [ $STATUS -eq 0 ]; then
        # make 命令本身执行成功（没有 Makefile 错误）
        # 但仿真可能有逻辑错误（FAIL/ERROR），需要检查日志内容

        # grep -q : quiet 模式，只判断是否匹配，不打印匹配内容
        # "FAIL\|ERROR\|error" : 用 \| 分隔多个关键词（OR 匹配）
        # 注意：VCS 的 $error() 会输出 "Error"，scoreboard FAIL 会输出 "FAIL"
        if grep -q "FAIL\|ERROR\|error" /tmp/sim_${TEST}.log; then
            echo -e "${RED}  RESULT: FAIL${NC}"
            FAIL_COUNT=$((FAIL_COUNT+1))
            RESULTS+=("FAIL: $TEST")     # 往数组末尾追加元素
        else
            echo -e "${GREEN}  RESULT: PASS${NC}"
            PASS_COUNT=$((PASS_COUNT+1))
            RESULTS+=("PASS: $TEST")
        fi
    else
        # make 命令执行失败（编译报错、Makefile 语法错误等）
        echo -e "${RED}  RESULT: COMPILE/RUN ERROR (exit code: $STATUS)${NC}"
        echo -e "  详细信息：cat /tmp/sim_${TEST}.log"
        FAIL_COUNT=$((FAIL_COUNT+1))
        RESULTS+=("ERROR: $TEST")
    fi
done


# ── 打印汇总报告 ─────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  REGRESSION SUMMARY                    ${NC}"
echo -e "${YELLOW}========================================${NC}"

# 遍历结果数组，根据前缀选择颜色打印
for RESULT in "${RESULTS[@]}"; do
    if [[ $RESULT == PASS* ]]; then
        # [[ ]] 是 bash 的扩展条件测试，PASS* 是通配符匹配
        echo -e "  ${GREEN}$RESULT${NC}"
    else
        echo -e "  ${RED}$RESULT${NC}"
    fi
done

echo ""
# 计算总数：((...)) 是 bash 的算术运算语法
echo -e "  总计: $((PASS_COUNT+FAIL_COUNT)) 个测试  |  通过: ${GREEN}$PASS_COUNT${NC}  |  失败: ${RED}$FAIL_COUNT${NC}"
echo -e "${YELLOW}========================================${NC}"

# 失败时提示日志位置，方便查看详细错误信息
if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo "  查看失败详情："
    for TEST in "${TESTS[@]}"; do
        echo "    cat /tmp/sim_${TEST}.log | grep -A5 'FAIL\|ERROR'"
    done
fi


# ── 返回退出状态 ─────────────────────────────────────────────────────────────
# CI/CD 系统（如 Jenkins、GitHub Actions）通过脚本退出码判断是否通过
# exit 0 : 所有测试通过，CI 认为成功（绿色）
# exit 1 : 有测试失败，CI 认为失败（红色）
if [ $FAIL_COUNT -eq 0 ]; then
    exit 0
else
    exit 1
fi
