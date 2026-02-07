###############################################################################
# Makefile for RISC-V TCM Testbench
###############################################################################

# Path configuration
TB_HOME = $(shell pwd)
RTL_HOME = $(TB_HOME)/../..

# Tool paths
VERILATOR = verilator
VERILATOR_SRC ?= /usr/share/verilator/include
SYSTEMC_HOME ?= /usr/local/systemc-2.3.3

# Check tool paths
ifeq (,$(wildcard $(VERILATOR_SRC)))
  $(error VERILATOR_SRC must be set to VERILATOR_INSTALL/include)
endif
ifeq (,$(wildcard $(SYSTEMC_HOME)))
  $(error SYSTEMC_HOME must be set)
endif

# RTL source files
RTL_TOP = riscv_tcm_top
RTL_SRC = $(RTL_HOME)/src/top/$(RTL_TOP).v
RTL_INC_DIRS = $(RTL_HOME)/src/top $(RTL_HOME)/src/core $(RTL_HOME)/src/tcm

# Testbench source files
TB_CPPSRC = $(TB_HOME)/*.cpp
TB_INC = $(TB_HOME)

# Test configuration
TEST_IMAGE ?= $(TB_HOME)/test.elf

# Build directories
OBJ_DIR = obj_dir
WAVE_FILE = wave.vcd

# Verilator flags
V_FLAGS = --sc --exe $(TB_CPPSRC)
V_FLAGS += --top $(RTL_TOP)
V_FLAGS += --Mdir $(OBJ_DIR)
V_FLAGS += --trace
V_FLAGS += --pins-sc-uint
V_FLAGS += --unroll-count 512
V_FLAGS += --public-flat-rw
V_FLAGS += --timescale-override 1ns/1ns
V_FLAGS += -Wno-fatal
V_FLAGS += $(addprefix -I, $(RTL_INC_DIRS))

# Check Verilator version for --l2-name support
OLDER_VERILATOR := $(shell $(VERILATOR) --l2-name v 2>&1 | grep "Invalid Option" | wc -l)
ifeq ($(OLDER_VERILATOR),0)
  V_FLAGS += --l2-name v
endif

# Compiler flags
INC_PATH = $(TB_INC) $(SYSTEMC_HOME)/include
CFLAGS = -DVM_TRACE=1 -DVL_USER_FINISH=1 -O2
CFLAGS += $(addprefix -I, $(INC_PATH))

# Linker flags
LDFLAGS = -L$(SYSTEMC_HOME)/lib-linux64 -lsystemc -lelf -lbfd

# Final executable
EXE = $(OBJ_DIR)/V$(RTL_TOP)

###############################################################################
# Targets
###############################################################################
.PHONY: all build_rtl build_simu run clean help

all: build_rtl

# Step 1: Run Verilator to generate C++ model
build_rtl: $(RTL_SRC) $(wildcard $(TB_HOME)/*.cpp) $(wildcard $(TB_HOME)/*.h)
	@echo "=== Running Verilator ==="
	$(VERILATOR) $(V_FLAGS) $(RTL_SRC) --CFLAGS "$(CFLAGS)" --LDFLAGS "$(LDFLAGS)"

# Step 2: Compile the executable
build_simu: build_rtl
	@echo "=== Building executable ==="
	$(MAKE) -C $(OBJ_DIR) -f V$(RTL_TOP).mk -j5

# Step 3: Run simulation
run: $(EXE)
	@echo "Running testbench with: $(TEST_IMAGE)"
	$(EXE) -f $(TEST_IMAGE)

# Clean all generated files
clean:
	@rm -rf $(OBJ_DIR) $(WAVE_FILE) *.vcd

# Help information
help:
	@echo "======================================================================"
	@echo " RISC-V TCM Testbench Makefile Help"
	@echo "======================================================================"
	@echo "Usage:"
	@echo "  make [target]"
	@echo ""
	@echo "Available targets:"
	@echo "  all           : Build RTL model (default target)"
	@echo "  build_rtl     : Run Verilator to generate C++ model from RTL"
	@echo "  build_simu    : Compile the executable from the generated model"
	@echo "  run           : Run simulation with test image ($(TEST_IMAGE))"
	@echo "  clean         : Remove all generated files"
	@echo "  help          : Display this help message"
	@echo ""
	@echo "Configuration:"
	@echo "  RTL_TOP       : $(RTL_TOP)"
	@echo "  RTL_SRC       : $(RTL_SRC)"
	@echo "  TEST_IMAGE    : $(TEST_IMAGE)"
	@echo "  OBJ_DIR       : $(OBJ_DIR)"
	@echo "  SYSTEMC_HOME  : $(SYSTEMC_HOME)"
	@echo "  VERILATOR_SRC : $(VERILATOR_SRC)"
	@echo ""
	@echo "Verilator flags:"
	@echo "  $(V_FLAGS)"
	@echo ""
	@echo "Compiler flags:"
	@echo "  $(CFLAGS)"
	@echo ""
	@echo "Linker flags:"
	@echo "  $(LDFLAGS)"
	@echo "======================================================================"
