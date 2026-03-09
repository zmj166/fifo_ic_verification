#!/bin/bash
# ==============================================================================
# 文件名 : scripts/check_env.sh
# 功  能 : 检查 IC 验证仿真环境是否正确配置
# 适用于 : VMware 16 + CentOS 7.9 预配置 EDA 虚拟机
#
# ── 使用方法 ──────────────────────────────────────────────────────────────────
#   # 第一次使用前先赋予可执行权限（只需一次）
#   chmod +x scripts/check_env.sh
#
#   # 运行检查
#   cd ~/async_fifo_verification-3
#   ./scripts/check_env.sh
#
# ── 脚本检查内容 ──────────────────────────────────────────────────────────────
#   1. EDA 工具是否可以正常调用（vcs、dve、verdi、vsim、vlog）
#   2. MAC 地址是否正确（License 绑定到特定 MAC）
#   3. 项目目录结构是否完整
#
# ── 常见问题 ──────────────────────────────────────────────────────────────────
#   工具显示 [XX]：
#     99% 的原因是 MAC 地址不是 00:0C:29:9C:3C:E0，导致 License 无法加载。
#     解决：关机 → VMware 编辑虚拟机设置 → 网络适配器 → 高级
#           → 手动指定 MAC 为 00:0C:29:9C:3C:E0 → 确定 → 开机
# ==============================================================================

# ── 打印标题 ─────────────────────────────────────────────────────────────────
echo "============================================"
echo "  Environment Check for IC Verification"
echo "  (VMware 16 + CentOS 7.9 EDA Image)"
echo "============================================"

# ── 计数器：记录通过/失败数量 ────────────────────────────────────────────────
PASS=0   # 通过项目数
FAIL=0   # 失败项目数


# ==============================================================================
# 函数定义：check_tool
# 功能：检查单个命令行工具是否可用，并打印版本信息
# 参数：
#   $1 = 工具命令名（如 vcs、verdi）
#   $2 = 工具描述（如 "VCS MX 2018.09 (Synopsys仿真器)"）
# ==============================================================================
check_tool() {
    local tool=$1    # 第一个参数：工具命令名
    local desc=$2    # 第二个参数：工具描述文字

    # command -v 检查命令是否在 PATH 中存在
    # &> /dev/null 把标准输出和标准错误都丢弃（不显示在终端）
    if command -v $tool &> /dev/null; then
        # 工具存在：获取版本信息
        # -version 是大多数 EDA 工具打印版本的参数
        # 2>&1 把标准错误也合并到标准输出（有些工具把版本打到 stderr）
        # head -1 只取版本信息的第一行（版本输出通常是多行）
        VERSION=$(${tool} -version 2>&1 | head -1)
        echo "  [OK] $desc"
        echo "       版本: $VERSION"
        PASS=$((PASS+1))   # 通过计数加1
    else
        # 工具不存在或 License 无效
        echo "  [XX] $desc: 未找到"
        echo "       -> 可能License未启动，请检查MAC地址是否为 00:0C:29:9C:3C:E0"
        FAIL=$((FAIL+1))   # 失败计数加1
    fi
}


# ==============================================================================
# 第一部分：检查 EDA 仿真工具
# ==============================================================================
echo ""
echo "--- EDA仿真工具 ---"

# VCS：Synopsys 的 Verilog/SystemVerilog 编译仿真器
# 编译命令：vcs，生成 simv 可执行文件
check_tool "vcs"   "VCS MX 2018.09 (Synopsys仿真器)"

# DVE：VCS 自带的波形查看工具，不需要额外 License
# 命令：dve，读取 VCD/VPD 格式波形
check_tool "dve"   "DVE (VCS内置波形工具，命令: dve)"

# Verdi：Synopsys 专业波形调试工具，支持代码-波形联动
# 命令：verdi，读取 FSDB 格式波形（需要 Verdi License）
check_tool "verdi" "Verdi 2018.09-SP2 (专业波形调试)"

# vsim：QuestaSIM 的仿真运行命令（批处理和GUI都用它）
check_tool "vsim"  "QuestaSIM 10.7c (Mentor仿真器)"

# vlog：QuestaSIM 的编译器（把 SV/Verilog 编译到库中）
check_tool "vlog"  "Vlog (QuestaSIM编译器)"


# ==============================================================================
# 第二部分：检查系统基础工具
# ==============================================================================
echo ""
echo "--- 系统工具 ---"

# make：Makefile 的执行工具，运行 make sim 等命令必须
check_tool "make"    "Make (构建工具，运行Makefile必须)"

# perl：很多 EDA 工具的后处理脚本用 Perl 写的，通常已预装
check_tool "perl"    "Perl (脚本语言，EDA工具依赖)"

# python/python3：部分自动化脚本需要
check_tool "python"  "Python2"
check_tool "python3" "Python3"


# ==============================================================================
# 第三部分：检查 License MAC 地址
# ==============================================================================
echo ""
echo "--- MAC地址确认 ---"

# License 绑定在 MAC 地址 00:0C:29:9C:3C:E0 上
# 如果虚拟机的 MAC 地址不是这个，所有 EDA 工具都无法获取 License

# ifconfig 列出所有网络接口信息
# grep -i 忽略大小写搜索（MAC 地址可能大写或小写显示）
# head -1 只取第一行（防止多个网卡都匹配时重复输出）
MAC=$(ifconfig 2>/dev/null | grep -i "00:0c:29:9c:3c:e0" | head -1)

if [ -n "$MAC" ]; then
    # -n 检查字符串非空：找到了匹配的 MAC 地址
    echo "  [OK] MAC地址正确: 00:0C:29:9C:3C:E0"
    echo "       -> License应可正常加载"
else
    # MAC 地址不匹配，需要修改虚拟机设置
    # 获取当前实际 MAC 地址（用于提示用户）
    # grep "ether\|HWaddr"：ether 是 CentOS7 的格式，HWaddr 是旧版 Linux 的格式
    # awk '{print $2}'：提取第二列（MAC 地址值）
    ACTUAL_MAC=$(ifconfig 2>/dev/null | grep "ether\|HWaddr" | head -1 | awk '{print $2}')
    echo "  [XX] MAC地址不匹配！"
    echo "       当前MAC: $ACTUAL_MAC"
    echo "       需要MAC: 00:0C:29:9C:3C:E0"
    echo ""
    echo "       修复步骤："
    echo "       1. 关闭虚拟机（不是挂起，要完全关机）"
    echo "       2. VMware -> 编辑虚拟机设置"
    echo "       3. 网络适配器 -> 高级"
    echo "       4. MAC地址 -> 手动填写 00:0C:29:9C:3C:E0"
    echo "       5. 确定 -> 重新开机"
fi


# ==============================================================================
# 第四部分：检查项目目录结构
# ==============================================================================
echo ""
echo "--- 目录结构检查 ---"

# 获取脚本自身所在目录的绝对路径
# $0 是脚本自身的路径
# dirname 取目录部分
# cd ... && pwd 获取规范化的绝对路径（解析 .. 等相对路径符号）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 项目根目录 = 脚本目录的上一级（scripts/ 的父目录）
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 需要检查的目录列表（相对于项目根目录）
DIRS=("rtl" "tb" "sim/vcs" "sim/questa" "scripts" "docs" "waves")

for DIR in "${DIRS[@]}"; do
    if [ -d "$PROJECT_ROOT/$DIR" ]; then
        echo "  [OK] $DIR/"
    else
        echo "  [XX] $DIR/ (缺失)"
        echo "       -> 请确认项目解压完整，或手动创建该目录"
    fi
done


# ==============================================================================
# 最终汇总报告
# ==============================================================================
echo ""
echo "============================================"
echo "  检查结果: [OK] $PASS 项通过 | [XX] $FAIL 项失败"

if [ $FAIL -eq 0 ]; then
    # 全部通过
    echo "  状态: 环境正常，可以开始仿真！"
    echo ""
    echo "  下一步："
    echo "    cd $PROJECT_ROOT/sim/vcs"
    echo "    make sim TEST=normal"
else
    # 有失败项
    echo "  状态: 请检查上述 [XX] 项目"
    echo ""
    echo "  最常见问题：MAC地址不正确导致License无法加载"
    echo "  按照上面的提示修改MAC地址后重新运行此脚本确认"
fi
echo "============================================"
