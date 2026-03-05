// ============================================================================
// 文件名: async_fifo.v
// 描述:   异步FIFO完整RTL实现
//
// 架构图:
//   写时钟域                              读时钟域
//   [write_ctrl]--wptr_gray--[sync_w2r]--wptr_gray_sync--[read_ctrl]
//   [write_ctrl]<-rptr_gray_sync--[sync_r2w]<--rptr_gray--[read_ctrl]
//                       [fifo_mem] (双端口存储器)
//
// 设计思路:
//   异步FIFO用于跨时钟域数据传输。核心挑战是在两个不同时钟域之间
//   安全地传递读/写指针，避免亚稳态。本设计采用以下关键技术：
//     1. 格雷码指针：相邻计数值只有1位变化，降低跨时钟域采样出错的概率
//     2. 双触发器同步器（2FF Synchronizer）：消除亚稳态
//     3. 满/空判断：利用格雷码最高位特性进行保守判断，确保功能安全
//
// 参数: DATA_WIDTH=8 (数据位宽), ADDR_WIDTH=4 (地址位宽, FIFO深度=2^4=16)
// 版本: v1.0
// ============================================================================
`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// 顶层模块：async_fifo
// 功能：实例化所有子模块并连接内部信号，对外提供统一的读写接口
// ----------------------------------------------------------------------------
module async_fifo #(
    parameter DATA_WIDTH = 8,   // 数据位宽，可配置
    parameter ADDR_WIDTH = 4    // 地址位宽，FIFO深度 = 2^ADDR_WIDTH
) (
    // ---------- 写时钟域端口 ----------
    input  wire                  wclk,   // 写时钟，所有写操作在此时钟上升沿触发
    input  wire                  wrst_n, // 写侧异步复位（低电平有效）
    input  wire                  winc,   // 写使能：为1且FIFO不满时执行写操作
    input  wire [DATA_WIDTH-1:0] wdata,  // 写数据总线
    output wire                  wfull,  // FIFO满标志（写时钟域），为1时禁止写入

    // ---------- 读时钟域端口 ----------
    input  wire                  rclk,   // 读时钟，所有读操作在此时钟上升沿触发
    input  wire                  rrst_n, // 读侧异步复位（低电平有效）
    input  wire                  rinc,   // 读使能：为1且FIFO不空时执行读操作
    output wire [DATA_WIDTH-1:0] rdata,  // 读数据总线（组合逻辑输出，异步读）
    output wire                  rempty  // FIFO空标志（读时钟域），为1时禁止读取
);

    // ---------- 内部信号声明 ----------
    // 二进制指针（宽度为 ADDR_WIDTH+1，最高位用于区分满/空）
    wire [ADDR_WIDTH:0]   wptr, rptr;

    // 格雷码指针（用于跨时钟域传输，降低亚稳态风险）
    wire [ADDR_WIDTH:0]   wptr_gray, rptr_gray;

    // 同步后的格雷码指针（已跨越到对方时钟域）
    wire [ADDR_WIDTH:0]   wptr_gray_sync;  // wptr_gray 同步到读时钟域的结果
    wire [ADDR_WIDTH:0]   rptr_gray_sync;  // rptr_gray 同步到写时钟域的结果

    // 存储器访问地址（取指针低 ADDR_WIDTH 位，去掉高位溢出标志位）
    wire [ADDR_WIDTH-1:0] waddr, raddr;

    // ---------- 子模块实例化 ----------

    // 双端口存储器：写侧时钟驱动写，读侧异步输出
    // wenc = winc & ~wfull，保证只有在不满时才真正写入
    fifo_mem #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_mem (
        .wclk  (wclk),
        .wenc  (winc & ~wfull),  // 写使能：外部winc有效且FIFO未满
        .waddr (waddr),
        .wdata (wdata),
        .raddr (raddr),
        .rdata (rdata)
    );

    // 写控制器：在写时钟域运行，产生写指针和wfull信号
    write_ctrl #(.ADDR_WIDTH(ADDR_WIDTH)) u_wctrl (
        .wclk           (wclk),
        .wrst_n         (wrst_n),
        .winc           (winc),
        .rptr_gray_sync (rptr_gray_sync), // 来自同步器：读指针的同步值
        .wptr           (wptr),
        .wptr_gray      (wptr_gray),
        .waddr          (waddr),
        .wfull          (wfull)
    );

    // 读控制器：在读时钟域运行，产生读指针和rempty信号
    read_ctrl #(.ADDR_WIDTH(ADDR_WIDTH)) u_rctrl (
        .rclk           (rclk),
        .rrst_n         (rrst_n),
        .rinc           (rinc),
        .wptr_gray_sync (wptr_gray_sync), // 来自同步器：写指针的同步值
        .rptr           (rptr),
        .rptr_gray      (rptr_gray),
        .raddr          (raddr),
        .rempty         (rempty)
    );

    // 写→读同步器：将写指针格雷码从写时钟域同步到读时钟域
    // 用于读控制器判断FIFO是否为空
    sync_w2r #(.ADDR_WIDTH(ADDR_WIDTH)) u_sw2r (
        .wptr_gray      (wptr_gray),
        .rclk           (rclk),
        .rrst_n         (rrst_n),
        .wptr_gray_sync (wptr_gray_sync)
    );

    // 读→写同步器：将读指针格雷码从读时钟域同步到写时钟域
    // 用于写控制器判断FIFO是否已满
    sync_r2w #(.ADDR_WIDTH(ADDR_WIDTH)) u_sr2w (
        .rptr_gray      (rptr_gray),
        .wclk           (wclk),
        .wrst_n         (wrst_n),
        .rptr_gray_sync (rptr_gray_sync)
    );

endmodule


// ============================================================================
// 子模块：fifo_mem —— 双端口存储器
// ----------------------------------------------------------------------------
// 功能：提供一个简单的同步写、异步读双端口RAM。
//   - 写操作：在 wclk 上升沿，若 wenc 有效，则将 wdata 写入 mem[waddr]
//   - 读操作：组合逻辑直接输出 mem[raddr]，无需时钟
//
// 注意：读写可以同时操作不同地址。若同地址同时读写，读出的是旧数据
//       （先读后写，read-first行为，取决于综合工具）。
// ============================================================================
module fifo_mem #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,  // 写时钟
    input  wire                  wenc,  // 写使能（高有效）
    input  wire [ADDR_WIDTH-1:0] waddr, // 写地址
    input  wire [ADDR_WIDTH-1:0] raddr, // 读地址（异步，无时钟）
    input  wire [DATA_WIDTH-1:0] wdata, // 写数据
    output wire [DATA_WIDTH-1:0] rdata  // 读数据（组合输出）
);
    // FIFO深度 = 2^ADDR_WIDTH
    localparam DEPTH = (1 << ADDR_WIDTH);

    // 存储器阵列：DEPTH 个 DATA_WIDTH 位宽的寄存器
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 仿真初始化：将所有存储单元清零，避免仿真出现 X 态
    integer i;
    initial
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 0;

    // 同步写：wclk 上升沿采样，wenc 为1时写入
    always @(posedge wclk)
        if (wenc) mem[waddr] <= wdata;

    // 异步读：raddr 变化时立即输出，不依赖时钟
    assign rdata = mem[raddr];

endmodule


// ============================================================================
// 子模块：write_ctrl —— 写控制器
// ----------------------------------------------------------------------------
// 功能：
//   1. 维护二进制写指针 wptr（复位为0，每次有效写操作自增1）
//   2. 计算并输出写地址 waddr（取 wptr 低 ADDR_WIDTH 位）
//   3. 将 wptr 转换为格雷码 wptr_gray，用于跨时钟域同步
//   4. 根据同步过来的读指针格雷码 rptr_gray_sync 判断并输出 wfull 信号
//
// 满条件（Full Condition）分析：
//   写指针格雷码下一拍值（wptr_gray_next）与同步后读指针格雷码（rptr_gray_sync）满足：
//     - 最高位（bit[N]）不同      → 表示写指针比读指针多绕了一圈
//     - 次高位（bit[N-1]）不同    → 格雷码满条件的必要组成
//     - 其余低位（bit[N-2:0]）相同 → 指向同一存储位置
//   三个条件同时成立，说明写指针已追上读指针，FIFO满。
//
// 注意：wfull 在写时钟域注册，是保守判断（可能稍晚反映真实满状态），
//       但不会导致数据溢出，只会暂时阻止合法写入（功能安全）。
// ============================================================================
module write_ctrl #(parameter ADDR_WIDTH = 4) (
    input  wire                  wclk,          // 写时钟
    input  wire                  wrst_n,         // 写侧复位（低有效）
    input  wire                  winc,           // 外部写使能
    input  wire [ADDR_WIDTH:0]   rptr_gray_sync, // 同步后的读指针格雷码（来自写时钟域）
    output reg  [ADDR_WIDTH:0]   wptr,           // 二进制写指针（当前值）
    output wire [ADDR_WIDTH:0]   wptr_gray,      // 写指针格雷码（用于跨域同步）
    output wire [ADDR_WIDTH-1:0] waddr,          // 写地址（送存储器）
    output reg                   wfull           // FIFO满标志
);
    // ---------- 下一拍写指针计算 ----------
    // 只有在写使能有效且FIFO不满时，指针才自增
    wire [ADDR_WIDTH:0] wptr_next = wptr + (winc & ~wfull);

    // 二进制转格雷码：gray = bin ^ (bin >> 1)
    // 格雷码相邻值只有1位不同，跨时钟域采样时即使发生亚稳态，
    // 最多偏差1个计数值，不会跳变到任意错误值
    wire [ADDR_WIDTH:0] wptr_gray_next = wptr_next ^ (wptr_next >> 1);

    // ---------- 满条件判断逻辑 ----------
    // 格雷码满条件：最高两位反相，其余低位相同
    wire wfull_next =
        (wptr_gray_next[ADDR_WIDTH]     != rptr_gray_sync[ADDR_WIDTH]    ) &&  // 最高位相反
        (wptr_gray_next[ADDR_WIDTH-1]   != rptr_gray_sync[ADDR_WIDTH-1]  ) &&  // 次高位相反
        (wptr_gray_next[ADDR_WIDTH-2:0] == rptr_gray_sync[ADDR_WIDTH-2:0]);    // 低位全部相同

    // ---------- 输出赋值 ----------
    // 写地址：取指针低位，去掉最高位（最高位仅用于满/空判断）
    assign waddr     = wptr[ADDR_WIDTH-1:0];

    // 当前写指针的格雷码（直接组合输出，供同步器采样）
    assign wptr_gray = wptr ^ (wptr >> 1);

    // ---------- 寄存器更新 ----------
    // 写指针和满标志在写时钟域更新
    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n)
            {wptr, wfull} <= 0;          // 复位：写指针清零，满标志清零
        else begin
            wptr  <= wptr_next;          // 更新写指针
            wfull <= wfull_next;         // 更新满标志
        end

endmodule


// ============================================================================
// 子模块：read_ctrl —— 读控制器
// ----------------------------------------------------------------------------
// 功能：
//   1. 维护二进制读指针 rptr（复位为0，每次有效读操作自增1）
//   2. 计算并输出读地址 raddr（取 rptr 低 ADDR_WIDTH 位）
//   3. 将 rptr 转换为格雷码 rptr_gray，用于跨时钟域同步
//   4. 根据同步过来的写指针格雷码 wptr_gray_sync 判断并输出 rempty 信号
//
// 空条件（Empty Condition）分析：
//   当读指针格雷码下一拍值（rptr_gray_next）等于同步后写指针格雷码
//   （wptr_gray_sync）时，说明读指针已追上写指针，FIFO为空。
//   相等判断在格雷码域直接进行，无需转回二进制。
//
// 注意：rempty 在读时钟域注册，同样是保守判断。复位时 rempty=1（初始为空）。
// ============================================================================
module read_ctrl #(parameter ADDR_WIDTH = 4) (
    input  wire                  rclk,          // 读时钟
    input  wire                  rrst_n,         // 读侧复位（低有效）
    input  wire                  rinc,           // 外部读使能
    input  wire [ADDR_WIDTH:0]   wptr_gray_sync, // 同步后的写指针格雷码（来自读时钟域）
    output reg  [ADDR_WIDTH:0]   rptr,           // 二进制读指针（当前值）
    output wire [ADDR_WIDTH:0]   rptr_gray,      // 读指针格雷码（用于跨域同步）
    output wire [ADDR_WIDTH-1:0] raddr,          // 读地址（送存储器）
    output reg                   rempty          // FIFO空标志
);
    // ---------- 下一拍读指针计算 ----------
    // 只有在读使能有效且FIFO不空时，指针才自增
    wire [ADDR_WIDTH:0] rptr_next = rptr + (rinc & ~rempty);

    // 二进制转格雷码
    wire [ADDR_WIDTH:0] rptr_gray_next = rptr_next ^ (rptr_next >> 1);

    // ---------- 空条件判断逻辑 ----------
    // 读指针格雷码下一拍 == 同步后的写指针格雷码，则下一拍为空
    wire rempty_next = (rptr_gray_next == wptr_gray_sync);

    // ---------- 输出赋值 ----------
    // 读地址：取指针低位
    assign raddr     = rptr[ADDR_WIDTH-1:0];

    // 当前读指针的格雷码（直接组合输出，供同步器采样）
    assign rptr_gray = rptr ^ (rptr >> 1);

    // ---------- 寄存器更新 ----------
    // 读指针和空标志在读时钟域更新
    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n)
            {rptr, rempty} <= {0, 1'b1}; // 复位：读指针清零，空标志置1（初始为空）
        else begin
            rptr   <= rptr_next;          // 更新读指针
            rempty <= rempty_next;        // 更新空标志
        end

endmodule


// ============================================================================
// 子模块：sync_w2r —— 写→读跨时钟域同步器（双触发器）
// ----------------------------------------------------------------------------
// 功能：将写指针格雷码（wptr_gray）从写时钟域安全同步到读时钟域。
//
// 工作原理（2FF Synchronizer）：
//   - ff1（第一级触发器）：在读时钟 rclk 上升沿采样 wptr_gray
//     → 此级输出可能处于亚稳态（建立/保持时间不满足）
//   - wptr_gray_sync（第二级触发器）：再次在 rclk 上升沿采样 ff1
//     → 经过一个完整读时钟周期后，亚稳态概率大幅降低，输出稳定
//
// 为何用格雷码而非二进制码：
//   二进制指针多位同时跳变（如 0111→1000 有4位变化），若采样时序不对，
//   可能采到任意中间状态（如 1111），导致指针严重错误。
//   格雷码相邻只有1位变化，即使亚稳态，最坏偏差仅1个计数值，安全可控。
//
// 复位行为：异步复位时同步器清零，与读时钟域其他逻辑保持一致。
// ============================================================================
module sync_w2r #(parameter ADDR_WIDTH = 4) (
    input  wire [ADDR_WIDTH:0] wptr_gray,      // 写时钟域的写指针格雷码（源信号）
    input  wire                rclk,           // 读时钟（目标时钟域）
    input  wire                rrst_n,          // 读侧复位（低有效）
    output reg  [ADDR_WIDTH:0] wptr_gray_sync  // 同步后的写指针格雷码（读时钟域稳定输出）
);
    reg [ADDR_WIDTH:0] ff1; // 第一级同步触发器（用于消除亚稳态的中间级）

    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n)
            {ff1, wptr_gray_sync} <= 0;   // 复位：两级触发器全部清零
        else begin
            ff1           <= wptr_gray;   // 第一级：采样源信号（可能短暂亚稳态）
            wptr_gray_sync <= ff1;        // 第二级：采样稳定后的第一级输出
        end

endmodule


// ============================================================================
// 子模块：sync_r2w —— 读→写跨时钟域同步器（双触发器）
// ----------------------------------------------------------------------------
// 功能：将读指针格雷码（rptr_gray）从读时钟域安全同步到写时钟域。
//
// 工作原理与 sync_w2r 完全对称，只是目标时钟域改为写时钟域（wclk）。
//   - ff1：在 wclk 上升沿采样 rptr_gray（第一级，可能亚稳态）
//   - rptr_gray_sync：在 wclk 上升沿再次采样（第二级，稳定输出）
//
// 同步后的 rptr_gray_sync 提供给写控制器，用于判断 wfull 信号。
// 由于多了2个时钟周期延迟，写控制器看到的是"稍旧"的读指针，
// 这使得 wfull 判断偏保守（实际未满时可能短暂认为满），但绝不会误判未满，
// 从而保证不会写入已被读指针占用的存储空间，设计上是安全的。
// ============================================================================
module sync_r2w #(parameter ADDR_WIDTH = 4) (
    input  wire [ADDR_WIDTH:0] rptr_gray,      // 读时钟域的读指针格雷码（源信号）
    input  wire                wclk,           // 写时钟（目标时钟域）
    input  wire                wrst_n,          // 写侧复位（低有效）
    output reg  [ADDR_WIDTH:0] rptr_gray_sync  // 同步后的读指针格雷码（写时钟域稳定输出）
);
    reg [ADDR_WIDTH:0] ff1; // 第一级同步触发器

    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n)
            {ff1, rptr_gray_sync} <= 0;   // 复位：两级触发器全部清零
        else begin
            ff1           <= rptr_gray;   // 第一级：采样读指针格雷码
            rptr_gray_sync <= ff1;        // 第二级：输出稳定的同步值
        end

endmodule
