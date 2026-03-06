#!/bin/bash
# ============================================================================
# 文件名: check_env.sh
# 描述:   检查仿真工具是否正确安装和配置
# 适用:   VMware 16 + CentOS 7.9 预配置EDA虚拟机
#
# 说明:   本虚拟机已预装所有EDA工具，License通过MAC地址自动加载。
#         如果工具显示 ✗，通常是License未启动，请检查MAC地址。
# ============================================================================

echo "============================================"
echo "  Environment Check for IC Verification"
echo "  (VMware 16 + CentOS 7.9 EDA Image)"
echo "============================================"

PASS=0
FAIL=0

check_tool() {
    local tool=$1
    local desc=$2
    if command -v $tool &> /dev/null; then
        VERSION=$(${tool} -version 2>&1 | head -1)
        echo "  [OK] $desc"
        echo "       版本: $VERSION"
        PASS=$((PASS+1))
    else
        echo "  [XX] $desc: 未找到"
        echo "       -> 可能License未启动，请检查MAC地址是否为 00:0C:29:9C:3C:E0"
        FAIL=$((FAIL+1))
    fi
}

echo ""
echo "--- EDA仿真工具 ---"
check_tool "vcs"   "VCS MX 2018.09 (Synopsys仿真器)"
check_tool "dve"   "DVE (VCS内置波形工具，命令: dve)"
check_tool "verdi" "Verdi 2018.09-SP2 (波形查看)"
check_tool "vsim"  "QuestaSIM 10.7c (Mentor仿真器)"
check_tool "vlog"  "Vlog (QuestaSIM编译器)"

echo ""
echo "--- 系统工具 ---"
check_tool "make"    "Make (构建工具)"
check_tool "perl"    "Perl"
check_tool "python"  "Python2"
check_tool "python3" "Python3"

echo ""
echo "--- MAC地址确认 ---"
MAC=$(ifconfig 2>/dev/null | grep -i "00:0c:29:9c:3c:e0" | head -1)
if [ -n "$MAC" ]; then
    echo "  [OK] MAC地址正确: 00:0C:29:9C:3C:E0"
    echo "       -> License应可正常加载"
else
    ACTUAL_MAC=$(ifconfig 2>/dev/null | grep "ether\|HWaddr" | head -1 | awk '{print $2}')
    echo "  [XX] MAC地址不匹配！"
    echo "       当前MAC: $ACTUAL_MAC"
    echo "       需要MAC: 00:0C:29:9C:3C:E0"
    echo "       -> 请关闭虚拟机，在VMware中修改MAC地址后重启"
fi

echo ""
echo "--- 目录结构检查 ---"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

DIRS=("rtl" "tb" "sim/vcs" "sim/questa" "scripts" "docs" "waves")
for DIR in "${DIRS[@]}"; do
    if [ -d "$PROJECT_ROOT/$DIR" ]; then
        echo "  [OK] $DIR/"
    else
        echo "  [XX] $DIR/ (缺失)"
    fi
done

echo ""
echo "============================================"
echo "  检查结果: [OK] $PASS 项通过 | [XX] $FAIL 项失败"
if [ $FAIL -eq 0 ]; then
    echo "  状态: 环境正常，可以开始仿真！"
else
    echo "  状态: 请检查上述失败项目"
    echo "  提示: License问题通常只需修正MAC地址即可解决"
fi
echo "============================================"
