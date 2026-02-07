module biriscv_npc //解决控制冒险（分支冒险）
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_BRANCH_PREDICTION = 1
    ,parameter NUM_BTB_ENTRIES  = 256  //BTB深度16
    ,parameter NUM_BTB_ENTRIES_W = 8  //BTB宽度4
    ,parameter NUM_BHT_ENTRIES  = 512 //BHT深度256
    ,parameter NUM_BHT_ENTRIES_W = 9  //BHT宽度8
    ,parameter RAS_ENABLE       = 1
    ,parameter GSHARE_ENABLE    = 0
    ,parameter BHT_ENABLE       = 1
    ,parameter NUM_RAS_ENTRIES  = 8
    ,parameter NUM_RAS_ENTRIES_W = 3
    ,parameter RESET_VECTOR     = 32'h80000000
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           invalidate_i //一直为0
    //来自issue单元的分支（错误）请求
    ,input           branch_request_i
    ,input           branch_is_taken_i
    ,input           branch_is_not_taken_i
    ,input  [ 31:0]  branch_source_i   //正在执行的分支指令的原始地址
    ,input           branch_is_call_i
    ,input           branch_is_ret_i
    ,input           branch_is_jmp_i
    ,input  [ 31:0]  branch_pc_i       //分支指令的目标地址
    
    //来自npcg单元
    ,input  [ 31:0]  pc_f_i          //正要从缓存取出指令的pc地址
    ,input           pc_accept_i     //流控信号，用于只是pc是否可以被更新/防止在流水线暂停时，还在进行刷新和预测，一直为1
    //从issue拉过来统计预测错误的信息
    ,input  [31:0]   mispredicted_all_r
    ,input  [31:0]   mispredicted_is_call_r
    ,input  [31:0]   mispredicted_is_ret_r
    ,input  [31:0]   mispredicted_is_jmp_r
    ,input  [31:0]   mispredicted_is_other_r

    //传递给npcg的预测信息
    ,output  [ 31:0]  next_pc_f_o     //预测的下一条指令地址
    ,output  [  1:0]  next_taken_f_o  //taken标记位
);


reg [31:0] pc_f_i_r;
reg pc_accept_i_r;

reg reg_branch_request_r;

always @(posedge clk_i or posedge rst_i) begin //时序隔离，接收来自npcg的信号，不马上进行组合逻辑，而是延一个周期，避免组合逻辑环
    pc_f_i_r <= pc_accept_i ? pc_f_i : pc_f_i_r; //pc_accept_i为1时，更新；
    pc_accept_i_r <= pc_accept_i ? pc_accept_i : pc_accept_i_r;
    reg_branch_request_r <= branch_request_i;
end

reg [31:0] mispredicted_is_jmp;
reg [31:0] mispredicted_is_ret;
reg [31:0] mispredicted_is_call;
reg [31:0] mispredicted_is_other;
reg [31:0] mispredicted_all;

always @(posedge clk_i or posedge rst_i) begin
    mispredicted_all      <= mispredicted_all_r;
    mispredicted_is_call  <= mispredicted_is_call_r;
    mispredicted_is_ret   <= mispredicted_is_ret_r;
    mispredicted_is_jmp   <= mispredicted_is_jmp_r;
    mispredicted_is_other <= mispredicted_is_other_r;
end


localparam RAS_INVALID = 32'h00000001;


//-----------------------------------------------------------------
// Branch prediction (BTB, BHT, RAS)
//-----------------------------------------------------------------
generate
if (SUPPORT_BRANCH_PREDICTION)
begin: BRANCH_PREDICTION

wire        pred_taken_w;
wire        pred_ntaken_w;

// Info from BTB
wire        btb_valid_w;
wire        btb_upper_w;
wire [31:0] btb_next_pc_w;
wire        btb_is_call_w;
wire        btb_is_ret_w;





//-----------------------------------------------------------------
// Return Address Stack (actual)//真实ras，执行阶段确认后更新，100%准确；来自branch_source_i实际pc；记录实际执行的调用返回关系
//-----------------------------------------------------------------
reg [NUM_RAS_ENTRIES_W-1:0] ras_index_real_q; //真实的RAS只维护栈指针，不存储具体地址
reg [NUM_RAS_ENTRIES_W-1:0] ras_index_real_r;

always @ *
begin
    ras_index_real_r = ras_index_real_q;

    if (branch_request_i & branch_is_call_i)
        ras_index_real_r = ras_index_real_q + 1;  //压栈
    else if (branch_request_i & branch_is_ret_i)
        ras_index_real_r = ras_index_real_q - 1;  //出栈
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    ras_index_real_q <= {NUM_RAS_ENTRIES_W{1'b0}};
else
    ras_index_real_q <= ras_index_real_r;

//-----------------------------------------------------------------
// Return Address Stack (speculative) //预测RAS，取指令阶段预测时更新，；来自pc_f_i预测pc；记录预测的调用返回关系
//-----------------------------------------------------------------
reg [31:0] ras_stack_q[NUM_RAS_ENTRIES-1:0]; //栈存储数组，存储的是分支指令地址的下一条地址
reg [NUM_RAS_ENTRIES_W-1:0] ras_index_q;     //栈顶指针

reg [NUM_RAS_ENTRIES_W-1:0] ras_index_r;

wire [31:0] ras_pc_pred_w   = ras_stack_q[ras_index_q]; //从栈顶取出的预测返回地址
wire        ras_call_pred_w = RAS_ENABLE & (btb_valid_w & btb_is_call_w) & ~ras_pc_pred_w[0]; //预测是call指令
wire        ras_ret_pred_w  = RAS_ENABLE & (btb_valid_w & btb_is_ret_w) & ~ras_pc_pred_w[0];  //预测是ret指令
//栈指针更新逻辑
always @ *
begin
    ras_index_r = ras_index_q;

    // Mispredict - go from confirmed call stack index
    // 如果这是一个 call 指令，首先把 ras 的指针+1
    // 接着往 ras_stack_q 中存放 branch_source_i +4 这条地址。
    // 下一次预测的时候，如果发现是一个 ret 指令，会 ras_index_q -1
    // 然后返回 wire [31:0] ras_pc_pred_w   = ras_stack_q[ras_index_q];
    // 这就完成了预测。
    if (branch_request_i & branch_is_call_i)  //预测错误，则从真实RAS恢复（执行阶段确认）
        ras_index_r = ras_index_real_q + 1;
    else if (branch_request_i & branch_is_ret_i)
        ras_index_r = ras_index_real_q - 1;
    // Speculative call / returns   预测正确，继续预测（取指阶段确认）
    else if (ras_call_pred_w & pc_accept_i_r)
        ras_index_r = ras_index_q + 1;
    else if (ras_ret_pred_w & pc_accept_i_r)
        ras_index_r = ras_index_q - 1;
end

integer i3;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    for (i3 = 0; i3 < NUM_RAS_ENTRIES; i3 = i3 + 1)
    begin
        ras_stack_q[i3] <= RAS_INVALID;
    end

    ras_index_q <= {NUM_RAS_ENTRIES_W{1'b0}};
end
// On a call push return address onto RAS stack (current PC + 4)
else if (branch_request_i & branch_is_call_i) //真实的call指令执行
begin
    ras_stack_q[ras_index_r] <= branch_source_i + 32'd4; //把调用函数的下一条指令地址压栈，便于函数返回时调取
    ras_index_q              <= ras_index_r; //栈指针更新
end
// On a call push return address onto RAS stack (current PC + 4)
else if (ras_call_pred_w & pc_accept_i_r)
begin
    ras_stack_q[ras_index_r] <= (btb_upper_w ? (pc_f_i_r | 32'd4) : pc_f_i_r) + 32'd4;
    ras_index_q              <= ras_index_r; //栈指针更新
end
// Return - pop item from stack
else if ((ras_ret_pred_w & pc_accept_i_r) || (branch_request_i & branch_is_ret_i)) //ret指令
begin
    ras_index_q              <= ras_index_r;
end






// TODO：当前是两位饱和计数器组-使用的是全局历史的预测方式

//-----------------------------------------------------------------
// Global history register (actual history)  //BHT的真实索引
//-----------------------------------------------------------------
reg [NUM_BHT_ENTRIES_W-1:0] global_history_real_q; //存储跳转历史情况

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    global_history_real_q <= {NUM_BHT_ENTRIES_W{1'b0}};
else if (branch_is_taken_i || branch_is_not_taken_i)  //只有分支指令的时候才会更新
    global_history_real_q <= {global_history_real_q[NUM_BHT_ENTRIES_W-2:0], branch_is_taken_i};

//-----------------------------------------------------------------
// Global history register (speculative) //更新BHT的索引
//-----------------------------------------------------------------
reg [NUM_BHT_ENTRIES_W-1:0] global_history_q; //存储跳转历史情况

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    global_history_q <= {NUM_BHT_ENTRIES_W{1'b0}};
// Mispredict - revert to actual branch history to flush out speculative errors
else if (branch_request_i) //预测错误，恢复真实历史
    global_history_q <= {global_history_real_q[NUM_BHT_ENTRIES_W-2:0], branch_is_taken_i};
// Predicted branch
else if (pred_taken_w || pred_ntaken_w) //正常预测更新
    global_history_q <= {global_history_q[NUM_BHT_ENTRIES_W-2:0], pred_taken_w};

//写BHT必须基于100%准确的历史，否则会污染BHT（训练要使用真实历史）  //gshare通过异或操作将pc地址和全局分支历史混合，生成BHT的索引
wire [NUM_BHT_ENTRIES_W-1:0] gshare_wr_entry_w = (branch_request_i ? global_history_real_q : global_history_q) ^ branch_source_i[2+NUM_BHT_ENTRIES_W-1:2];
//读BHT使用推测历史（预测）
wire [NUM_BHT_ENTRIES_W-1:0] gshare_rd_entry_w = global_history_q ^ {pc_f_i_r[3+NUM_BHT_ENTRIES_W-2:3],btb_upper_w};

//-----------------------------------------------------------------
// Branch prediction bits  //更新BHT的饱和计数器
//-----------------------------------------------------------------
reg [1:0]                    bht_sat_q[NUM_BHT_ENTRIES-1:0];

wire [NUM_BHT_ENTRIES_W-1:0] bht_wr_entry_w = GSHARE_ENABLE ? gshare_wr_entry_w : branch_source_i[2+NUM_BHT_ENTRIES_W-1:2];
wire [NUM_BHT_ENTRIES_W-1:0] bht_rd_entry_w = GSHARE_ENABLE ? gshare_rd_entry_w : {pc_f_i_r[3+NUM_BHT_ENTRIES_W-2:3],btb_upper_w};

integer i4;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    for (i4 = 0; i4 < NUM_BHT_ENTRIES; i4 = i4 + 1)
    begin
        bht_sat_q[i4] = 2'd3; //当for循环赋值的数组变大时进行非阻塞赋值，会导致综合工具报错，要改成阻塞赋值
    end
end
else if (branch_is_taken_i && bht_sat_q[bht_wr_entry_w] < 2'd3)
    bht_sat_q[bht_wr_entry_w] <= bht_sat_q[bht_wr_entry_w] + 2'd1;
else if (branch_is_not_taken_i && bht_sat_q[bht_wr_entry_w] > 2'd0)
    bht_sat_q[bht_wr_entry_w] <= bht_sat_q[bht_wr_entry_w] - 2'd1;

wire bht_predict_taken_w = BHT_ENABLE && (bht_sat_q[bht_rd_entry_w] >= 2'd2); //根据对应条目的饱和计数器值来预测是否跳转






//-----------------------------------------------------------------
// Branch target buffer //存储分支指令的目标地址和类型 TODO：改组相连
//-----------------------------------------------------------------
reg [31:0]  btb_pc_q[NUM_BTB_ENTRIES-1:0];       //分支指令的pc地址
reg [31:0]  btb_target_q[NUM_BTB_ENTRIES-1:0];   //分支目标地址
reg         btb_is_call_q[NUM_BTB_ENTRIES-1:0];  //标记是否为call指令，2**9个条目
reg         btb_is_ret_q[NUM_BTB_ENTRIES-1:0];   //标记是否为ret指令，2**9个条目
reg         btb_is_jmp_q[NUM_BTB_ENTRIES-1:0];   //标记是否为jump指令，2**9个条目

reg         btb_valid_r;   //BTB是否命中
reg         btb_upper_r;   //是否命中上半个字（压缩指令）
reg         btb_is_call_r; //预测为call指令
reg         btb_is_ret_r;  //预测为ret指令
reg [31:0]  btb_next_pc_r; //预测的下一个pc地址
reg         btb_is_jmp_r;  //预测为jump指令

reg [NUM_BTB_ENTRIES_W-1:0] btb_entry_r; //用于记录在BTB命中时，记录哪一个条目命中的，用于更新后续的BYB训练阶段需要知道更新哪个条目，避免在训练时再次遍历寻找
integer i0;

always @ *
begin
    btb_valid_r   = 1'b0;
    btb_upper_r   = 1'b0;
    btb_is_call_r = 1'b0;
    btb_is_ret_r  = 1'b0;
    btb_is_jmp_r  = 1'b0;
    btb_next_pc_r = {pc_f_i_r[31:3],3'b0} + 32'd8; //正常情况，取出两条指令
    btb_entry_r   = {NUM_BTB_ENTRIES_W{1'b0}};

    for (i0 = 0; i0 < NUM_BTB_ENTRIES; i0 = i0 + 1)
    begin
        if (btb_pc_q[i0] == pc_f_i_r) //当前需要取指令的的pc是否有命中BTB中的地址
        begin
            btb_valid_r   = 1'b1;
            btb_upper_r   = pc_f_i_r[2]; //分支在fetch块的上半部分(PC+4)还是下半部分(PC)
            btb_is_call_r = btb_is_call_q[i0];
            btb_is_ret_r  = btb_is_ret_q[i0];
            btb_is_jmp_r  = btb_is_jmp_q[i0];
            btb_next_pc_r = btb_target_q[i0];
/* verilator lint_off WIDTH */
            btb_entry_r   = i0; //记录是哪一个BTB条目命中的
/* verilator lint_on WIDTH */
        end
    end

    // 如果未命中就进行伙伴查找，PC+4
    // 此时如果命中，btb_upper_r 就是 1。
    // 这个标志就是 当前被查找指令的位置，如果是高位就是 1，如果是低位就是 0。
    if (~btb_valid_r && ~pc_f_i_r[2])
        for (i0 = 0; i0 < NUM_BTB_ENTRIES; i0 = i0 + 1)  //16
        begin
            if (btb_pc_q[i0] == (pc_f_i_r | 32'd4))
            begin
                btb_valid_r   = 1'b1;
                btb_upper_r   = 1'b1;
                btb_is_call_r = btb_is_call_q[i0];
                btb_is_ret_r  = btb_is_ret_q[i0];
                btb_is_jmp_r  = btb_is_jmp_q[i0];
                btb_next_pc_r = btb_target_q[i0];
/* verilator lint_off WIDTH */
                btb_entry_r   = i0;
/* verilator lint_on WIDTH */
            end
        end
end

reg [NUM_BTB_ENTRIES_W-1:0]  btb_wr_entry_r;
wire [NUM_BTB_ENTRIES_W-1:0] btb_wr_alloc_w;

reg btb_hit_r; //分支指令的原始地址命中BTB
reg btb_miss_r;
integer i1;
always @ *
begin
    btb_wr_entry_r = {NUM_BTB_ENTRIES_W{1'b0}};
    btb_hit_r      = 1'b0;
    btb_miss_r     = 1'b0;

    // Misprediction - learn / update branch details
    if (branch_request_i)
    begin
        for (i1 = 0; i1 < NUM_BTB_ENTRIES; i1 = i1 + 1)
        begin
            if (btb_pc_q[i1] == branch_source_i) //正在执行的分支指令的原始地址是否命中BTB
            begin
                btb_hit_r      = 1'b1;
    /* verilator lint_off WIDTH */
                btb_wr_entry_r = i1;
    /* verilator lint_on WIDTH */
            end
        end
        btb_miss_r = ~btb_hit_r;
    end
end

integer i2;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    for (i2 = 0; i2 < NUM_BTB_ENTRIES; i2 = i2 + 1)
    begin
        btb_pc_q[i2]      = 32'b0;
        btb_target_q[i2]  = 32'b0;
        btb_is_call_q[i2] = 1'b0;
        btb_is_ret_q[i2]  = 1'b0;
        btb_is_jmp_q[i2]  = 1'b0;
    end
end
// Hit - update entry
else if (btb_hit_r)
begin
    btb_pc_q[btb_wr_entry_r]     <= branch_source_i;
    if (branch_is_taken_i)
        btb_target_q[btb_wr_entry_r] <= branch_pc_i;
    btb_is_call_q[btb_wr_entry_r]<= branch_is_call_i;
    btb_is_ret_q[btb_wr_entry_r] <= branch_is_ret_i;
    btb_is_jmp_q[btb_wr_entry_r] <= branch_is_jmp_i;
end
// Miss - allocate entry
else if (btb_miss_r)
begin
    btb_pc_q[btb_wr_alloc_w]     <= branch_source_i;
    btb_target_q[btb_wr_alloc_w] <= branch_pc_i;
    btb_is_call_q[btb_wr_alloc_w]<= branch_is_call_i;
    btb_is_ret_q[btb_wr_alloc_w] <= branch_is_ret_i;
    btb_is_jmp_q[btb_wr_alloc_w] <= branch_is_jmp_i;
end

//-----------------------------------------------------------------
// Replacement Selection
//-----------------------------------------------------------------
biriscv_npc_lfsr0
#(
    .DEPTH(NUM_BTB_ENTRIES)
   ,.ADDR_W(NUM_BTB_ENTRIES_W)
)
u_lru
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.hit_i(btb_valid_r)        //btb是否命中
    ,.hit_entry_i(btb_entry_r) //btb命中的条目

    ,.alloc_i(btb_miss_r)           //btb没有命中
    ,.alloc_entry_o(btb_wr_alloc_w) //输出需要更换的btb条目
);

//-----------------------------------------------------------------
// Outputs
//-----------------------------------------------------------------
assign btb_valid_w   = btb_valid_r; //btb命中
assign btb_upper_w   = btb_upper_r;
assign btb_is_call_w = btb_is_call_r;
assign btb_is_ret_w  = btb_is_ret_r;

assign next_pc_f_o   = (branch_request_i || reg_branch_request_r) && branch_source_i == pc_f_i_r ? branch_pc_i :
ras_ret_pred_w      ? ras_pc_pred_w :
                       (bht_predict_taken_w | btb_is_jmp_r) ? btb_next_pc_r :
                       {pc_f_i_r[31:3],3'b0} + 32'd8;
                       //执行阶段分支确认
                       //RAS返回地址预测
                       //常规分支/跳转预测--给出再次预测的地址

assign next_taken_f_o = (btb_valid_w & (ras_ret_pred_w | bht_predict_taken_w | btb_is_jmp_r)) ?
                        pc_f_i_r[2] ? {btb_upper_r, 1'b0} :
                        {btb_upper_r, ~btb_upper_r} : 2'b0;


assign pred_taken_w   = btb_valid_w & (ras_ret_pred_w | bht_predict_taken_w | btb_is_jmp_r) & pc_accept_i_r; //btb命中，预测要跳转或是ret或jmp指令，pc请求
assign pred_ntaken_w  = btb_valid_w & ~pred_taken_w & pc_accept_i_r;

end
//-----------------------------------------------------------------
// No branch prediction
//-----------------------------------------------------------------
else
begin: NO_BRANCH_PREDICTION

assign next_pc_f_o    = {pc_f_i[31:3],3'b0} + 32'd8;
assign next_taken_f_o = 2'b0;

end
endgenerate
endmodule

module biriscv_npc_lfu
#(
    parameter DEPTH           = 512,     // 条目数
    parameter ADDR_W          = 9,      // 地址位宽 log2(DEPTH)
    parameter COUNTER_W       = 10,      // 频率计数器位宽（2^COUNTER_W-1最大计数）
    parameter AGING_PERIOD    = 256     // 老化周期
)
(
    // Inputs
    input                   clk_i,
    input                   rst_i,
    input                   hit_i,           // 命中信号
    input  [ADDR_W-1:0]    hit_entry_i,     // 命中的条目索引
    input                   alloc_i,         // 需要分配新条目
    
    // Outputs
    output [ADDR_W-1:0]    alloc_entry_o    // 要替换的条目索引
);

//-----------------------------------------------------------------
// LFU with Aging Implementation
//-----------------------------------------------------------------
reg [COUNTER_W-1:0] counter_r [0:DEPTH-1];  // 每个条目的访问频率计数器
reg [DEPTH-1:0]     valid_r;                // 条目有效位
reg [ADDR_W-1:0]    min_entry_r;            // 当前最小频率条目
reg [COUNTER_W-1:0] min_count_r;            // 当前最小频率值
reg [9:0]           aging_counter_r;        // 老化计数器

// 初始化所有存储
integer i;
initial begin
    for (i = 0; i < DEPTH; i = i + 1) begin
        counter_r[i] = {COUNTER_W{1'b0}};
    end
    valid_r = {DEPTH{1'b0}};
end

//-----------------------------------------------------------------
// 组合逻辑：查找最小频率条目
//-----------------------------------------------------------------
wire [ADDR_W-1:0]   min_entry_w;
wire [COUNTER_W-1:0] min_count_w;
reg [ADDR_W-1:0]    current_min_entry;
reg [COUNTER_W-1:0] current_min_count;
reg                 found_valid;

always @(*) begin
    current_min_entry = {ADDR_W{1'b0}};
    current_min_count = {COUNTER_W{1'b1}};  // 初始设为最大值
    found_valid = 1'b0;
    
    // 遍历所有条目查找最小频率的有效条目
    for (i = 0; i < DEPTH; i = i + 1) begin
        if (valid_r[i]) begin
            if ((counter_r[i] < current_min_count) || !found_valid) begin
                current_min_entry = i[ADDR_W-1:0];
                current_min_count = counter_r[i];
                found_valid = 1'b1;
            end
            // 频率相同时，选择索引较小的（保持确定性）
            else if ((counter_r[i] == current_min_count) && (i[ADDR_W-1:0] < current_min_entry)) begin
                current_min_entry = i[ADDR_W-1:0];
                current_min_count = counter_r[i];
            end
        end
    end
    
    // 如果没有有效条目，返回0
    if (!found_valid) begin
        current_min_entry = {ADDR_W{1'b0}};
        current_min_count = {COUNTER_W{1'b0}};
    end
end

assign min_entry_w = current_min_entry;
assign min_count_w = current_min_count;

//-----------------------------------------------------------------
// 时序逻辑：更新计数器和状态
//-----------------------------------------------------------------
always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
        // 复位所有计数器
        for (i = 0; i < DEPTH; i = i + 1) begin
            counter_r[i] <= {COUNTER_W{1'b0}};
        end
        valid_r <= {DEPTH{1'b0}};
        min_entry_r <= {ADDR_W{1'b0}};
        min_count_r <= {COUNTER_W{1'b0}};
        aging_counter_r <= 10'b0;
    end
    else begin
        // 缓存当前最小频率条目（减少关键路径）
        min_entry_r <= min_entry_w;
        min_count_r <= min_count_w;
        
        // 老化计数器递增
        aging_counter_r <= aging_counter_r + 1'b1;
        
        // 周期性老化：所有计数器右移1位（除以2）
        if (aging_counter_r == 10'd1023) begin
            aging_counter_r <= 10'b0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                if (valid_r[i]) begin
                    counter_r[i] = {1'b0, counter_r[i][COUNTER_W-1:1]};
                end
            end
        end
        
        // 命中：增加对应条目的计数器
        if (hit_i && valid_r[hit_entry_i]) begin
            // 防溢出：不超过最大值
            if (counter_r[hit_entry_i] != {COUNTER_W{1'b1}}) begin
                counter_r[hit_entry_i] <= counter_r[hit_entry_i] + 1'b1;
            end
        end
        
        // 分配新条目：替换最小频率条目
        if (alloc_i) begin
            // 设置新条目有效，计数器初始化为1（不是0）
            valid_r[min_entry_w] <= 1'b1;
            counter_r[min_entry_w] <= {{COUNTER_W-1{1'b0}}, 1'b1};  // 计数值=1
        end
    end
end

//-----------------------------------------------------------------
// 输出分配条目
//-----------------------------------------------------------------
assign alloc_entry_o = min_entry_r;

endmodule


module biriscv_npc_lfsr0
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter DEPTH            = 32
    ,parameter ADDR_W           = 9
    ,parameter INITIAL_VALUE    = 16'h0001
    ,parameter TAP_VALUE        = 16'hB400
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           hit_i
    ,input  [ADDR_W-1:0]  hit_entry_i
    ,input           alloc_i

    // Outputs
    ,output [ADDR_W-1:0]  alloc_entry_o
);

//-----------------------------------------------------------------
// Scheme: LFSR
//-----------------------------------------------------------------
reg [15:0] lfsr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    lfsr_q <= INITIAL_VALUE;
else if (alloc_i)
begin
    if (lfsr_q[0])
        lfsr_q <= {1'b0, lfsr_q[15:1]} ^ TAP_VALUE;
    else
        lfsr_q <= {1'b0, lfsr_q[15:1]};
end

assign alloc_entry_o = lfsr_q[ADDR_W-1:0];


endmodule
