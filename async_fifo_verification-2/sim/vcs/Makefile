# ============================================================================
# Makefile for VCS Simulation
# 工具版本: VCS MX 2018.09 / Verdi 2018.09-SP2
# 运行环境: VMware 16 + CentOS 7.9 预配置EDA虚拟机
#
# Usage:
#   make sim               - 运行默认测试（normal）
#   make sim TEST=normal   - 正常功能测试
#   make sim TEST=full_empty - 满空边界测试
#   make sim TEST=random   - 随机并发测试
#   make regress           - 运行全部测试
#   make dve               - 打开DVE波形查看（VCS内置，较轻量）
#   make verdi             - 打开Verdi波形查看（功能更强大）
#   make cov               - 生成覆盖率报告
#   make clean             - 清理仿真文件
# ============================================================================

VCS       = vcs
VERDI     = verdi
DVE       = dve
URG       = urg

PROJECT_ROOT = ../..
RTL_DIR      = $(PROJECT_ROOT)/rtl
TB_DIR       = $(PROJECT_ROOT)/tb
WAVES_DIR    = $(PROJECT_ROOT)/waves

# Test selection
TEST ?= normal
ifeq ($(TEST),normal)
    TEST_DEFINE = +define+NORMAL_TEST
else ifeq ($(TEST),full_empty)
    TEST_DEFINE = +define+FULL_EMPTY_TEST
else ifeq ($(TEST),random)
    TEST_DEFINE = +define+RANDOM_TEST
else
    TEST_DEFINE = +define+NORMAL_TEST
endif

# Source files
RTL_FILES = $(RTL_DIR)/async_fifo.v
TB_FILES  = $(TB_DIR)/fifo_tb_top.sv

# Include directories
INCDIRS = +incdir+$(TB_DIR) \
          +incdir+$(TB_DIR)/interface \
          +incdir+$(TB_DIR)/env \
          +incdir+$(TB_DIR)/sequence \
          +incdir+$(TB_DIR)/test \
          +incdir+$(TB_DIR)/coverage

# VCS compile options
# -full64       : 64-bit compile mode
# -sverilog     : Enable SystemVerilog
# -debug_access : Enable full signal access for waveform
# -kdb          : Generate Verdi KDB database
# +define+DUMP_FSDB : Enable FSDB waveform dump
VCS_OPTS = -full64 -sverilog -timescale=1ns/1ps \
           -debug_access+all -kdb \
           +define+DUMP_FSDB \
           $(TEST_DEFINE) \
           $(INCDIRS) \
           -l compile.log

# Coverage options
# -cm line+cond+fsm+branch+tgl : Enable multiple coverage types
COV_OPTS = -cm line+cond+fsm+branch+tgl -cm_dir ./coverage_db

.PHONY: all compile sim regress dve verdi cov clean help

all: compile sim

compile:
	@echo "=============================="
	@echo "  VCS Compile: TEST=$(TEST)"
	@echo "=============================="
	@mkdir -p $(WAVES_DIR)
	$(VCS) $(VCS_OPTS) $(COV_OPTS) $(RTL_FILES) $(TB_FILES) -o simv
	@echo "Compile done. See compile.log"

sim: compile
	@echo "=============================="
	@echo "  VCS Simulation: TEST=$(TEST)"
	@echo "=============================="
	./simv $(COV_OPTS) -l sim.log
	@echo "Simulation done. See sim.log"

regress:
	@echo "=== Running Full Regression ==="
	$(MAKE) sim TEST=normal
	$(MAKE) sim TEST=full_empty
	$(MAKE) sim TEST=random
	@echo "=== Regression Complete ==="

# Open DVE with VCD waveform（轻量级波形查看，VCS内置）
# DVE是VCS自带的波形工具，不需要额外license
dve:
	$(DVE) -vpd $(WAVES_DIR)/fifo_sim.vcd &

# Open Verdi with FSDB waveform（功能更强大，需要Verdi license）
verdi:
	$(VERDI) -sv -ssf $(WAVES_DIR)/fifo_sim.fsdb -nologo &

# Merge and report coverage
cov:
	$(URG) -dir ./coverage_db -report ./coverage_report
	@echo "Coverage report: ./coverage_report/dashboard.html"

clean:
	rm -rf simv simv.daidir csrc
	rm -rf *.log *.key vc_hdrs.h
	rm -rf coverage_db coverage_report
	rm -rf novas.* verdiLog ucli.key
	rm -rf $(WAVES_DIR)/*.vcd $(WAVES_DIR)/*.fsdb
	@echo "Clean done."

help:
	@echo "Targets: all compile sim regress dve verdi cov clean"
	@echo "TEST options: normal, full_empty, random"
