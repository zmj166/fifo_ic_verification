#!/bin/bash
# ============================================================================
# 文件名: run_all.sh
# 描述:   一键运行所有测试的脚本
#
# 使用方法:
#   chmod +x run_all.sh
#   ./run_all.sh            - 使用VCS运行所有测试
#   ./run_all.sh questa     - 使用QuestaSim运行所有测试
# ============================================================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 仿真器选择
TOOL=${1:-vcs}
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Async FIFO Verification Suite         ${NC}"
echo -e "${YELLOW}  Tool: $TOOL                           ${NC}"
echo -e "${YELLOW}========================================${NC}"

# 设置仿真目录
if [ "$TOOL" == "questa" ]; then
    SIM_DIR="../sim/questa"
else
    SIM_DIR="../sim/vcs"
fi

cd $SIM_DIR

# 定义测试列表
TESTS=("normal" "full_empty" "random")
PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

# 运行每个测试
for TEST in "${TESTS[@]}"; do
    echo ""
    echo -e "${YELLOW}--- Running: $TEST test ---${NC}"

    make sim TEST=$TEST > /tmp/sim_${TEST}.log 2>&1
    STATUS=$?

    if [ $STATUS -eq 0 ]; then
        # 检查日志中是否有FAIL
        if grep -q "FAIL\|ERROR\|error" /tmp/sim_${TEST}.log; then
            echo -e "${RED}  RESULT: FAIL${NC}"
            FAIL_COUNT=$((FAIL_COUNT+1))
            RESULTS+=("FAIL: $TEST")
        else
            echo -e "${GREEN}  RESULT: PASS${NC}"
            PASS_COUNT=$((PASS_COUNT+1))
            RESULTS+=("PASS: $TEST")
        fi
    else
        echo -e "${RED}  RESULT: COMPILE/RUN ERROR${NC}"
        FAIL_COUNT=$((FAIL_COUNT+1))
        RESULTS+=("ERROR: $TEST")
    fi
done

# 打印汇总
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  REGRESSION SUMMARY                    ${NC}"
echo -e "${YELLOW}========================================${NC}"
for RESULT in "${RESULTS[@]}"; do
    if [[ $RESULT == PASS* ]]; then
        echo -e "  ${GREEN}$RESULT${NC}"
    else
        echo -e "  ${RED}$RESULT${NC}"
    fi
done
echo ""
echo -e "  Total: $((PASS_COUNT+FAIL_COUNT))  Pass: ${GREEN}$PASS_COUNT${NC}  Fail: ${RED}$FAIL_COUNT${NC}"
echo -e "${YELLOW}========================================${NC}"

# 返回状态
if [ $FAIL_COUNT -eq 0 ]; then
    exit 0
else
    exit 1
fi
