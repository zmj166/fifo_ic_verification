// ============================================================================
// 文件名 : async_fifo.v
// 功  能 : 异步 FIFO 完整 RTL 实现（顶层 + 5 个子模块）
//
// ── 整体架构 ─────────────────────────────────────────────────────────────────
//
//        写时钟域 (wclk)                读时钟域 (rclk)
//   ┌──────────────────────┐       ┌──────────────────────┐
//   │                      │       │                      │
//   │  winc/wdata          │       │         rdata/rempty │
//   │     ↓                │       │              ↑       │
//   │  [write_ctrl]        │       │        [read_ctrl]   │
//   │     │ wptr_gray      │       │   rptr_gray │        │
//   │     ↓                │       │        ↓   │        │
//   │  [sync_r2w]←─────────┼───────┼─[sync_w2r] │        │
//   │  rptr_gray_sync      │       │ wptr_gray_sync       │
//   │                      │       │                      │
//   │        [fifo_mem] ───┼───────┼──→ rdata             │
//   └──────────────────────┘       └──────────────────────┘
//
// ── 子模块一览 ────────────────────────────────────────────────────────────────
//   fifo_mem   : 双端口 SRAM，写时序，读组合逻辑
//   write_ctrl : 产生写指针、写地址、wfull 信号
//   read_ctrl  : 产生读指针、读地址、rempty 信号
//   sync_w2r   : 写指针格雷码同步到读时钟域（2-FF 同步器）
//   sync_r2w   : 读指针格雷码同步到写时钟域（2-FF 同步器）
//
// ── 关键设计原则 ──────────────────────────────────────────────────────────────
//   1. 使用格雷码（Gray Code）传递指针，相邻变化只有 1 bit，
//      经过 2-FF 同步后亚稳态概率极低，是异步 FIFO 的标准做法。
//   2. 指针位宽比地址多 1 bit（ADDR_WIDTH+1），最高位用于区分满/空。
//      满条件：wptr 和 rptr 最高 2 位相反，其余位相同。
//      空条件：wptr 格雷码 == rptr 格雷码（经同步后）。
//   3. 宁可误判"满"（保守），绝不误判"空"，确保数据不丢失。
//
// ── 参数 ──────────────────────────────────────────────────────────────────────
//   DATA_WIDTH = 8  : 数据位宽（默认8位）
//   ADDR_WIDTH = 4  : 地址位宽（默认4位，深度 = 2^4 = 16）
//
// 版本: v1.0 | 时间精度: 1ns/1ps
// ============================================================================

`timescale 1ns/1ps

// ============================================================================
// 顶层模块：async_fifo
// 作用：把 5 个子模块实例化并连线，对外呈现完整的 FIFO 接口
// ============================================================================
module async_fifo #(
    parameter DATA_WIDTH = 8,   // 数据位宽，可按需修改
    parameter ADDR_WIDTH = 4    // 地址位宽，FIFO深度 = 2^ADDR_WIDTH
) (
    // ── 写端口（工作在 wclk 时钟域）──────────────────────────────────────
    input  wire                  wclk,   // 写时钟：所有写操作在其上升沿触发
    input  wire                  wrst_n, // 写复位：低有效，异步复位写时钟域
    input  wire                  winc,   // 写使能：为1且wfull=0时执行写操作
    input  wire [DATA_WIDTH-1:0] wdata,  // 写数据：写入FIFO的数据
    output wire                  wfull,  // 满标志：为1时禁止写入，防止溢出

    // ── 读端口（工作在 rclk 时钟域）──────────────────────────────────────
    input  wire                  rclk,   // 读时钟：所有读操作在其上升沿触发
    input  wire                  rrst_n, // 读复位：低有效，异步复位读时钟域
    input  wire                  rinc,   // 读使能：为1且rempty=0时执行读操作
    output wire [DATA_WIDTH-1:0] rdata,  // 读数据：从FIFO读出的数据（组合逻辑）
    output wire                  rempty  // 空标志：为1时禁止读取，防止下溢
);

    // ── 内部连线（子模块之间的信号）─────────────────────────────────────────
    // 指针（ADDR_WIDTH+1 位：最高位作为"圈数"标志位，用于判断满/空）
    wire [ADDR_WIDTH:0]   wptr;          // 写指针（二进制，写时钟域）
    wire [ADDR_WIDTH:0]   rptr;          // 读指针（二进制，读时钟域）
    wire [ADDR_WIDTH:0]   wptr_gray;     // 写指针的格雷码（写时钟域）
    wire [ADDR_WIDTH:0]   rptr_gray;     // 读指针的格雷码（读时钟域）
    wire [ADDR_WIDTH:0]   wptr_gray_sync; // 写指针格雷码同步到读时钟域后的值
    wire [ADDR_WIDTH:0]   rptr_gray_sync; // 读指针格雷码同步到写时钟域后的值
    wire [ADDR_WIDTH-1:0] waddr;         // 写地址（去掉最高位，用于寻址存储器）
    wire [ADDR_WIDTH-1:0] raddr;         // 读地址（去掉最高位，用于寻址存储器）

    // ── 子模块实例化 ─────────────────────────────────────────────────────────

    // 【存储器】双端口 SRAM
    // 写操作：在 wclk 上升沿，若 wenc=1 则写入 wdata 到 waddr
    // 读操作：rdata 直接组合逻辑输出 mem[raddr]，无时钟
    fifo_mem #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_mem (
        .wclk  (wclk),
        .wenc  (winc & ~wfull),  // 写使能 = winc AND (不满)，防止满时写入
        .waddr (waddr),
        .wdata (wdata),
        .raddr (raddr),
        .rdata (rdata)
    );

    // 【写控制器】产生写指针和 wfull 信号
    // 输入：写时钟、复位、winc、来自读时钟域同步过来的读指针
    // 输出：wptr/wptr_gray（给 sync_r2w 用）、waddr（给存储器）、wfull
    write_ctrl #(.ADDR_WIDTH(ADDR_WIDTH)) u_wctrl (
        .wclk          (wclk),
        .wrst_n        (wrst_n),
        .winc          (winc),
        .rptr_gray_sync(rptr_gray_sync),  // 同步过来的读指针格雷码
        .wptr          (wptr),
        .wptr_gray     (wptr_gray),
        .waddr         (waddr),
        .wfull         (wfull)
    );

    // 【读控制器】产生读指针和 rempty 信号
    // 输入：读时钟、复位、rinc、来自写时钟域同步过来的写指针
    // 输出：rptr/rptr_gray（给 sync_w2r 用）、raddr（给存储器）、rempty
    read_ctrl #(.ADDR_WIDTH(ADDR_WIDTH)) u_rctrl (
        .rclk          (rclk),
        .rrst_n        (rrst_n),
        .rinc          (rinc),
        .wptr_gray_sync(wptr_gray_sync),  // 同步过来的写指针格雷码
        .rptr          (rptr),
        .rptr_gray     (rptr_gray),
        .raddr         (raddr),
        .rempty        (rempty)
    );

    // 【写→读同步器】将写指针格雷码从写时钟域同步到读时钟域
    // 读控制器用 wptr_gray_sync 来判断是否为空
    sync_w2r #(.ADDR_WIDTH(ADDR_WIDTH)) u_sw2r (
        .wptr_gray     (wptr_gray),
        .rclk          (rclk),
        .rrst_n        (rrst_n),
        .wptr_gray_sync(wptr_gray_sync)
    );

    // 【读→写同步器】将读指针格雷码从读时钟域同步到写时钟域
    // 写控制器用 rptr_gray_sync 来判断是否为满
    sync_r2w #(.ADDR_WIDTH(ADDR_WIDTH)) u_sr2w (
        .rptr_gray     (rptr_gray),
        .wclk          (wclk),
        .wrst_n        (wrst_n),
        .rptr_gray_sync(rptr_gray_sync)
    );

endmodule


// ============================================================================
// 子模块1：fifo_mem — 双端口存储器
// ============================================================================
// 功能：
//   - 写端口：同步写（wclk 上升沿触发），wenc=1 时将 wdata 写入 mem[waddr]
//   - 读端口：异步读（组合逻辑），rdata = mem[raddr]，无时钟延迟
//
// 关键点：读是组合逻辑（assign），rinc 有效的同一拍上升沿前 rdata 已稳定，
//   这是 Monitor 能在同一拍采样到正确数据的根本原因。
// ============================================================================
module fifo_mem #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,   // 写时钟
    input  wire                  wenc,   // 写使能（由顶层保证：winc & ~wfull）
    input  wire [ADDR_WIDTH-1:0] waddr,  // 写地址（来自write_ctrl）
    input  wire [DATA_WIDTH-1:0] wdata,  // 写数据
    input  wire [ADDR_WIDTH-1:0] raddr,  // 读地址（来自read_ctrl，组合逻辑输出）
    output wire [DATA_WIDTH-1:0] rdata   // 读数据（组合逻辑，实时跟随raddr变化）
);
    localparam DEPTH = (1 << ADDR_WIDTH);  // 深度 = 2^ADDR_WIDTH = 16

    // 存储阵列：DEPTH 个 DATA_WIDTH 宽的寄存器
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 初始化：仿真开始时全部清零（避免 X 状态干扰结果）
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 0;
    end

    // 同步写：wclk 上升沿且 wenc=1 时写入
    always @(posedge wclk) begin
        if (wenc)
            mem[waddr] <= wdata;
    end

    // 组合读：rdata 直接等于 mem[raddr]，raddr 变化时 rdata 立即变化
    // 注意：这不是寄存器输出，没有时钟延迟
    assign rdata = mem[raddr];

endmodule


// ============================================================================
// 子模块2：write_ctrl — 写控制器
// ============================================================================
// 功能：
//   1. 维护写指针 wptr（二进制，每次成功写入加1）
//   2. 输出写地址 waddr = wptr 的低 ADDR_WIDTH 位（去掉最高的圈数标志位）
//   3. 输出写指针格雷码 wptr_gray（用于跨时钟域传输）
//   4. 计算并输出满标志 wfull
//
// 满的判断条件（格雷码比较）：
//   当写指针追上读指针"一圈"时为满。在格雷码中的表现：
//     - wptr_gray 的最高位（第 ADDR_WIDTH 位）≠ rptr_gray_sync 的最高位
//     - wptr_gray 的次高位（第 ADDR_WIDTH-1 位）≠ rptr_gray_sync 的次高位
//     - 其余所有位 == rptr_gray_sync 对应位
//   这种判断方式能确保"宁可多判满，绝不少判满"（保守策略，数据安全）
// ============================================================================
module write_ctrl #(
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,          // 写时钟
    input  wire                  wrst_n,         // 写复位（低有效，异步）
    input  wire                  winc,           // 写请求（来自外部）
    input  wire [ADDR_WIDTH:0]   rptr_gray_sync, // 读指针格雷码（已同步到写时钟域）
    output reg  [ADDR_WIDTH:0]   wptr,           // 写指针（二进制）
    output wire [ADDR_WIDTH:0]   wptr_gray,      // 写指针格雷码（传给 sync_r2w）
    output wire [ADDR_WIDTH-1:0] waddr,          // 写地址（传给存储器）
    output reg                   wfull           // 满标志（传给顶层输出）
);
    // 下一状态计算（组合逻辑）
    // 只有在 winc=1 且不满时，指针才加1；满时保持不变（防止溢出）
    wire [ADDR_WIDTH:0] wptr_next      = wptr + (winc & ~wfull);

    // 二进制转格雷码公式：gray = binary XOR (binary >> 1)
    // 格雷码相邻值只有 1 bit 不同，CDC 传输更安全
    wire [ADDR_WIDTH:0] wptr_gray_next = wptr_next ^ (wptr_next >> 1);

    // 满条件检测（格雷码比较）
    wire wfull_next =
        // 最高位必须相反（表示写指针比读指针多绕了一圈）
        (wptr_gray_next[ADDR_WIDTH]     != rptr_gray_sync[ADDR_WIDTH]  ) &&
        // 次高位也必须相反（格雷码满条件的特殊性，与二进制不同）
        (wptr_gray_next[ADDR_WIDTH-1]   != rptr_gray_sync[ADDR_WIDTH-1]) &&
        // 其余低位必须完全相同（指向相同的物理地址）
        (wptr_gray_next[ADDR_WIDTH-2:0] == rptr_gray_sync[ADDR_WIDTH-2:0]);

    // 写地址 = 写指针去掉最高位（最高位仅用于满/空判断，不参与寻址）
    assign waddr     = wptr[ADDR_WIDTH-1:0];

    // 输出格雷码格式的写指针（供同步器 sync_r2w 使用）
    assign wptr_gray = wptr ^ (wptr >> 1);

    // 时序逻辑：在 wclk 上升沿更新写指针和满标志
    // 复位时：wptr=0（从头开始写）, wfull=0（不满）
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)
            {wptr, wfull} <= 0;       // 异步复位：指针清零，满标志清零
        else begin
            wptr  <= wptr_next;       // 更新写指针
            wfull <= wfull_next;      // 更新满标志
        end
    end

endmodule


// ============================================================================
// 子模块3：read_ctrl — 读控制器
// ============================================================================
// 功能：
//   1. 维护读指针 rptr（二进制，每次成功读出加1）
//   2. 输出读地址 raddr = rptr 的低 ADDR_WIDTH 位
//   3. 输出读指针格雷码 rptr_gray（用于跨时钟域传输）
//   4. 计算并输出空标志 rempty
//
// 空的判断条件：
//   rptr 追上 wptr（读得和写的一样多）时为空。
//   在格雷码中的表现：rptr_gray_next == wptr_gray_sync
//   即：下一个读指针的格雷码 == 同步过来的写指针格雷码
//
// 初始状态：复位后 rempty=1（FIFO 是空的），rptr=0
// ============================================================================
module read_ctrl #(
    parameter ADDR_WIDTH = 4
) (
    input  wire                  rclk,          // 读时钟
    input  wire                  rrst_n,         // 读复位（低有效，异步）
    input  wire                  rinc,           // 读请求
    input  wire [ADDR_WIDTH:0]   wptr_gray_sync, // 写指针格雷码（已同步到读时钟域）
    output reg  [ADDR_WIDTH:0]   rptr,           // 读指针（二进制）
    output wire [ADDR_WIDTH:0]   rptr_gray,      // 读指针格雷码（传给 sync_w2r）
    output wire [ADDR_WIDTH-1:0] raddr,          // 读地址（传给存储器）
    output reg                   rempty          // 空标志
);
    // 下一状态：只有 rinc=1 且不空时，读指针才加1
    wire [ADDR_WIDTH:0] rptr_next      = rptr + (rinc & ~rempty);

    // 二进制转格雷码
    wire [ADDR_WIDTH:0] rptr_gray_next = rptr_next ^ (rptr_next >> 1);

    // 空条件：下一个读指针的格雷码 == 写指针格雷码（追上写指针了）
    wire rempty_next = (rptr_gray_next == wptr_gray_sync);

    // 读地址 = 读指针去掉最高位（最高位仅用于空满判断）
    assign raddr     = rptr[ADDR_WIDTH-1:0];

    // 输出读指针格雷码（供同步器 sync_w2r 使用）
    assign rptr_gray = rptr ^ (rptr >> 1);

    // 时序逻辑：在 rclk 上升沿更新读指针和空标志
    // 复位时：rptr=0, rempty=1（初始为空）
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            {rptr, rempty} <= {0, 1'b1};  // 异步复位：指针清零，空标志置1
        else begin
            rptr   <= rptr_next;           // 更新读指针
            rempty <= rempty_next;         // 更新空标志
        end
    end

endmodule


// ============================================================================
// 子模块4：sync_w2r — 写指针格雷码同步器（写时钟域 → 读时钟域）
// ============================================================================
// 功能：将写时钟域的 wptr_gray 安全传递到读时钟域
//
// 原理（2-FF 同步器）：
//   第一级 FF（ff1）：采样 wptr_gray，可能产生亚稳态
//   第二级 FF（wptr_gray_sync）：再采样一次，亚稳态概率接近 0
//
// 为什么用格雷码：
//   普通二进制指针跳变时可能多 bit 同时变化（如 0111→1000 有 4 bit 变化），
//   经过异步采样极易产生错误值。格雷码相邻只有 1 bit 变化，
//   即使 CDC 采样时出现亚稳态，最坏也只是采样偏早/偏晚 1 个周期，
//   不会产生中间错误值，安全得多。
//
// 延迟：2 个 rclk 周期
// ============================================================================
module sync_w2r #(
    parameter ADDR_WIDTH = 4
) (
    input  wire [ADDR_WIDTH:0] wptr_gray,      // 写指针格雷码（写时钟域）
    input  wire                rclk,           // 读时钟
    input  wire                rrst_n,          // 读复位
    output reg  [ADDR_WIDTH:0] wptr_gray_sync  // 同步后的写指针格雷码（读时钟域）
);
    reg [ADDR_WIDTH:0] ff1;  // 第一级触发器（可能有亚稳态）

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            ff1            <= 0;  // 复位第一级
            wptr_gray_sync <= 0;  // 复位第二级
        end else begin
            ff1            <= wptr_gray;  // 第一级采样（可能亚稳态）
            wptr_gray_sync <= ff1;        // 第二级再采样（亚稳态基本消除）
        end
    end

endmodule


// ============================================================================
// 子模块5：sync_r2w — 读指针格雷码同步器（读时钟域 → 写时钟域）
// ============================================================================
// 功能：将读时钟域的 rptr_gray 安全传递到写时钟域
// 原理与 sync_w2r 完全对称，只是时钟方向相反
//
// 延迟：2 个 wclk 周期（所以满标志会比实际满稍微滞后，是保守判断）
// ============================================================================
module sync_r2w #(
    parameter ADDR_WIDTH = 4
) (
    input  wire [ADDR_WIDTH:0] rptr_gray,      // 读指针格雷码（读时钟域）
    input  wire                wclk,           // 写时钟
    input  wire                wrst_n,          // 写复位
    output reg  [ADDR_WIDTH:0] rptr_gray_sync  // 同步后的读指针格雷码（写时钟域）
);
    reg [ADDR_WIDTH:0] ff1;  // 第一级触发器

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            ff1            <= 0;
            rptr_gray_sync <= 0;
        end else begin
            ff1            <= rptr_gray;  // 第一级采样
            rptr_gray_sync <= ff1;        // 第二级消除亚稳态
        end
    end

endmodule
