module biriscv_issue
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MULDIV   = 1
    ,parameter SUPPORT_DUAL_ISSUE = 1
    ,parameter SUPPORT_LOAD_BYPASS = 1
    ,parameter SUPPORT_MUL_BYPASS = 1
    ,parameter SUPPORT_REGFILE_XILINX = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i

    //来自前端frontend，指令0信息
    ,input           fetch0_valid_i
    ,input  [ 31:0]  fetch0_instr_i
    ,input  [ 31:0]  fetch0_pc_i
    ,input           fetch0_fault_fetch_i
    ,input           fetch0_fault_page_i
    ,input           fetch0_instr_exec_i
    ,input           fetch0_instr_lsu_i
    ,input           fetch0_instr_branch_i
    ,input           fetch0_instr_mul_i
    ,input           fetch0_instr_div_i
    ,input           fetch0_instr_csr_i
    ,input           fetch0_instr_rd_valid_i
    ,input           fetch0_instr_invalid_i
    //来自前端frontend，指令1信息
    ,input           fetch1_valid_i
    ,input  [ 31:0]  fetch1_instr_i
    ,input  [ 31:0]  fetch1_pc_i
    ,input           fetch1_fault_fetch_i
    ,input           fetch1_fault_page_i
    ,input           fetch1_instr_exec_i
    ,input           fetch1_instr_lsu_i
    ,input           fetch1_instr_branch_i
    ,input           fetch1_instr_mul_i
    ,input           fetch1_instr_div_i
    ,input           fetch1_instr_csr_i
    ,input           fetch1_instr_rd_valid_i
    ,input           fetch1_instr_invalid_i

    //来自exu，指令0的跳转信息
    ,input           branch_exec0_request_i
    ,input           branch_exec0_is_taken_i
    ,input           branch_exec0_is_not_taken_i
    ,input  [ 31:0]  branch_exec0_source_i
    ,input           branch_exec0_is_call_i
    ,input           branch_exec0_is_ret_i
    ,input           branch_exec0_is_jmp_i
    ,input  [ 31:0]  branch_exec0_pc_i
    ,input           branch_d_exec0_request_i
    ,input  [ 31:0]  branch_d_exec0_pc_i
    ,input  [  1:0]  branch_d_exec0_priv_i
    //来自exu，指令1的跳转信息
    ,input           branch_exec1_request_i
    ,input           branch_exec1_is_taken_i
    ,input           branch_exec1_is_not_taken_i
    ,input  [ 31:0]  branch_exec1_source_i
    ,input           branch_exec1_is_call_i
    ,input           branch_exec1_is_ret_i
    ,input           branch_exec1_is_jmp_i
    ,input  [ 31:0]  branch_exec1_pc_i
    ,input           branch_d_exec1_request_i
    ,input  [ 31:0]  branch_d_exec1_pc_i
    ,input  [  1:0]  branch_d_exec1_priv_i
    ,input           branch_csr_request_i
    ,input  [ 31:0]  branch_csr_pc_i
    ,input  [  1:0]  branch_csr_priv_i

    //来自exu，需要写入issue中的regfile
    ,input  [ 31:0]  writeback_exec0_value_i
    ,input  [ 31:0]  writeback_exec1_value_i

    //来自lsu
    ,input           writeback_mem_valid_i
    ,input  [ 31:0]  writeback_mem_value_i
    ,input  [  5:0]  writeback_mem_exception_i

    //来自乘除法计算单元
    ,input  [ 31:0]  writeback_mul_value_i
    ,input           writeback_div_valid_i
    ,input  [ 31:0]  writeback_div_value_i
    //来自csr
    ,input  [ 31:0]  csr_result_e1_value_i
    ,input           csr_result_e1_write_i
    ,input  [ 31:0]  csr_result_e1_wdata_i
    ,input  [  5:0]  csr_result_e1_exception_i
    //来自lsu
    ,input           lsu_stall_i
    ,input           take_interrupt_i

    // Outputs
    //传递给前端frontend，用于分支预测器的更新和学习
    ,output          fetch0_accept_o
    ,output          fetch1_accept_o
    ,output          branch_request_o
    ,output [ 31:0]  branch_pc_o
    ,output [  1:0]  branch_priv_o
    ,output          branch_info_request_o
    ,output          branch_info_is_taken_o
    ,output          branch_info_is_not_taken_o
    ,output [ 31:0]  branch_info_source_o
    ,output          branch_info_is_call_o
    ,output          branch_info_is_ret_o
    ,output          branch_info_is_jmp_o
    ,output [ 31:0]  branch_info_pc_o

    //传给exu
    ,output          exec0_opcode_valid_o
    ,output          exec1_opcode_valid_o
    //传给lsu、csr、mul、div单元
    ,output          lsu_opcode_valid_o
    ,output          csr_opcode_valid_o
    ,output          mul_opcode_valid_o
    ,output          div_opcode_valid_o

    //指令0，传给exu计算
    ,output [ 31:0]  opcode0_opcode_o
    ,output [ 31:0]  opcode0_pc_o
    ,output          opcode0_invalid_o
    ,output [  4:0]  opcode0_rd_idx_o
    ,output [  4:0]  opcode0_ra_idx_o
    ,output [  4:0]  opcode0_rb_idx_o
    ,output [ 31:0]  opcode0_ra_operand_o
    ,output [ 31:0]  opcode0_rb_operand_o
    //指令1，传给exu计算
    ,output [ 31:0]  opcode1_opcode_o
    ,output [ 31:0]  opcode1_pc_o
    ,output          opcode1_invalid_o
    ,output [  4:0]  opcode1_rd_idx_o
    ,output [  4:0]  opcode1_ra_idx_o
    ,output [  4:0]  opcode1_rb_idx_o
    ,output [ 31:0]  opcode1_ra_operand_o
    ,output [ 31:0]  opcode1_rb_operand_o

    //传给lsu
    ,output [ 31:0]  lsu_opcode_opcode_o
    ,output [ 31:0]  lsu_opcode_pc_o
    ,output          lsu_opcode_invalid_o
    ,output [  4:0]  lsu_opcode_rd_idx_o
    ,output [  4:0]  lsu_opcode_ra_idx_o
    ,output [  4:0]  lsu_opcode_rb_idx_o
    ,output [ 31:0]  lsu_opcode_ra_operand_o
    ,output [ 31:0]  lsu_opcode_rb_operand_o
    ,output [ 31:0]  mul_opcode_opcode_o
    ,output [ 31:0]  mul_opcode_pc_o
    ,output          mul_opcode_invalid_o
    ,output [  4:0]  mul_opcode_rd_idx_o
    ,output [  4:0]  mul_opcode_ra_idx_o
    ,output [  4:0]  mul_opcode_rb_idx_o
    ,output [ 31:0]  mul_opcode_ra_operand_o
    ,output [ 31:0]  mul_opcode_rb_operand_o
    ,output [ 31:0]  csr_opcode_opcode_o
    ,output [ 31:0]  csr_opcode_pc_o
    ,output          csr_opcode_invalid_o
    ,output [  4:0]  csr_opcode_rd_idx_o
    ,output [  4:0]  csr_opcode_ra_idx_o
    ,output [  4:0]  csr_opcode_rb_idx_o
    ,output [ 31:0]  csr_opcode_ra_operand_o
    ,output [ 31:0]  csr_opcode_rb_operand_o
    ,output          csr_writeback_write_o
    ,output [ 11:0]  csr_writeback_waddr_o
    ,output [ 31:0]  csr_writeback_wdata_o
    ,output [  5:0]  csr_writeback_exception_o
    ,output [ 31:0]  csr_writeback_exception_pc_o
    ,output [ 31:0]  csr_writeback_exception_addr_o

    ,output          exec0_hold_o
    ,output          exec1_hold_o
    ,output          mul_hold_o
    ,output          interrupt_inhibit_o

    //传给npc，记录分支预测错误的指令类型
    ,output [31:0]   mispredicted_all_o
    ,output [31:0]   mispredicted_is_call_o
    ,output [31:0]   mispredicted_is_ret_o
    ,output [31:0]   mispredicted_is_jmp_o
    ,output [31:0]   mispredicted_is_other_o
);

`include "biriscv_defs.v"

wire enable_dual_issue_w = SUPPORT_DUAL_ISSUE;
wire enable_muldiv_w     = SUPPORT_MULDIV;
wire enable_mul_bypass_w = SUPPORT_MUL_BYPASS;

wire stall_w;
wire squash_w;

//-------------------------------------------------------------
// PC--流水线pc更新逻辑
//-------------------------------------------------------------
wire        single_issue_w;
wire        dual_issue_w;
reg  [31:0] pc_x_q;
reg   [1:0] priv_x_q;
//支持分支恢复
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pc_x_q <= 32'b0;
else if (branch_csr_request_i)
    pc_x_q <= branch_csr_pc_i;
else if (branch_d_exec1_request_i)
    pc_x_q <= branch_d_exec1_pc_i;
else if (branch_d_exec0_request_i)
    pc_x_q <= branch_d_exec0_pc_i;
else if (dual_issue_w)
    pc_x_q <= pc_x_q + 32'd8;
else if (single_issue_w)
    pc_x_q <= pc_x_q + 32'd4;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    priv_x_q <= `PRIV_MACHINE;
else if (branch_csr_request_i)
    priv_x_q <= branch_csr_priv_i; //2'b11

//-------------------------------------------------------------
// Issue Select
//-------------------------------------------------------------
reg mispredicted_r;
reg slot0_valid_r;
reg slot1_valid_r;

always @ *
begin
    mispredicted_r = 1'b0;
    slot0_valid_r  = 1'b0;
    slot1_valid_r  = 1'b0;

    // Flush due to CSR branch
    if (branch_csr_request_i || squash_w)
    begin
        slot0_valid_r  = 1'b0; //这两个信号不会同时拉高
        slot1_valid_r  = 1'b0;
    end
    // Word 0 valid and expected PC (word 1 may also be valid)
    else if (fetch0_valid_i && {fetch0_pc_i[31:2], 2'b0} == {pc_x_q[31:2], 2'b0})
        slot0_valid_r  = 1'b1; //标记指令0是有效指令
    // Word 1 valid and expected PC
    else if (fetch1_valid_i && {fetch1_pc_i[31:2], 2'b0} == {pc_x_q[31:2], 2'b0})
        slot1_valid_r  = 1'b1; //标记指令1是有效指令
    // Neither word is the expected PC - must be a branch misprediction
    else if ((fetch0_valid_i || fetch1_valid_i)) //两条指令有效，但是不匹配预期的pc_x_q
        mispredicted_r = 1'b1;
end

//当issue识别到预测的指令和实际取到的指令不相匹配时，mispredicted_r信号拉高
//本模块用于检测发生错误的是哪种类型的分支指令（jmp、ret、call），以及有多少条其他指令预测错误
reg [31:0]      mispredicted_is_jmp;
reg [31:0]      mispredicted_is_ret;
reg [31:0]      mispredicted_is_call;
reg [31:0]      mispredicted_is_other;
reg [31:0]      mispredicted_all;
always@(posedge clk_i or posedge rst_i) begin
    if(rst_i) begin
        mispredicted_is_jmp    <=  32'b0;
        mispredicted_is_ret    <=  32'b0;
        mispredicted_is_call   <=  32'b0;
        mispredicted_is_other  <=  32'b0;
        mispredicted_all       <=  32'b0;
    end
    else if(mispredicted_r) begin
        if(branch_exec0_is_call_i) begin
            mispredicted_is_call  <= mispredicted_is_call + 1'b1;
            mispredicted_all      <= mispredicted_all + 1'b1; end
        else if(branch_exec0_is_ret_i) begin
            mispredicted_is_ret   <= mispredicted_is_ret + 1'b1;
            mispredicted_all      <= mispredicted_all + 1'b1; end
        else if(branch_exec0_is_jmp_i) begin //直接跳转，间接跳转
            mispredicted_is_jmp   <= mispredicted_is_jmp + 1'b1;
            mispredicted_all      <= mispredicted_all + 1'b1; end
        else begin //分支指令
            mispredicted_is_other <= mispredicted_is_other + 1'b1;
            mispredicted_all      <= mispredicted_all + 1'b1; end
    end
    else begin
            mispredicted_is_jmp   <= mispredicted_is_jmp;
            mispredicted_is_call  <= mispredicted_is_call;
            mispredicted_is_ret   <= mispredicted_is_ret;
            mispredicted_is_other <= mispredicted_is_other;
            mispredicted_all      <= mispredicted_all;
    end
end
assign mispredicted_is_jmp_o    = mispredicted_is_jmp;
assign mispredicted_is_ret_o    = mispredicted_is_ret;
assign mispredicted_is_call_o   = mispredicted_is_call;
assign mispredicted_is_other_o  = mispredicted_is_other;
assign mispredicted_all_o       = mispredicted_all;

// Branch request (CSR branch - ecall, xret, or branch misprediction)
// Note: Correctly predicted branches are silent
assign branch_request_o          = branch_csr_request_i | mispredicted_r; //这里的csr请求只在开头拉高一拍
assign branch_pc_o               = branch_csr_request_i ? branch_csr_pc_i : pc_x_q;
assign branch_priv_o             = branch_csr_request_i ? branch_csr_priv_i : priv_x_q; //一直为2'b11

//-------------------------------------------------------------
// Instruction Decoder
//-------------------------------------------------------------
reg        opcode_a_valid_r;// Slot A指令有效标志
reg        opcode_b_valid_r;// Slot B指令有效标志
reg [1:0]  opcode_a_fault_r;// Slot A异常标志（页面错误、取指错误）
reg [1:0]  opcode_b_fault_r;// Slot B异常标志
reg [31:0] opcode_a_r;      // Slot A指令编码
reg [31:0] opcode_b_r;      // Slot B指令编码
reg [31:0] opcode_a_pc_r;   // Slot A指令PC
reg [31:0] opcode_b_pc_r;   // Slot B指令PC

always @ *
begin
    opcode_a_r       = 32'b0;
    opcode_b_r       = 32'b0;
    opcode_a_valid_r = 1'b0;
    opcode_b_valid_r = 1'b0;
    opcode_a_fault_r = 2'b0;
    opcode_b_fault_r = 2'b0;
    opcode_a_pc_r    = 32'b0;
    opcode_b_pc_r    = 32'b0;

    // 情况1：Word 0有效（可能Word 1也有效）
    // 理想情况：同时获取两条连续指令（fetch0和fetch1都有效）
    // 如果两条都有效，可以尝试双发射
    // 异常信息随指令一起传递
    if (slot0_valid_r)
    begin
        opcode_a_valid_r = 1'b1;
        opcode_a_r       = fetch0_instr_i; //仅当fetch1也有效时
        opcode_a_pc_r    = fetch0_pc_i;
        opcode_a_fault_r = {fetch0_fault_page_i, fetch0_fault_fetch_i};
        opcode_b_valid_r = fetch1_valid_i;
        opcode_b_r       = fetch1_instr_i;
        opcode_b_pc_r    = fetch1_pc_i;
        opcode_b_fault_r = {fetch1_fault_page_i, fetch1_fault_fetch_i};
    end
    // Word 1 valid - mux to first issue slot
    // Note: Some instruction types can only issue in slot0, hence this muxing
    // 情况2：只有word 1有效
    // 处理指令不连续情况（如分支目标不对齐）
    // 某些指令类型只能在Slot A发射（如CSR、除法指令）
    // 将单独的有效指令移动到Slot A
    else if (slot1_valid_r)
    begin
        opcode_a_valid_r = 1'b1;
        opcode_a_r       = fetch1_instr_i;   //将fetch1移到Slot A
        opcode_a_pc_r    = fetch1_pc_i;
        opcode_a_fault_r = {fetch1_fault_page_i, fetch1_fault_fetch_i};
        opcode_b_valid_r = 1'b0;  //Slot B无效
        opcode_b_r       = 32'b0; //Slot B清空
        opcode_b_pc_r    = 32'b0;
        opcode_b_fault_r = 2'b0;
    end
end

//Slot A指令信息提取
wire [4:0] issue_a_ra_idx_w   = opcode_a_r[19:15]; // rs1（源寄存器1）
wire [4:0] issue_a_rb_idx_w   = opcode_a_r[24:20]; // rs2（源寄存器2）
wire [4:0] issue_a_rd_idx_w   = opcode_a_r[11:7];  // rd（目标寄存器）
//根据slot0_valid_r决定使用哪个取指通道的信息
wire       issue_a_sb_alloc_w = (slot0_valid_r ? fetch0_instr_rd_valid_i : fetch1_instr_rd_valid_i);
wire       issue_a_exec_w     = (slot0_valid_r ? fetch0_instr_exec_i     : fetch1_instr_exec_i);
wire       issue_a_lsu_w      = (slot0_valid_r ? fetch0_instr_lsu_i      : fetch1_instr_lsu_i);
wire       issue_a_branch_w   = (slot0_valid_r ? fetch0_instr_branch_i   : fetch1_instr_branch_i);
wire       issue_a_mul_w      = (slot0_valid_r ? fetch0_instr_mul_i      : fetch1_instr_mul_i);
wire       issue_a_div_w      = (slot0_valid_r ? fetch0_instr_div_i      : fetch1_instr_div_i);
wire       issue_a_csr_w      = (slot0_valid_r ? fetch0_instr_csr_i      : fetch1_instr_csr_i);
wire       issue_a_invalid_w  = (slot0_valid_r ? fetch0_instr_invalid_i  : fetch1_instr_invalid_i);

//Slot B指令信息提取
wire [4:0] issue_b_ra_idx_w   = opcode_b_r[19:15];
wire [4:0] issue_b_rb_idx_w   = opcode_b_r[24:20];
wire [4:0] issue_b_rd_idx_w   = opcode_b_r[11:7];

wire       issue_b_sb_alloc_w = fetch1_instr_rd_valid_i;
wire       issue_b_exec_w     = fetch1_instr_exec_i;
wire       issue_b_lsu_w      = fetch1_instr_lsu_i;
wire       issue_b_branch_w   = fetch1_instr_branch_i;
wire       issue_b_mul_w      = fetch1_instr_mul_i;
wire       issue_b_div_w      = fetch1_instr_div_i;
wire       issue_b_csr_w      = fetch1_instr_csr_i;
wire       issue_b_invalid_w  = fetch1_instr_invalid_i;

//-------------------------------------------------------------
// Pipe0 - Status tracking --流水线状态跟踪核管理模块
//------------------------------------------------------------- 
// 1、流水线状态跟踪：管理指令在流水线各阶段的状态
// 2、数据旁路控制：提供旁路选择信号
// 3、异常处理：跟踪和传播异常信息
// 4、流水线互锁：检测并处理流水线停顿
// 5、分支处理：管理分支预测和恢复
    //   ┌─────────┐    ┌─────────┐
    //   │  Pipe0  │    │  Pipe1  │
    //   └────┬────┘    └────┬────┘
    //        │              │
    //   ┌────▼────┐    ┌────▼────┐
    //   │  E1阶段 │    │  E1阶段 │
    //   │  ALU结果│    │  ALU结果│
    //   └────┬────┘    └────┬────┘
    //        │              │
    //   ┌────▼────┐    ┌────▼────┐
    //   │  E2阶段 │    │  E2阶段 │
    //   │乘/加载结果│   │乘/加载结果│
    //   └────┬────┘    └────┬────┘
    //        │              │
    //   ┌────▼────┐    ┌────▼────┐
    //   │  WB阶段 │    │  WB阶段 │
    //   │写回寄存器│   │写回寄存器│
    //   └────┬────┘    └────┬────┘
    //        └──────────────┘
    //             │
    //   ┌─────────▼─────────┐
    //   │  旁路选择逻辑      │
    //   │ （发射阶段）       │
    //   └─────────┬─────────┘
    //             │
    //       ┌─────▼─────┐
    //       │ 执行单元   │
    //       └───────────┘

        //     发射阶段 (Issue)
        //       ↓
        // 执行阶段1 (E1) - ALU、分支计算
        //       ↓
        // 执行阶段2 (E2) - 乘/加载完成
        //       ↓
        // 写回阶段 (WB) - 寄存器更新

wire        pipe0_squash_e1_e2_w;
wire        pipe1_squash_e1_e2_w;

reg         opcode_a_issue_r;
reg         opcode_a_accept_r;
wire        pipe0_stall_raw_w;

wire        pipe0_load_e1_w;
wire        pipe0_store_e1_w;
wire        pipe0_mul_e1_w;
wire        pipe0_branch_e1_w;
wire [4:0]  pipe0_rd_e1_w;

wire [31:0] pipe0_pc_e1_w;
wire [31:0] pipe0_opcode_e1_w;
wire [31:0] pipe0_operand_ra_e1_w;
wire [31:0] pipe0_operand_rb_e1_w;

wire        pipe0_load_e2_w;
wire        pipe0_mul_e2_w;
wire [4:0]  pipe0_rd_e2_w;
wire [31:0] pipe0_result_e2_w;

wire        pipe0_valid_wb_w;
wire        pipe0_csr_wb_w;
wire [4:0]  pipe0_rd_wb_w;
wire [31:0] pipe0_result_wb_w;
wire [31:0] pipe0_pc_wb_w;
wire [31:0] pipe0_opc_wb_w;
wire [31:0] pipe0_ra_val_wb_w;
wire [31:0] pipe0_rb_val_wb_w;
wire [`EXCEPTION_W-1:0] pipe0_exception_wb_w;

wire [`EXCEPTION_W-1:0] issue_a_fault_w = opcode_a_fault_r[0] ? `EXCEPTION_FAULT_FETCH:
                                          opcode_a_fault_r[1] ? `EXCEPTION_PAGE_FAULT_INST: `EXCEPTION_W'b0;

    //  Pipe0 E1 ───┐        Pipe1 E1 ───┐
    //  Pipe0 E2 ───┤        Pipe1 E2 ───┤
    //  Pipe0 WB ───┤        Pipe1 WB ───┤
    //              │                   │
    //       ┌──────▼───────────────────▼──────┐
    //       │     旁路多路选择器              │
    //       └─────────────┬───────────────────┘
    //                     │
    //               发射阶段的指令

biriscv_pipe_ctrl
#( 
     .SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
)
u_pipe0_ctrl
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)    

    //input
    // Issue 指令发射控制
    ,.issue_valid_i(opcode_a_issue_r)   //发射请求
    ,.issue_accept_i(opcode_a_accept_r) //发射接受
    ,.issue_stall_i(stall_w)            //全局停顿
    // 指令类型信息
    ,.issue_lsu_i(issue_a_lsu_w)
    ,.issue_csr_i(issue_a_csr_w)
    ,.issue_div_i(issue_a_div_w)
    ,.issue_mul_i(issue_a_mul_w)
    ,.issue_branch_i(issue_a_branch_w)
    //寄存器信息
    ,.issue_rd_valid_i(issue_a_sb_alloc_w) //写寄存器索引
    ,.issue_rd_i(issue_a_rd_idx_w)         //目标寄存器索引
    //异常信息
    ,.issue_exception_i(issue_a_fault_w)

    //指令数据
    ,.issue_pc_i(opcode0_pc_o)                 //pc
    ,.issue_opcode_i(opcode0_opcode_o)         //指令编码
    ,.issue_operand_ra_i(opcode0_ra_operand_o) //操作数A
    ,.issue_operand_rb_i(opcode0_rb_operand_o) //操作数B
    //分支信息
    ,.issue_branch_taken_i(branch_d_exec0_request_i) //分支发生
    ,.issue_branch_target_i(branch_d_exec0_pc_i)     //分支目标
    ,.take_interrupt_i(take_interrupt_i)             //中断发生



    // Execution stage 1: ALU result  input 输入：E1阶段结果
    ,.alu_result_e1_i(writeback_exec0_value_i)          //ALU结果
    // Execution stage 1: CSR read result / early exceptions
    ,.csr_result_value_e1_i(csr_result_e1_value_i)      //CSR结果
    ,.csr_result_write_e1_i(csr_result_e1_write_i)      //CSR写使能
    ,.csr_result_wdata_e1_i(csr_result_e1_wdata_i)      //CSR写数据
    ,.csr_result_exception_e1_i(csr_result_e1_exception_i) //CSR异常

    // Execution stage 1   output  输出：E1阶段状态
    ,.load_e1_o(pipe0_load_e1_w)      //当前是load指令
    ,.store_e1_o(pipe0_store_e1_w)
    ,.mul_e1_o(pipe0_mul_e1_w)
    ,.branch_e1_o(pipe0_branch_e1_w)
    ,.rd_e1_o(pipe0_rd_e1_w)          //目标寄存器索引
    ,.pc_e1_o(pipe0_pc_e1_w)          //当前pc
    ,.opcode_e1_o(pipe0_opcode_e1_w)  //当前指令编码
    ,.operand_ra_e1_o(pipe0_operand_ra_e1_w) //操作数A
    ,.operand_rb_e1_o(pipe0_operand_rb_e1_w) //操作数B

    // Execution stage 2: Other results  input  E2阶段结果
    ,.mem_complete_i(writeback_mem_valid_i)         //内存操作完成
    ,.mem_result_e2_i(writeback_mem_value_i)        //内存操作结果
    ,.mem_exception_e2_i(writeback_mem_exception_i) //内存异常
    ,.mul_result_e2_i(writeback_mul_value_i)        //乘法结果

    // Execution stage 2  output  E2阶段状态
    ,.load_e2_o(pipe0_load_e2_w)     //E2阶段是加载指令
    ,.mul_e2_o(pipe0_mul_e2_w)
    ,.rd_e2_o(pipe0_rd_e2_w)         //目标寄存器索引
    ,.result_e2_o(pipe0_result_e2_w) //E2阶段结果

    //控制接口
    //流水线控制
    ,.stall_o(pipe0_stall_raw_w)            //产生的停顿信号   output
    ,.squash_e1_e2_o(pipe0_squash_e1_e2_w)  //刷新E1=E2阶段   output
    ,.squash_e1_e2_i(pipe1_squash_e1_e2_w)  //来自Pipe1的刷新  input
    ,.squash_wb_i(1'b0)                     //刷新WB阶段       input

    // Out of pipe: Divide Result
    //除法结果（外部完成）
    ,.div_complete_i(writeback_div_valid_i) //除法完成  input
    ,.div_result_i(writeback_div_value_i)   //除法结果  input

    // Commit 提交阶段状态   output
    ,.valid_wb_o(pipe0_valid_wb_w)
    ,.csr_wb_o(pipe0_csr_wb_w)
    ,.rd_wb_o(pipe0_rd_wb_w)
    ,.result_wb_o(pipe0_result_wb_w)
    ,.pc_wb_o(pipe0_pc_wb_w)
    ,.opcode_wb_o(pipe0_opc_wb_w)
    ,.operand_ra_wb_o(pipe0_ra_val_wb_w)
    ,.operand_rb_wb_o(pipe0_rb_val_wb_w)
    ,.exception_wb_o(pipe0_exception_wb_w)
    //CSR写回控制           output
    ,.csr_write_wb_o(csr_writeback_write_o)  //CSR写使能
    ,.csr_waddr_wb_o(csr_writeback_waddr_o)  //CSR地址
    ,.csr_wdata_wb_o(csr_writeback_wdata_o)  //CSR数据 
);

assign exec0_hold_o = stall_w;
assign mul_hold_o   = stall_w;

//-------------------------------------------------------------
// Pipe1 - Status tracking
//-------------------------------------------------------------
reg         opcode_b_issue_r;
reg         opcode_b_accept_r;
wire        pipe1_stall_raw_w;

wire        pipe1_load_e1_w;
wire        pipe1_store_e1_w;
wire        pipe1_mul_e1_w;
wire        pipe1_branch_e1_w;
wire [4:0]  pipe1_rd_e1_w;

wire [31:0] pipe1_pc_e1_w;
wire [31:0] pipe1_opcode_e1_w;
wire [31:0] pipe1_operand_ra_e1_w;
wire [31:0] pipe1_operand_rb_e1_w;

wire        pipe1_load_e2_w;
wire        pipe1_mul_e2_w;
wire [4:0]  pipe1_rd_e2_w;
wire [31:0] pipe1_result_e2_w;

wire        pipe1_valid_wb_w;
wire [4:0]  pipe1_rd_wb_w;
wire [31:0] pipe1_result_wb_w;
wire [31:0] pipe1_pc_wb_w;
wire [31:0] pipe1_opc_wb_w;
wire [31:0] pipe1_ra_val_wb_w;
wire [31:0] pipe1_rb_val_wb_w;
wire [`EXCEPTION_W-1:0] pipe1_exception_wb_w;

wire [`EXCEPTION_W-1:0] issue_b_fault_w = opcode_b_fault_r[0] ? `EXCEPTION_FAULT_FETCH:
                                          opcode_b_fault_r[1] ? `EXCEPTION_PAGE_FAULT_INST: `EXCEPTION_W'b0;

biriscv_pipe_ctrl //流水线控制器，管理指令在流水线中的流动、异常处理和结果转发
#( 
     .SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
)
u_pipe1_ctrl
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    // Issue
    ,.issue_valid_i(opcode_b_issue_r)
    ,.issue_accept_i(opcode_b_accept_r)
    ,.issue_stall_i(stall_w)
    ,.issue_lsu_i(issue_b_lsu_w)
    ,.issue_csr_i(1'b0)
    ,.issue_div_i(1'b0)
    ,.issue_mul_i(issue_b_mul_w)
    ,.issue_branch_i(issue_b_branch_w)
    ,.issue_rd_valid_i(issue_b_sb_alloc_w)
    ,.issue_rd_i(issue_b_rd_idx_w)
    ,.issue_exception_i(issue_b_fault_w)
    ,.issue_pc_i(opcode1_pc_o)
    ,.issue_opcode_i(opcode1_opcode_o)
    ,.issue_operand_ra_i(opcode1_ra_operand_o)
    ,.issue_operand_rb_i(opcode1_rb_operand_o)
    ,.issue_branch_taken_i(branch_d_exec1_request_i)
    ,.issue_branch_target_i(branch_d_exec1_pc_i)
    ,.take_interrupt_i(take_interrupt_i)

    // Execution stage 1: ALU, CSR result
    ,.alu_result_e1_i(writeback_exec1_value_i)
    ,.csr_result_value_e1_i(csr_result_e1_value_i)
    ,.csr_result_write_e1_i(csr_result_e1_write_i)
    ,.csr_result_wdata_e1_i(csr_result_e1_wdata_i)
    ,.csr_result_exception_e1_i(csr_result_e1_exception_i)

    // Execution stage 1
    ,.load_e1_o(pipe1_load_e1_w)
    ,.store_e1_o(pipe1_store_e1_w)
    ,.mul_e1_o(pipe1_mul_e1_w)
    ,.branch_e1_o(pipe1_branch_e1_w)
    ,.rd_e1_o(pipe1_rd_e1_w)
    ,.pc_e1_o(pipe1_pc_e1_w)
    ,.opcode_e1_o(pipe1_opcode_e1_w)
    ,.operand_ra_e1_o(pipe1_operand_ra_e1_w)
    ,.operand_rb_e1_o(pipe1_operand_rb_e1_w)

    // Execution stage 2: Other results
    ,.mem_complete_i(writeback_mem_valid_i)
    ,.mem_result_e2_i(writeback_mem_value_i)
    ,.mem_exception_e2_i(writeback_mem_exception_i)
    ,.mul_result_e2_i(writeback_mul_value_i)

    // Execution stage 2
    ,.load_e2_o(pipe1_load_e2_w)
    ,.mul_e2_o(pipe1_mul_e2_w)
    ,.rd_e2_o(pipe1_rd_e2_w)
    ,.result_e2_o(pipe1_result_e2_w)

    ,.stall_o(pipe1_stall_raw_w)
    ,.squash_e1_e2_o(pipe1_squash_e1_e2_w)
    ,.squash_e1_e2_i(pipe0_squash_e1_e2_w)
    ,.squash_wb_i(pipe0_squash_e1_e2_w)

    // Out of pipe: Divide Result
    ,.div_complete_i(writeback_div_valid_i)
    ,.div_result_i(writeback_div_value_i)

    // Commit
    ,.valid_wb_o(pipe1_valid_wb_w)
    ,.csr_wb_o()
    ,.rd_wb_o(pipe1_rd_wb_w)
    ,.result_wb_o(pipe1_result_wb_w)
    ,.pc_wb_o(pipe1_pc_wb_w)
    ,.opcode_wb_o(pipe1_opc_wb_w)
    ,.operand_ra_wb_o(pipe1_ra_val_wb_w)
    ,.operand_rb_wb_o(pipe1_rb_val_wb_w)
    ,.exception_wb_o(pipe1_exception_wb_w)
    ,.csr_write_wb_o()
    ,.csr_waddr_wb_o()
    ,.csr_wdata_wb_o()
);

assign exec1_hold_o = stall_w;

assign csr_writeback_exception_o      = pipe0_exception_wb_w | pipe1_exception_wb_w;
assign csr_writeback_exception_pc_o   = (|pipe0_exception_wb_w) ? pipe0_pc_wb_w     : pipe1_pc_wb_w;
assign csr_writeback_exception_addr_o = (|pipe0_exception_wb_w) ? pipe0_result_wb_w : pipe1_result_wb_w;

//-------------------------------------------------------------
// Branch predictor info
//-------------------------------------------------------------
// This info is used to learn future prediction, and to correct 
// BTB, BHT, GShare, RAS indexes on mispredictions.
assign branch_info_request_o      = mispredicted_r;
assign branch_info_is_taken_o     = (pipe1_branch_e1_w & branch_exec1_is_taken_i)     | (pipe0_branch_e1_w & branch_exec0_is_taken_i);
assign branch_info_is_not_taken_o = (pipe1_branch_e1_w & branch_exec1_is_not_taken_i) | (pipe0_branch_e1_w & branch_exec0_is_not_taken_i);
assign branch_info_is_call_o      = (pipe1_branch_e1_w & branch_exec1_is_call_i)      | (pipe0_branch_e1_w & branch_exec0_is_call_i);
assign branch_info_is_ret_o       = (pipe1_branch_e1_w & branch_exec1_is_ret_i)       | (pipe0_branch_e1_w & branch_exec0_is_ret_i);
assign branch_info_is_jmp_o       = (pipe1_branch_e1_w & branch_exec1_is_jmp_i)       | (pipe0_branch_e1_w & branch_exec0_is_jmp_i);
assign branch_info_source_o       = (pipe1_branch_e1_w & branch_exec1_request_i)      ? branch_exec1_source_i : branch_exec0_source_i;
assign branch_info_pc_o           = (pipe1_branch_e1_w & branch_exec1_request_i)      ? branch_exec1_pc_i     : branch_exec0_pc_i;

//-------------------------------------------------------------
// Blocking events (division, CSR unit access) 长延迟操作管理
//-------------------------------------------------------------
reg div_pending_q;
reg csr_pending_q;

// Division operations take 2 - 34 cycles and stall
// the pipeline (complete out-of-pipe) until completed.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    div_pending_q <= 1'b0;
else if (pipe0_squash_e1_e2_w || pipe1_squash_e1_e2_w) //流水线刷新
    div_pending_q <= 1'b0;
else if (div_opcode_valid_o && issue_a_div_w)  //除法指令需要等待
    div_pending_q <= 1'b1;
else if (writeback_div_valid_i)    //除法完成
    div_pending_q <= 1'b0;

// CSR operations are infrequent - avoid any complications of pipelining them.
// These only take a 2-3 cycles anyway and may result in a pipe flush (e.g. ecall, ebreak..).
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    csr_pending_q <= 1'b0;
else if (pipe0_squash_e1_e2_w || pipe1_squash_e1_e2_w)
    csr_pending_q <= 1'b0;
else if (csr_opcode_valid_o && issue_a_csr_w)  //csr指令需要等待
    csr_pending_q <= 1'b1;
else if (pipe0_csr_wb_w)
    csr_pending_q <= 1'b0;

assign squash_w = pipe0_squash_e1_e2_w || pipe1_squash_e1_e2_w;

//-------------------------------------------------------------
// Issue / scheduling logic  ---指令调度逻辑
//-------------------------------------------------------------
reg [31:0] scoreboard_r;   //计数板，32位向量，每一个bit对应一个寄存器，跟踪寄存器依赖状态，防止数据冒险
//scoreboard_r为1表示该寄存器的值正在计算，还未被写回；反之，则准备就绪
reg        pipe1_mux_lsu_r;  // LSU指令来自哪个slot
reg        pipe1_mux_mul_r;  // MUL指令来自哪个slot

// Check instructions can be issued in the second execution unit
wire pipe1_ok_w      = issue_b_exec_w | issue_b_branch_w | issue_b_lsu_w | issue_b_mul_w;

// Is this combination of instructions possible to execute concurrently.
// This excludes result dependencies which may also block secondary execution.
//双发射条件检查
// 指令组合规则：
// 指令A（ALU/LSU/MUL） + 指令B（ALU）
// 指令A（ALU/LSU/MUL） + 指令B（分支）
// 指令A（ALU/MUL） + 指令B（LSU）
// 指令A（ALU/LSU） + 指令B（MUL）
wire dual_issue_ok_w =   enable_dual_issue_w &&  // Second pipe switched on
                         pipe1_ok_w &&           // Instruction 2 is possible on second exec unit
                        (((issue_a_exec_w | issue_a_lsu_w | issue_a_mul_w) && issue_b_exec_w)   ||
                         ((issue_a_exec_w | issue_a_lsu_w | issue_a_mul_w) && issue_b_branch_w) ||
                         ((issue_a_exec_w | issue_a_mul_w) && issue_b_lsu_w)                    ||
                         ((issue_a_exec_w | issue_a_lsu_w) && issue_b_mul_w)
                         ) && ~take_interrupt_i;

always @ *
begin
    opcode_a_issue_r     = 1'b0;
    opcode_b_issue_r     = 1'b0;
    opcode_a_accept_r    = 1'b0;
    opcode_b_accept_r    = 1'b0;
    scoreboard_r         = 32'b0;  //计分板，跟踪寄存器占用状态、防止数据冒险、支持旁路优化
    pipe1_mux_lsu_r      = 1'b0;
    pipe1_mux_mul_r      = 1'b0;

    // Execution units with >= 2 cycle latency
    if (SUPPORT_LOAD_BYPASS == 0)
    begin
        if (pipe0_load_e2_w)
            scoreboard_r[pipe0_rd_e2_w] = 1'b1;
        if (pipe1_load_e2_w)
            scoreboard_r[pipe1_rd_e2_w] = 1'b1;
    end
    if (SUPPORT_MUL_BYPASS == 0)
    begin
        if (pipe0_mul_e2_w)
            scoreboard_r[pipe0_rd_e2_w] = 1'b1;
        if (pipe1_mul_e2_w)
            scoreboard_r[pipe1_rd_e2_w] = 1'b1;
    end

    // Execution units with >= 1 cycle latency (loads / multiply)
    if (pipe0_load_e1_w || pipe0_mul_e1_w)
        scoreboard_r[pipe0_rd_e1_w] = 1'b1;
    if (pipe1_load_e1_w || pipe1_mul_e1_w)
        scoreboard_r[pipe1_rd_e1_w] = 1'b1;

    // Do not start multiply, division or CSR operation in the cycle after a load (leaving only ALU operations and branches)
    if ((pipe0_load_e1_w || pipe0_store_e1_w || pipe1_load_e1_w || pipe1_store_e1_w ) && (issue_a_mul_w || issue_a_div_w || issue_a_csr_w))
        scoreboard_r = 32'hFFFFFFFF;

    // Stall - no issues...
    if (lsu_stall_i || stall_w || div_pending_q || csr_pending_q)
        ;
    // Primary slot (lsu, branch, alu, mul, div, csr)
    else if (opcode_a_valid_r &&
        !(scoreboard_r[issue_a_ra_idx_w] || 
          scoreboard_r[issue_a_rb_idx_w] ||
          scoreboard_r[issue_a_rd_idx_w]))
    begin
        opcode_a_issue_r  = 1'b1;
        opcode_a_accept_r = 1'b1;

        if (opcode_a_accept_r && issue_a_sb_alloc_w && (|issue_a_rd_idx_w))
            scoreboard_r[issue_a_rd_idx_w] = 1'b1;
    end

    // Stall - no issues...
    if (lsu_stall_i || stall_w || div_pending_q || csr_pending_q)
        ;
    // Secondary Slot (lsu, branch, alu, mul)
    else if (dual_issue_ok_w && opcode_b_valid_r && opcode_a_accept_r &&
        !(scoreboard_r[issue_b_ra_idx_w] || 
          scoreboard_r[issue_b_rb_idx_w] ||
          scoreboard_r[issue_b_rd_idx_w]))
    begin
        opcode_b_issue_r  = 1'b1;
        opcode_b_accept_r = 1'b1;
        pipe1_mux_lsu_r   = issue_b_lsu_w;
        pipe1_mux_mul_r   = issue_b_mul_w;

        if (opcode_b_accept_r && issue_b_sb_alloc_w && (|issue_b_rd_idx_w))
            scoreboard_r[issue_b_rd_idx_w] = 1'b1;
    end    
end

assign lsu_opcode_valid_o   = (pipe1_mux_lsu_r ? opcode_b_issue_r : opcode_a_issue_r) & ~take_interrupt_i;
assign exec0_opcode_valid_o = opcode_a_issue_r;
assign mul_opcode_valid_o   = enable_muldiv_w & (pipe1_mux_mul_r ? opcode_b_issue_r : opcode_a_issue_r);
assign div_opcode_valid_o   = enable_muldiv_w & (opcode_a_issue_r);
assign interrupt_inhibit_o  = csr_pending_q || issue_a_csr_w;

assign exec1_opcode_valid_o = opcode_b_issue_r;

assign dual_issue_w         = opcode_b_issue_r & opcode_b_accept_r & ~take_interrupt_i;
assign single_issue_w       = (opcode_a_issue_r & opcode_a_accept_r) & ~dual_issue_w & ~take_interrupt_i;

assign fetch0_accept_o      = ((slot0_valid_r & opcode_a_accept_r) | slot1_valid_r) & ~take_interrupt_i;
assign fetch1_accept_o      = ((slot1_valid_r & opcode_a_accept_r) | (opcode_b_accept_r)) & ~take_interrupt_i;

assign stall_w              = pipe0_stall_raw_w | pipe1_stall_raw_w;

//-------------------------------------------------------------
// Register File
//------------------------------------------------------------- 
wire [31:0] issue_a_ra_value_w;
wire [31:0] issue_a_rb_value_w;
wire [31:0] issue_b_ra_value_w;
wire [31:0] issue_b_rb_value_w;

// Register file: 2W4R
biriscv_regfile
#(
     .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX)
    ,.SUPPORT_DUAL_ISSUE(SUPPORT_DUAL_ISSUE)
)
u_regfile
(
    .clk_i(clk_i),
    .rst_i(rst_i),

    // Write ports
    .rd0_i(pipe0_rd_wb_w),
    .rd0_value_i(pipe0_result_wb_w),
    .rd1_i(pipe1_rd_wb_w),
    .rd1_value_i(pipe1_result_wb_w),

    // Read ports
    .ra0_i(issue_a_ra_idx_w),
    .rb0_i(issue_a_rb_idx_w),
    .ra0_value_o(issue_a_ra_value_w),
    .rb0_value_o(issue_a_rb_value_w),

    .ra1_i(issue_b_ra_idx_w),
    .rb1_i(issue_b_rb_idx_w),
    .ra1_value_o(issue_b_ra_value_w),
    .rb1_value_o(issue_b_rb_value_w)    
);

//-------------------------------------------------------------
// Issue Slot 0
//------------------------------------------------------------- 
// 双发射限制：
// CSR指令只能在Pipe0执行
// 除法指令只能在Pipe0执行
// 存储指令有特殊限制（避免访存冲突）
assign opcode0_opcode_o = opcode_a_r;
assign opcode0_pc_o     = opcode_a_pc_r;
assign opcode0_rd_idx_o = issue_a_rd_idx_w;
assign opcode0_ra_idx_o = issue_a_ra_idx_w;
assign opcode0_rb_idx_o = issue_a_rb_idx_w;
assign opcode0_invalid_o= 1'b0; 

reg [31:0] issue_a_ra_value_r;
reg [31:0] issue_a_rb_value_r;

always @ *
begin
    // NOTE: Newest version of operand takes priority
    issue_a_ra_value_r = issue_a_ra_value_w;
    issue_a_rb_value_r = issue_a_rb_value_w;

    // Bypass - WB
    if (pipe0_rd_wb_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe0_result_wb_w;
    if (pipe0_rd_wb_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe0_result_wb_w;

    if (pipe1_rd_wb_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe1_result_wb_w;
    if (pipe1_rd_wb_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe1_result_wb_w;

    // Bypass - E2
    if (pipe0_rd_e2_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe0_result_e2_w;
    if (pipe0_rd_e2_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe0_result_e2_w;

    if (pipe1_rd_e2_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe1_result_e2_w;
    if (pipe1_rd_e2_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe1_result_e2_w;

    // Bypass - E1
    if (pipe0_rd_e1_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = writeback_exec0_value_i;
    if (pipe0_rd_e1_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = writeback_exec0_value_i;

    if (pipe1_rd_e1_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = writeback_exec1_value_i;
    if (pipe1_rd_e1_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = writeback_exec1_value_i;

    // Reg 0 source
    if (issue_a_ra_idx_w == 5'b0)
        issue_a_ra_value_r = 32'b0;
    if (issue_a_rb_idx_w == 5'b0)
        issue_a_rb_value_r = 32'b0;
end

assign opcode0_ra_operand_o = issue_a_ra_value_r;
assign opcode0_rb_operand_o = issue_a_rb_value_r;

//-------------------------------------------------------------
// Issue Slot 1
//------------------------------------------------------------- 
assign opcode1_opcode_o = opcode_b_r;
assign opcode1_pc_o     = opcode_b_pc_r;
assign opcode1_rd_idx_o = issue_b_rd_idx_w;
assign opcode1_ra_idx_o = issue_b_ra_idx_w;
assign opcode1_rb_idx_o = issue_b_rb_idx_w;
assign opcode1_invalid_o= 1'b0;

reg [31:0] issue_b_ra_value_r;
reg [31:0] issue_b_rb_value_r;

always @ *
begin
    // NOTE: Newest version of operand takes priority
    issue_b_ra_value_r = issue_b_ra_value_w;
    issue_b_rb_value_r = issue_b_rb_value_w;

    // Bypass - WB
    if (pipe0_rd_wb_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe0_result_wb_w;
    if (pipe0_rd_wb_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe0_result_wb_w;

    if (pipe1_rd_wb_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe1_result_wb_w;
    if (pipe1_rd_wb_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe1_result_wb_w;

    // Bypass - E2
    if (pipe0_rd_e2_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe0_result_e2_w;
    if (pipe0_rd_e2_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe0_result_e2_w;

    if (pipe1_rd_e2_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe1_result_e2_w;
    if (pipe1_rd_e2_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe1_result_e2_w;

    // Bypass - E1
    if (pipe0_rd_e1_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = writeback_exec0_value_i;
    if (pipe0_rd_e1_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = writeback_exec0_value_i;

    if (pipe1_rd_e1_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = writeback_exec1_value_i;
    if (pipe1_rd_e1_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = writeback_exec1_value_i;

    // Reg 0 source
    if (issue_b_ra_idx_w == 5'b0)
        issue_b_ra_value_r = 32'b0;
    if (issue_b_rb_idx_w == 5'b0)
        issue_b_rb_value_r = 32'b0;
end

assign opcode1_ra_operand_o = issue_b_ra_value_r;
assign opcode1_rb_operand_o = issue_b_rb_value_r;

//-------------------------------------------------------------
// Load store unit
//-------------------------------------------------------------
assign lsu_opcode_opcode_o      = pipe1_mux_lsu_r ? opcode1_opcode_o     : opcode0_opcode_o;
assign lsu_opcode_pc_o          = pipe1_mux_lsu_r ? opcode1_pc_o         : opcode0_pc_o;
assign lsu_opcode_rd_idx_o      = pipe1_mux_lsu_r ? opcode1_rd_idx_o     : opcode0_rd_idx_o;
assign lsu_opcode_ra_idx_o      = pipe1_mux_lsu_r ? opcode1_ra_idx_o     : opcode0_ra_idx_o;
assign lsu_opcode_rb_idx_o      = pipe1_mux_lsu_r ? opcode1_rb_idx_o     : opcode0_rb_idx_o;
assign lsu_opcode_ra_operand_o  = pipe1_mux_lsu_r ? opcode1_ra_operand_o : opcode0_ra_operand_o;
assign lsu_opcode_rb_operand_o  = pipe1_mux_lsu_r ? opcode1_rb_operand_o : opcode0_rb_operand_o;
assign lsu_opcode_invalid_o     = 1'b0;

//-------------------------------------------------------------
// Multiply
//-------------------------------------------------------------
assign mul_opcode_opcode_o      = pipe1_mux_mul_r ? opcode1_opcode_o     : opcode0_opcode_o;
assign mul_opcode_pc_o          = pipe1_mux_mul_r ? opcode1_pc_o         : opcode0_pc_o;
assign mul_opcode_rd_idx_o      = pipe1_mux_mul_r ? opcode1_rd_idx_o     : opcode0_rd_idx_o;
assign mul_opcode_ra_idx_o      = pipe1_mux_mul_r ? opcode1_ra_idx_o     : opcode0_ra_idx_o;
assign mul_opcode_rb_idx_o      = pipe1_mux_mul_r ? opcode1_rb_idx_o     : opcode0_rb_idx_o;
assign mul_opcode_ra_operand_o  = pipe1_mux_mul_r ? opcode1_ra_operand_o : opcode0_ra_operand_o;
assign mul_opcode_rb_operand_o  = pipe1_mux_mul_r ? opcode1_rb_operand_o : opcode0_rb_operand_o;
assign mul_opcode_invalid_o     = 1'b0;

//-------------------------------------------------------------
// CSR unit
//-------------------------------------------------------------
assign csr_opcode_valid_o       = opcode_a_issue_r & ~take_interrupt_i;
assign csr_opcode_opcode_o      = opcode0_opcode_o;
assign csr_opcode_pc_o          = opcode0_pc_o;
assign csr_opcode_rd_idx_o      = opcode0_rd_idx_o;
assign csr_opcode_ra_idx_o      = opcode0_ra_idx_o;
assign csr_opcode_rb_idx_o      = opcode0_rb_idx_o;
assign csr_opcode_ra_operand_o  = opcode0_ra_operand_o;
assign csr_opcode_rb_operand_o  = opcode0_rb_operand_o;
assign csr_opcode_invalid_o     = opcode_a_issue_r && issue_a_invalid_w;

//-------------------------------------------------------------
// Checker Interface
//-------------------------------------------------------------
`ifdef verilator
biriscv_trace_sim
u_pipe0_dec0_verif
(
     .valid_i(pipe0_valid_wb_w)
    ,.pc_i(pipe0_pc_wb_w)
    ,.opcode_i(pipe0_opc_wb_w)
);

wire [4:0] v_pipe0_rs1_w = pipe0_opc_wb_w[19:15];
wire [4:0] v_pipe0_rs2_w = pipe0_opc_wb_w[24:20];

function [0:0] complete_valid0; /*verilator public*/
begin
    complete_valid0 = pipe0_valid_wb_w;
end
endfunction
function [31:0] complete_pc0; /*verilator public*/
begin
    complete_pc0 = pipe0_pc_wb_w;
end
endfunction
function [31:0] complete_opcode0; /*verilator public*/
begin
    complete_opcode0 = pipe0_opc_wb_w;
end
endfunction
function [4:0] complete_ra0; /*verilator public*/
begin
    complete_ra0 = v_pipe0_rs1_w;
end
endfunction
function [4:0] complete_rb0; /*verilator public*/
begin
    complete_rb0 = v_pipe0_rs2_w;
end
endfunction
function [4:0] complete_rd0; /*verilator public*/
begin
    complete_rd0 = pipe0_rd_wb_w;
end
endfunction
function [31:0] complete_ra_val0; /*verilator public*/
begin
    complete_ra_val0 = pipe0_ra_val_wb_w;
end
endfunction
function [31:0] complete_rb_val0; /*verilator public*/
begin
    complete_rb_val0 = pipe0_rb_val_wb_w;
end
endfunction
function [31:0] complete_rd_val0; /*verilator public*/
begin
    if (|pipe0_rd_wb_w)
        complete_rd_val0 = pipe0_result_wb_w;
    else
        complete_rd_val0 = 32'b0;
end
endfunction

biriscv_trace_sim
u_pipe0_dec1_verif
(
     .valid_i(pipe1_valid_wb_w)
    ,.pc_i(pipe1_pc_wb_w)
    ,.opcode_i(pipe1_opc_wb_w)
);

wire [4:0] v_pipe1_rs1_w = pipe1_opc_wb_w[19:15];
wire [4:0] v_pipe1_rs2_w = pipe1_opc_wb_w[24:20];

function [0:0] complete_valid1; /*verilator public*/
begin
    complete_valid1 = pipe1_valid_wb_w;
end
endfunction
function [31:0] complete_pc1; /*verilator public*/
begin
    complete_pc1 = pipe1_pc_wb_w;
end
endfunction
function [31:0] complete_opcode1; /*verilator public*/
begin
    complete_opcode1 = pipe1_opc_wb_w;
end
endfunction
function [4:0] complete_ra1; /*verilator public*/
begin
    complete_ra1 = v_pipe1_rs1_w;
end
endfunction
function [4:0] complete_rb1; /*verilator public*/
begin
    complete_rb1 = v_pipe1_rs2_w;
end
endfunction
function [4:0] complete_rd1; /*verilator public*/
begin
    complete_rd1 = pipe1_rd_wb_w;
end
endfunction
function [31:0] complete_ra_val1; /*verilator public*/
begin
    complete_ra_val1 = pipe1_ra_val_wb_w;
end
endfunction
function [31:0] complete_rb_val1; /*verilator public*/
begin
    complete_rb_val1 = pipe1_rb_val_wb_w;
end
endfunction
function [31:0] complete_rd_val1; /*verilator public*/
begin
    if (|pipe1_rd_wb_w)
        complete_rd_val1 = pipe1_result_wb_w;
    else
        complete_rd_val1 = 32'b0;
end
endfunction
function [5:0] complete_exception; /*verilator public*/
begin
    complete_exception = pipe0_exception_wb_w | pipe1_exception_wb_w;
end
endfunction
`endif


endmodule
