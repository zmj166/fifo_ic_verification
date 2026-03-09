# ==============================================================================
# 文件名 : sim/vcs/Makefile
# 功  能 : VCS 仿真自动化构建脚本
# 工具版本: VCS MX 2018.09 / Verdi 2018.09-SP2
# 运行环境: VMware 16 + CentOS 7.9 预配置EDA虚拟机
#
# ── 什么是 Makefile ──────────────────────────────────────────────────────────
#   Makefile 是自动化构建工具 make 的配置文件。
#   它定义了一系列"目标"（Target）和对应的命令，
#   使用者只需输入 "make 目标名" 就能自动执行一系列操作，
#   不需要手动输入多条长命令。
#
#   格式规则：
#     目标名: 依赖目标
#     [Tab]命令1          ← 注意：命令行必须用 Tab 缩进，不能用空格！
#     [Tab]命令2
#
#   变量定义：VAR = 值
#   引用变量：$(VAR)
#   条件判断：ifeq / else ifeq / endif
#
# ── 使用方法速查 ─────────────────────────────────────────────────────────────
#   make sim                    运行默认测试（normal）
#   make sim TEST=normal        正常功能测试：先写8个，再读8个
#   make sim TEST=full_empty    满/空边界测试：写满再读空
#   make sim TEST=random        随机并发测试：读写同时进行
#   make regress                一键运行全部三个测试（回归测试）
#   make dve                    用 DVE 打开波形（VCS内置，无需额外License）
#   make verdi                  用 Verdi 打开波形（功能更强，需要License）
#   make cov                    合并覆盖率数据并生成 HTML 报告
#   make clean                  删除所有生成文件，重新开始
# ==============================================================================


# ==============================================================================
# 第一节：工具命令定义
# ==============================================================================

# VCS  : Synopsys 的 Verilog/SystemVerilog 编译仿真器
#        两步流程：vcs 编译 → ./simv 运行
VCS   = vcs

# VERDI: Synopsys 的专业波形调试工具，支持代码-波形联动
#        读取 FSDB 格式波形，功能远强于 DVE
VERDI = verdi

# DVE  : Discovery Visualization Environment，VCS 自带的波形工具
#        轻量级，不需要额外 License，读取 VCD/VPD 格式
DVE   = dve

# URG  : Unified Report Generator，VCS 的覆盖率报告工具
#        把多次仿真的覆盖率数据合并，生成 HTML 报告
URG   = urg


# ==============================================================================
# 第二节：目录路径定义
# ==============================================================================

# 项目根目录：当前目录是 sim/vcs/，往上两级到达项目根
# ../.. 表示：从 sim/vcs/ → sim/ → 项目根/
PROJECT_ROOT = ../..

# RTL 设计代码目录（async_fifo.v 在这里）
RTL_DIR = $(PROJECT_ROOT)/rtl

# 验证代码目录（TB、interface、env、sequence、test、coverage 在这里）
TB_DIR  = $(PROJECT_ROOT)/tb

# 波形输出目录（仿真后 .vcd 和 .fsdb 文件保存在这里）
WAVES_DIR = $(PROJECT_ROOT)/waves


# ==============================================================================
# 第三节：测试选择（通过 make sim TEST=xxx 切换）
# ==============================================================================

# TEST 变量：如果用户没有指定（make sim），默认用 normal
# ?= 表示"仅当变量未定义时赋值"，防止覆盖用户传入的值
TEST ?= normal

# 根据 TEST 变量的值，选择对应的编译宏
# 编译宏通过 +define+ 传给 VCS，在 TB Top 里用 `ifdef 判断
# 这样不需要修改任何代码，只换一个宏定义就能切换测试场景
ifeq ($(TEST),normal)
    # 正常功能测试：验证基本写读顺序正确性
    TEST_DEFINE = +define+NORMAL_TEST
else ifeq ($(TEST),full_empty)
    # 满/空边界测试：验证 wfull/rempty 保护机制
    TEST_DEFINE = +define+FULL_EMPTY_TEST
else ifeq ($(TEST),random)
    # 随机并发测试：读写同时进行，验证CDC在高负载下的正确性
    TEST_DEFINE = +define+RANDOM_TEST
else
    # 未知测试名：默认回退到 normal
    TEST_DEFINE = +define+NORMAL_TEST
endif


# ==============================================================================
# 第四节：源文件列表
# ==============================================================================

# RTL 设计文件（DUT）：只有一个顶层文件，内部包含所有子模块
RTL_FILES = $(RTL_DIR)/async_fifo.v

# TB 顶层文件：通过 `include 引入所有 TB 组件（interface/env/test等）
# VCS 只需要指定顶层，`include 的文件会自动编译
TB_FILES  = $(TB_DIR)/fifo_tb_top.sv

# Include 路径：告诉 VCS 去哪些目录寻找 `include 的文件
# +incdir+路径 是 Verilog/SV 的标准 include 路径指定方式
# 反斜杠 \ 是 Makefile 的续行符，允许把一行命令写成多行
INCDIRS = +incdir+$(TB_DIR)              \
          +incdir+$(TB_DIR)/interface    \
          +incdir+$(TB_DIR)/env          \
          +incdir+$(TB_DIR)/sequence     \
          +incdir+$(TB_DIR)/test         \
          +incdir+$(TB_DIR)/coverage


# ==============================================================================
# 第五节：VCS 编译选项
# ==============================================================================

# VCS_OPTS：传给 vcs 命令的编译选项（影响编译行为和仿真能力）
#
# -full64
#   使用 64 位编译模式。在 64 位 Linux 系统上必须加，
#   支持超过 4GB 的设计，现代 IC 验证的标配。
#
# -sverilog
#   启用 SystemVerilog 语法支持。
#   不加此选项，SV 特有语法（class/interface/assert等）会报错。
#
# -timescale=1ns/1ps
#   设置默认时间单位和精度：
#     1ns  = #1 表示1纳秒（设计中使用的时间单位）
#     1ps  = 仿真时钟内部计算精度（时间分辨率）
#   本设计时钟半周期 5ns，读时钟 6.667ns，需要 ps 级精度才能精确表示。
#
# -debug_access+all
#   开启全信号访问权限。
#   不加此选项：波形文件中可能缺少内部信号，DVE/Verdi 无法看到所有波形。
#   加了此选项：编译速度略慢，但仿真和调试功能完整。
#
# -kdb
#   生成 Verdi KDB（Knowledge Database）知识数据库。
#   这是 Verdi 实现"代码-波形联动"功能的必要条件。
#   如果没有加 -kdb 就用 make verdi，会出现 "no source file" 错误。
#
# +define+DUMP_FSDB
#   定义编译宏 DUMP_FSDB，激活 TB 中被 `ifdef 保护的 FSDB 转储代码：
#     `ifdef DUMP_FSDB
#         $fsdbDumpfile("waves/fifo_sim.fsdb");
#         $fsdbDumpvars(0, fifo_tb_top);
#     `endif
#
# $(TEST_DEFINE)
#   引用上面第三节设置的测试宏，如 +define+NORMAL_TEST
#
# $(INCDIRS)
#   引用上面第四节设置的 include 路径
#
# -l compile.log
#   -l 表示 log：把编译过程的所有输出保存到 compile.log 文件。
#   方便事后查看编译警告和错误，不会因为滚屏而丢失。

VCS_OPTS = -full64 -sverilog -timescale=1ns/1ps  \
           -debug_access+all -kdb                 \
           +define+DUMP_FSDB                      \
           $(TEST_DEFINE)                         \
           $(INCDIRS)                             \
           -l compile.log


# ==============================================================================
# 第六节：覆盖率收集选项
# ==============================================================================

# COV_OPTS：覆盖率相关选项（编译和仿真都需要加）
#
# -cm line+cond+fsm+branch+tgl
#   开启多种覆盖率收集：
#     line   : 行覆盖率 — 每一行代码是否被执行
#     cond   : 条件覆盖率 — 每个条件表达式的 true/false 是否都出现
#     fsm    : 状态机覆盖率 — 状态机每个状态和跳转是否都经历
#     branch : 分支覆盖率 — if/case 每个分支是否都触发
#     tgl    : 翻转覆盖率 — 每个信号是否经历了 0→1 和 1→0
#
# -cm_dir ./coverage_db
#   指定覆盖率数据保存目录。
#   每次 make sim 运行后，数据累积到 coverage_db/，
#   make cov 时用 urg 从这里读取并合并生成报告。

COV_OPTS = -cm line+cond+fsm+branch+tgl -cm_dir ./coverage_db


# ==============================================================================
# 第七节：.PHONY 声明
# ==============================================================================

# .PHONY 告诉 make：这些目标是"伪目标"，不对应实际文件。
# 如果不声明，当目录下恰好有同名文件时，make 会误认为目标已是最新而跳过执行。
# 例如：如果目录下有个叫 clean 的文件，"make clean" 就不会执行——声明后就没这个问题。
.PHONY: all compile sim regress dve verdi cov clean help


# ==============================================================================
# 第八节：构建目标（Targets）
# ==============================================================================

# ── all：默认目标 ─────────────────────────────────────────────────────────────
# 直接输入 "make" 不加目标名时，执行第一个目标（all）
# all 依赖 compile 和 sim，等同于先编译再仿真
all: compile sim


# ── compile：编译目标 ─────────────────────────────────────────────────────────
# 把 RTL 和 TB 代码编译成可执行仿真文件 simv
#
# @echo   : @ 符号表示不把这条命令本身打印出来，只打印命令的输出内容
# mkdir -p: -p 表示路径中的所有父目录一起创建，且目录已存在时不报错
# $(VCS) ... -o simv : 编译命令，-o simv 指定输出文件名为 simv
compile:
	@echo "=============================="
	@echo "  VCS Compile: TEST=$(TEST)"
	@echo "=============================="
	@mkdir -p $(WAVES_DIR)                              # 确保波形输出目录存在
	$(VCS) $(VCS_OPTS) $(COV_OPTS) $(RTL_FILES) $(TB_FILES) -o simv
	@echo "Compile done. See compile.log"


# ── sim：编译+仿真目标 ────────────────────────────────────────────────────────
# sim 依赖 compile，所以 make sim 会先执行 compile，再执行仿真
# 这样保证每次运行仿真前代码都是最新编译的
#
# ./simv $(COV_OPTS) -l sim.log
#   运行编译好的仿真可执行文件
#   $(COV_OPTS) : 仿真时也需要覆盖率选项（收集运行时覆盖率数据）
#   -l sim.log  : 把仿真输出（$display 等）保存到 sim.log
sim: compile
	@echo "=============================="
	@echo "  VCS Simulation: TEST=$(TEST)"
	@echo "=============================="
	./simv $(COV_OPTS) -l sim.log
	@echo "Simulation done. See sim.log"


# ── regress：回归测试目标 ─────────────────────────────────────────────────────
# 依次运行全部三个测试场景，验证所有功能都正确
#
# $(MAKE) : 递归调用 make 本身（而不是直接写 make），
#            这样能继承当前的 Makefile 环境变量，是 Makefile 的最佳实践
# TEST=normal/full_empty/random : 覆盖 TEST 变量，选择不同测试
regress:
	@echo "=== Running Full Regression ==="
	$(MAKE) sim TEST=normal       # 场景1：正常功能（先写后读）
	$(MAKE) sim TEST=full_empty   # 场景2：满/空边界（写满读空）
	$(MAKE) sim TEST=random       # 场景3：随机并发（读写同时）
	@echo "=== Regression Complete ==="


# ── dve：打开 DVE 波形工具 ───────────────────────────────────────────────────
# DVE 是 VCS 自带的轻量级波形查看工具，不需要额外 License
#
# -vcd 文件路径 : 加载 VCD 格式波形文件
#   注意：早期版本用 -vpd，新版本用 -vcd，参数名不同会报错
# & : 让 DVE 在后台运行，终端继续可用（不会被 DVE 阻塞）
dve:
	$(DVE) -vcd $(WAVES_DIR)/fifo_sim.vcd &


# ── verdi：打开 Verdi 波形工具 ───────────────────────────────────────────────
# Verdi 是专业级波形调试工具，比 DVE 功能强大很多
# 支持：代码-波形联动、信号驱动追踪、层级式原理图等高级功能
#
# -sv         : 告诉 Verdi 使用 SystemVerilog 模式解析设计
# -ssf 文件   : Specify Signal File，加载 FSDB 格式波形
#   FSDB 比 VCD 小 5~10 倍，加载更快，Verdi 原生支持
# -nologo     : 启动时不显示版权 Logo 画面，加快启动速度
# &           : 后台运行
verdi:
	$(VERDI) -sv -ssf $(WAVES_DIR)/fifo_sim.fsdb -nologo &


# ── cov：生成覆盖率 HTML 报告 ─────────────────────────────────────────────────
# 先运行 make regress 收集覆盖率数据，再运行 make cov 生成报告
#
# urg 工具的用法：
#   -dir ./coverage_db  : 从 coverage_db/ 目录读取覆盖率数据
#   -report ./coverage_report : 把 HTML 报告输出到 coverage_report/ 目录
#
# 报告生成后用浏览器打开：
#   firefox coverage_report/dashboard.html &
cov:
	$(URG) -dir ./coverage_db -report ./coverage_report
	@echo "Coverage report: ./coverage_report/dashboard.html"
	@echo "Open with: firefox coverage_report/dashboard.html &"


# ── clean：清理所有生成文件 ───────────────────────────────────────────────────
# 删除所有编译和仿真产生的中间文件，恢复到干净状态
# 当遇到奇怪的编译错误、文件冲突时，make clean 后重新 make sim 通常能解决
#
# rm -rf     : 强制递归删除，不提示确认
# simv       : VCS 编译生成的仿真可执行文件
# simv.daidir: VCS 的调试信息目录
# csrc       : VCS 内部编译缓存目录
# *.log      : 所有日志文件（compile.log、sim.log）
# *.key      : VCS/Verdi 的 License key 临时文件
# vc_hdrs.h  : VCS 生成的头文件
# coverage_db: 覆盖率数据库目录
# coverage_report: 覆盖率 HTML 报告目录
# novas.*    : Verdi/Novas 的配置文件
# verdiLog   : Verdi 的日志目录
# ucli.key   : VCS 的 UCli 接口临时文件
# *.vcd *.fsdb: 波形文件（体积可能很大）
clean:
	rm -rf simv simv.daidir csrc
	rm -rf *.log *.key vc_hdrs.h
	rm -rf coverage_db coverage_report
	rm -rf novas.* verdiLog ucli.key
	rm -rf $(WAVES_DIR)/*.vcd $(WAVES_DIR)/*.fsdb
	@echo "Clean done. Ready for fresh compile."


# ── help：打印帮助信息 ────────────────────────────────────────────────────────
# 快速提示可用的 make 目标和用法，忘记命令时很有用
help:
	@echo ""
	@echo "  VCS 仿真 Makefile 使用说明"
	@echo "  =================================="
	@echo "  make sim                  运行默认测试（normal）"
	@echo "  make sim TEST=normal      正常功能测试"
	@echo "  make sim TEST=full_empty  满/空边界测试"
	@echo "  make sim TEST=random      随机并发测试"
	@echo "  make regress              一键回归（全部3个测试）"
	@echo "  make dve                  打开 DVE 查看 VCD 波形"
	@echo "  make verdi                打开 Verdi 查看 FSDB 波形"
	@echo "  make cov                  生成覆盖率 HTML 报告"
	@echo "  make clean                清理所有生成文件"
	@echo "  make help                 显示本帮助"
	@echo ""
