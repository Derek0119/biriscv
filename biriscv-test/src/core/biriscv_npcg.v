module biriscv_npcg
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MMU = 1
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i

    // Branch interface- 来自issue的分支（错误）请求
    ,input           branch_request_i
    ,input           info_branch_request_i
    ,input  [ 31:0]  branch_pc_i      // 分支目标地址
    ,input  [ 31:0]  branch_source_i  // 分支指令的PC

    // 来自NPC预测的下一个PC
    ,input  [ 31:0]  next_pc_f_i
    ,input  [  1:0]  next_taken_f_i
    //来自fetch单元
    ,input fetch_allowin  //来自fetch单元，表示fetch单元是否接受npcg的pc输出

    // Outputs
    // 传向 NPC (query address)
    ,output [ 31:0]  pc_f_o
    ,output          pc_accept_o  //一直为1

    // To Fetch (current PC with branch mux)
    ,output npcg_valid    //npcg输出有效
    ,output [ 31:0]  fetch_pc_o
    ,output [  1:0]  next_taken_o
);

`include "biriscv_defs.v"

// ┌─────────────────────────────────────────────────────┐
// │                biriscv_npcg (NPC生成器)                │
// ├──────────────┬──────────────┬───────────────────────┤
// │   分支处理    │   PC寄存器    │    激活控制            │
// │ (优先级逻辑)  │ (PC状态保持)  │ (启动/分支同步)        │
// └──────────────┴──────────────┴───────────────────────┘

//-------------------------------------------------------------
// Registers
//-------------------------------------------------------------
reg [31:0]  pc_r;           // 上一周期发给 npc 查询的 PC
reg         active_q;       // Active flag
reg         branch_delay_q; // 延迟一周期等待 npc 预测生效

//-------------------------------------------------------------
// NPC Query Address
// branch 优先，否则使用 npc 预测的下一个 PC
//-------------------------------------------------------------

// 由于首次激活和后面 branch_request_i 不一样，因此这里要有一个首次激活的概念
//设计思想：区分cpu启动时的分支（从复位向量跳转）和运行时的分支
// 注意到首次激活特征是：
//branch_request_i 和info_branch_request_i 都来自issue单元，一开始只有branch_request_i被拉高
wire first_active = branch_request_i & !info_branch_request_i; //first_active信号长期为0，就一开始拉高了一下

// 当首次激活的时候，应该有一个信号 pc_r_q，它负责用来更新 pc_r
wire [31:0] pc_r_q = first_active ? branch_pc_i :
                    branch_request_i ? branch_pc_i: //如果执行阶段发现预测失败，就把真正的分支目标地址发给pc_r_q
                    next_pc_f_i;

//传递给npc
assign pc_f_o = first_active ? branch_pc_i :
                branch_request_i ? branch_pc_i:
                !fetch_allowin ? pc_r : //如果取指模块不接受新的pc，就继续用旧的pc_r
                next_pc_f_i;  //next_pc_f_i永远比pc_r多3'h8

//-------------------------------------------------------------
// Active flag
//-------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i) //cpu启动后保持激活状态，防止复位后取指无效
    if (rst_i)
        active_q <= 1'b0;
    else if (branch_request_i)
        active_q <= 1'b1;

//-------------------------------------------------------------
// PC register update
//-------------------------------------------------------------

reg [1:0] next_taken_f_i_r;
always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
        pc_r <= 32'd0;
    end
    else if (fetch_allowin && (active_q || branch_request_i) || (branch_request_i)) begin
        pc_r <= pc_r_q;
    end
end

// 再考虑 fetch
// pc_r 用来锁存要发射到 fetch 单元的 pc
// 当CPU 刚激活的时候，此时还不能给 fetch 单元发射 pc
// 因为为了统一结构，所有发射到 fetch 单元的 pc 理论上都必须由 npc 给出。

// 如果上一周期有 branch_request_i，那么这一周期不要 valid
assign npcg_valid = !first_active && active_q; //不是首次激活，避免开机时的无效pc，cpu已经激活
assign fetch_pc_o = pc_r;
assign next_taken_o = next_taken_f_i;




//-------------------------------------------------------------
// Outputs
//-------------------------------------------------------------

// 当 branch_pc 来到的时候，这个 pc 其实是目标 pc
// 但是这个目标 pc 对应的 taken 信息必须从 npc 中发出，因此这个 branch_pc 不能直接发给 fetch
// 当开机启动的时候，branch_pc 为 vec，此时可以简化 next_taken 为 0，但是这不是一般做法。
// 如果这样做了，后面遇到 branch 信息就没办法处理了，因此这里应该采用统一的解决办法

// 那就是只要是 branch_pc 来了，我们必须拿到它的 source_pc 去访问 npc，这样在下一个周期就能拿到
// npc 以及 npc 对应的 taken。

// 在处理器启动的时候，获得 branch_pc
// mux(branch_pc,npc_i) 组合电路进入 npc，
// 同时启动的时候这个 branch_pc 进入 fetch 单元

// 到了下一个周期
// npc 返回 npc_i，这个 npc 继续进入 npc
// 此时，pc_r 还没更新

assign pc_accept_o = 1'b1;
endmodule