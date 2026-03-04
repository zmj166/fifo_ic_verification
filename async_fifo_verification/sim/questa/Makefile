# ============================================================================
# Makefile for QuestaSim Simulation
# Usage:
#   make sim              - Batch simulation (normal test)
#   make sim TEST=<name>  - Run specific test
#   make gui              - GUI mode with waveforms
#   make regress          - Run all tests
#   make cov              - Coverage report
#   make clean            - Clean files
# ============================================================================

VLIB  = vlib
VMAP  = vmap
VLOG  = vlog
VSIM  = vsim

PROJECT_ROOT = ../..
RTL_DIR      = $(PROJECT_ROOT)/rtl
TB_DIR       = $(PROJECT_ROOT)/tb
WAVES_DIR    = $(PROJECT_ROOT)/waves
WORK_LIB     = work

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

RTL_FILES = $(RTL_DIR)/async_fifo.v
TB_FILES  = $(TB_DIR)/fifo_tb_top.sv

INCDIRS = +incdir+$(TB_DIR) \
          +incdir+$(TB_DIR)/interface \
          +incdir+$(TB_DIR)/env \
          +incdir+$(TB_DIR)/sequence \
          +incdir+$(TB_DIR)/test \
          +incdir+$(TB_DIR)/coverage

# vlog compile options
# -sv          : SystemVerilog mode
# +acc         : Enable full access (needed for waveform)
VLOG_OPTS = -sv -timescale "1ns/1ps" +acc \
            $(TEST_DEFINE) $(INCDIRS) -l compile.log

# Batch simulation options
VSIM_BATCH = -batch -do "run -all; quit -f" -l sim.log

# GUI simulation options  
VSIM_GUI   = -gui -do questa_wave.do

# Coverage
COV_OPTS = +cover=bcefst -coverdb coverage_db

.PHONY: all lib compile sim gui regress cov clean help

all: lib compile sim

lib:
	$(VLIB) $(WORK_LIB)
	$(VMAP) $(WORK_LIB) $(WORK_LIB)

compile: lib
	@echo "=============================="
	@echo "  Questa Compile: TEST=$(TEST)"
	@echo "=============================="
	@mkdir -p $(WAVES_DIR)
	$(VLOG) -work $(WORK_LIB) $(VLOG_OPTS) $(RTL_FILES)
	$(VLOG) -work $(WORK_LIB) $(VLOG_OPTS) $(TB_FILES)
	@echo "Compile done."

sim: compile
	@echo "=============================="
	@echo "  Questa Simulation: TEST=$(TEST)"
	@echo "=============================="
	$(VSIM) -work $(WORK_LIB) $(COV_OPTS) $(VSIM_BATCH) fifo_tb_top
	@echo "Simulation done. See sim.log"

gui: compile
	@echo "Opening QuestaSim GUI..."
	$(VSIM) -work $(WORK_LIB) $(VSIM_GUI) fifo_tb_top &

regress:
	$(MAKE) sim TEST=normal
	$(MAKE) sim TEST=full_empty
	$(MAKE) sim TEST=random

cov:
	vcover report coverage_db -html -output coverage_html
	@echo "Coverage at coverage_html/index.html"

clean:
	rm -rf $(WORK_LIB) modelsim.ini
	rm -rf *.log transcript
	rm -rf coverage_db coverage_html
	rm -rf $(WAVES_DIR)/*.vcd
	@echo "Clean done."

help:
	@echo "Targets: all lib compile sim gui regress cov clean"
