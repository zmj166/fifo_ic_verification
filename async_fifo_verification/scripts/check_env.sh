#!/bin/bash
# ============================================================================
# 文件名: check_env.sh
# 描述:   检查仿真工具是否正确安装和配置
# ============================================================================

echo "============================================"
echo "  Environment Check for IC Verification"
echo "============================================"

check_tool() {
    local tool=$1
    local desc=$2
    if command -v $tool &> /dev/null; then
        VERSION=$(${tool} -version 2>&1 | head -1)
        echo "  ✓ $desc: $VERSION"
    else
        echo "  ✗ $desc: NOT FOUND (set PATH correctly)"
    fi
}

echo ""
echo "--- EDA Tools ---"
check_tool "vcs"      "VCS (Synopsys)"
check_tool "verdi"    "Verdi (Synopsys)"
check_tool "vsim"     "QuestaSim (Mentor)"
check_tool "vlog"     "Vlog (Mentor)"

echo ""
echo "--- System Tools ---"
check_tool "make"     "Make"
check_tool "perl"     "Perl"
check_tool "python3"  "Python3"

echo ""
echo "--- License Check ---"
if [ -n "$LM_LICENSE_FILE" ]; then
    echo "  ✓ LM_LICENSE_FILE = $LM_LICENSE_FILE"
else
    echo "  ✗ LM_LICENSE_FILE not set!"
fi

echo ""
echo "--- Directory Structure ---"
DIRS=("rtl" "tb" "sim/vcs" "sim/questa" "scripts" "docs" "waves")
for DIR in "${DIRS[@]}"; do
    if [ -d "../$DIR" ]; then
        echo "  ✓ $DIR/"
    else
        echo "  ✗ $DIR/ (missing)"
    fi
done

echo ""
echo "============================================"
