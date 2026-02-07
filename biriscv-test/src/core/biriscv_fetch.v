module biriscv_fetch
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MMU      = 1
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    //流控信号
    ,input           fetch_accept_i   //下游（译码）是否接受指令
    ,input           icache_accept_i  //cache是否接受请求
    ,input           icache_valid_i   //cache返回数据有效
    //cache数据
    ,input           icache_error_i
    ,input  [ 63:0]  icache_inst_i       //2条指令
    ,input           icache_page_fault_i //页错误
    //控制信号
    ,input           fetch_invalidate_i  //取指无效，清空icache
    ,input           branch_request_i    //分支请求，清空取指单元
    ,input  [ 31:0]  branch_pc_i         //分支目标地址
    //分支预测相关
    ,input  [ 31:0]  next_pc_f_i         //npc预测的下一个pc
    ,input  [  1:0]  next_taken_f_i      //npc预测的分支结果
    ,input  npcg_valid                   //npcg输出有效

    ,output fetch_allowin //是否允许上游输入

    // Outputs
    //取指输出-给idu
    ,output          fetch_valid_o       //指令有效
    ,output [ 63:0]  fetch_instr_o       //2条指令
    ,output [  1:0]  fetch_pred_branch_o //预测分支结果
    ,output          fetch_fault_fetch_o //取指异常
    ,output          fetch_fault_page_o  //页异常
    ,output [ 31:0]  fetch_pc_o          //指令对应的pc
    // ICACHE 控制          
    ,output          icache_rd_o          //读请求
    ,output          icache_flush_o       //cache刷新
    ,output          icache_invalidate_o  //icache无效化
    ,output [ 31:0]  icache_pc_o          //请求的pc
    ,output [  1:0]  icache_priv_o        //权限级别
);

// ┌─────────────────────────────────────────────────────┐
// │                 biriscv_fetch 取指单元                 │
// ├─────────────┬──────────────┬───────────────────────┤
// │  控制逻辑    │  请求跟踪     │    响应缓冲            │
// │ (状态机)     │ (pending状态) │ (skid buffer)        │
// └─────────────┴──────────────┴───────────────────────┘

reg fetch_valid_r;   //取指单元是否有效
wire fetch_ready_go; 

reg [31:0] next_pc_f_i_r;  //保存的pc值
reg [1:0] next_taken_f_i_r;//保存的预测结果 


always @(posedge clk_i or posedge rst_i) begin
    // 复位或分支预测错误时：清空状态，取指单元无效
    if (rst_i || branch_request_i) begin
        fetch_valid_r <= 1'b0;
    end
    //正常情况----允许输入且没有分支：接收新pc
    else if (fetch_allowin) begin
        fetch_valid_r <= npcg_valid;
    end
    // branch_request_i 拉低时不更新，因为此时 npcg 的数据还是旧的
    if (npcg_valid && fetch_allowin && !branch_request_i) begin
        next_pc_f_i_r <= next_pc_f_i;
        next_taken_f_i_r <= next_taken_f_i;
    end
end

//-------------------------------------------------------------
// Stall flag---停顿（stall）控制
//-------------------------------------------------------------

// 这个 stall 信号有两个作用，一个暂停接受上游 pc
// 一个是恢复 stall 之后
wire icache_busy_w;  //cache是否忙
//停顿情况：下游不接受（译码阶段停顿）、cache忙-未命中、cache不接受请求-满
wire stall_w = !fetch_accept_i || icache_busy_w || !icache_accept_i;
reg stall_q;

always @ (posedge clk_i or posedge rst_i) begin
    if (rst_i)
        stall_q <= 1'b0;
    else
        stall_q <= stall_w;
end

//-------------------------------------------------------------
// Request tracking
//-------------------------------------------------------------
reg icache_fetch_q;      //是否有pending的cache请求
reg icache_invalidate_q; //是否有pending的无效化请求

// 追踪 branch 后是否有旧请求需要丢弃
// branch 发生时，如果有 pending 的 icache 请求，需要丢弃其返回数据

// ICACHE fetch tracking-用于跟踪icache的请求状态
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    icache_fetch_q <= 1'b0;
else if (branch_request_i)
// branch发生时清除pending状态
    icache_fetch_q <= 1'b0;
else if (icache_rd_o && icache_accept_i)
// 发送请求且被接受：进入pending状态
    icache_fetch_q <= 1'b1;
else if (icache_valid_i)
//收到相应：退出pending状态
    icache_fetch_q <= 1'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    icache_invalidate_q <= 1'b0;
else if (icache_invalidate_o && !icache_accept_i) //icache_invalidate_o一直为0，cache默认不会有pending的无效化请求
    icache_invalidate_q <= 1'b1;
else
    icache_invalidate_q <= 1'b0;



// icache 是否忙，一旦 icache 上一周期已经发请求且 valid 信号未来到，
// 这意味着 icache 发生了未命中。一旦命中，下一个周期就能拿到信号，这样 busy 信号就
// 没有拉高过。

assign icache_busy_w = icache_fetch_q && !icache_valid_i; //在pengding状态，等待cache传递有效信号过来
// 拿到上游的 pc 信息后就可以请求 icache 了

// 跟踪最新的发往 icache 的请求信号
wire [31:0] icache_pc_w;
reg [31:0] pc_d_q;       //保存发送给cache的pc，用于时序对齐
reg [1:0] pred_d_q;      //保存对应的分支预测信息

always @ (posedge clk_i or posedge rst_i) begin
    if (rst_i)
        pc_d_q <= 32'b0;
    else if (icache_rd_o && icache_accept_i)
        pc_d_q <= icache_pc_w;  //记录发送时的pc
end


always @ (posedge clk_i or posedge rst_i) begin
    if (rst_i)
        pred_d_q <= 2'b0;
    else if (icache_rd_o && icache_accept_i)
        pred_d_q <= next_taken_f_i_r;
    else if (icache_valid_i)
        pred_d_q <= 2'b0;
end
// 为什么要跟踪，为了解决跨周期的问题
// 如果 T 发送了请求
// 那么 T+1 icache 才会返回数据
// 此时 pc_d_q，pred_d_q 保存的数据就会和返回的数据对齐

//-------------------------------------------------------------
// Response Buffer-响应缓冲
//-------------------------------------------------------------
reg [99:0]  skid_buffer_q; // 100位缓冲：{page_fault, fetch_fault, pred, pc, instr}
reg         skid_valid_q;  // skid buffer 是否有效

always @ (posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
        skid_buffer_q  <= 100'b0;
        skid_valid_q   <= 1'b0;
    end
    else if (branch_request_i) begin
        // branch 时清除 skid buffer 中的旧数据
        skid_valid_q   <= 1'b0;
        skid_buffer_q  <= 100'b0;
    end
    else if (fetch_valid_o && !fetch_accept_i) begin
        //下游不接受时，存入缓存
        skid_valid_q  <= 1'b1;
        skid_buffer_q <= {fetch_fault_page_o, fetch_fault_fetch_o, fetch_pred_branch_o, fetch_pc_o, fetch_instr_o};
    end
    else begin
        skid_valid_q  <= 1'b0;
        skid_buffer_q <= 100'b0;
    end
end
// 这个深度为 1 的 buffer 的作用是，如果上一个周期 icache 发起请求，此时 decode 发来了
// 拉低了 fetch_accept_i，这意味着 decode 暂时无法接受数据，此时就可以将这一个请求数据返回后放到 buffer 中。

wire branch_w = branch_request_i;
wire [1:0] icache_priv_w;

wire fetch_resp_drop_w;

assign icache_pc_w       = next_pc_f_i_r;
assign icache_priv_w     = `PRIV_MACHINE; // Don't care 特权级别默认机器级
// branch 当周期丢弃，或者 branch 后有旧的 pending 请求返回也丢弃
assign fetch_resp_drop_w = branch_w;

//-------------------------------------------------------------
// Outputs
//-------------------------------------------------------------
//输出给cache
assign icache_rd_o         = fetch_valid_r & fetch_accept_i & !icache_busy_w & !branch_request_i;
assign icache_pc_o         = {icache_pc_w[31:3],3'b0};
assign icache_priv_o       = icache_priv_w;
assign icache_flush_o      = fetch_invalidate_i || icache_invalidate_q; //取指无效，或者有pending的无效化请求
assign icache_invalidate_o = 1'b0;
assign icache_busy_w       =  icache_fetch_q && !icache_valid_i; //在pengding状态，等待cache传递有效信号过来

//输出给idu
assign fetch_valid_o       = (icache_valid_i || skid_valid_q) & !fetch_resp_drop_w;
assign fetch_pc_o          = skid_valid_q ? skid_buffer_q[95:64] : {pc_d_q[31:3],3'b0}; //按照8字节对齐
assign fetch_instr_o       = skid_valid_q ? skid_buffer_q[63:0]  : icache_inst_i;
assign fetch_pred_branch_o = skid_valid_q ? skid_buffer_q[97:96] : pred_d_q;

// Faults
assign fetch_fault_fetch_o = skid_valid_q ? skid_buffer_q[98] : icache_error_i;
assign fetch_fault_page_o  = skid_valid_q ? skid_buffer_q[99] : icache_page_fault_i;

assign fetch_allowin = !fetch_valid_r || !stall_w;  //取指单元无效，或者不stall时允许上游输入


endmodule