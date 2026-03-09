// ============================================================================
// 文件名 : fifo_if.sv
// 功  能 : 异步 FIFO 的 SystemVerilog Interface 定义
//
// ── 为什么需要 Interface ──────────────────────────────────────────────────────
//   传统 TB 直接用 wire/reg 连接 DUT，端口众多时连线混乱，且无法复用。
//   Interface 把 DUT 的所有端口打包成一个"总线对象"，并附带：
//     1. Clocking Block：精确定义信号的采样时刻和驱动时刻，消除时序竞争
//     2. modport：限定 Driver/Monitor/DUT 各自只能访问自己该访问的信号
//
// ── Clocking Block 时序说明 ───────────────────────────────────────────────────
//
//   default input  #1ns   ← 在时钟上升沿前 1ns 采样（读取稳定旧值）
//   default output #2ns   ← 在时钟上升沿后 2ns 驱动（新值在下沿前稳定）
//
//   时间轴：
//   ───────────────────────────────────────────────►
//           -1ns    0(上升沿)    +2ns    +10ns(下一个沿)
//            │         │          │         │
//       [采样稳定值]  [时钟沿]  [驱动新值]  [新值稳定，满足setup]
//
// ── 本文件包含两个独立 Interface ─────────────────────────────────────────────
//   fifo_write_if : 写端口（wclk 时钟域）
//   fifo_read_if  : 读端口（rclk 时钟域）
//   两者独立是因为异步 FIFO 的写端和读端时钟不同
// ============================================================================


// ============================================================================
// 接口1：fifo_write_if — 写端口接口
// ============================================================================
interface fifo_write_if #(parameter DATA_WIDTH = 8) (
    input logic wclk   // 写时钟，由 TB Top 提供，接口自身不产生时钟
);
    // ── 信号声明 ──────────────────────────────────────────────────────────────
    logic                  wrst_n; // 写复位（低有效）：由 Write Driver 驱动
    logic                  winc;   // 写使能：由 Write Driver 驱动，高电平有效
    logic [DATA_WIDTH-1:0] wdata;  // 写数据：由 Write Driver 驱动
    logic                  wfull;  // 满标志：由 DUT 驱动，表示 FIFO 已满

    // ── Clocking Block：驱动端时序（Driver 使用）─────────────────────────────
    // write_cb 定义了 Driver 驱动和采样信号的时序，防止时序竞争
    // @(posedge wclk) 表示在 wclk 上升沿对齐
    clocking write_cb @(posedge wclk);
        default input  #1ns;   // 所有 input 信号：在上升沿前 1ns 采样
        default output #2ns;   // 所有 output 信号：在上升沿后 2ns 驱动

        output wrst_n;  // Driver 驱动复位
        output winc;    // Driver 驱动写使能
        output wdata;   // Driver 驱动写数据
        input  wfull;   // Driver 读取满标志（只读，不驱动）
    endclocking

    // ── Clocking Block：监测端时序（Monitor 使用）───────────────────────────
    // write_mon_cb 只包含 input，Monitor 是被动观察者，只采样不驱动
    clocking write_mon_cb @(posedge wclk);
        default input #1ns;  // 在上升沿前 1ns 采样所有信号
        input wrst_n, winc, wdata, wfull;  // Monitor 可以看到所有写端信号
    endclocking

    // ── modport：限制访问权限 ─────────────────────────────────────────────────
    // modport 让编译器检查：Driver 只能用 write_cb，Monitor 只能用 write_mon_cb，
    // 防止 Monitor 意外驱动信号，增强代码安全性

    modport driver_mp (   // Driver 视角：通过 write_cb 访问
        clocking write_cb,
        input    wclk
    );

    modport monitor_mp (  // Monitor 视角：通过 write_mon_cb 访问
        clocking write_mon_cb,
        input    wclk
    );

    modport dut_mp (      // DUT 视角：直接访问物理信号（不经过 clocking block）
        input  wclk, wrst_n, winc, wdata,  // DUT 接收这些信号
        output wfull                        // DUT 输出满标志
    );

endinterface : fifo_write_if


// ============================================================================
// 接口2：fifo_read_if — 读端口接口
// ============================================================================
interface fifo_read_if #(parameter DATA_WIDTH = 8) (
    input logic rclk   // 读时钟，由 TB Top 提供
);
    // ── 信号声明 ──────────────────────────────────────────────────────────────
    logic                  rrst_n; // 读复位（低有效）：由 Read Driver 驱动
    logic                  rinc;   // 读使能：由 Read Driver 驱动，高电平有效
    logic [DATA_WIDTH-1:0] rdata;  // 读数据：由 DUT 驱动（组合逻辑输出）
    logic                  rempty; // 空标志：由 DUT 驱动，表示 FIFO 已空

    // ── Clocking Block：驱动端（Read Driver 使用）────────────────────────────
    clocking read_cb @(posedge rclk);
        default input  #1ns;   // 采样：上升沿前 1ns
        default output #2ns;   // 驱动：上升沿后 2ns

        output rrst_n;  // Driver 驱动复位
        output rinc;    // Driver 驱动读使能
        input  rdata;   // Driver 读取读数据（rinc 有效的同一拍，rdata 已稳定）
        input  rempty;  // Driver 读取空标志
    endclocking

    // ── Clocking Block：监测端（Read Monitor 使用）───────────────────────────
    // 重要说明：rdata 是组合逻辑输出（assign rdata = mem[raddr]），
    // rinc 有效的同一拍上升沿前 1ns，rdata 已经是正确的待读数据。
    // 因此 Monitor 在检测到 rinc=1 的同一拍直接采样 rdata 即可，
    // 不需要再等一拍（等一拍反而会采到下一个数据，导致数据错位！）
    clocking read_mon_cb @(posedge rclk);
        default input #1ns;
        input rrst_n, rinc, rdata, rempty;  // Monitor 监测所有读端信号
    endclocking

    // ── modport ───────────────────────────────────────────────────────────────
    modport driver_mp (
        clocking read_cb,
        input    rclk
    );

    modport monitor_mp (
        clocking read_mon_cb,
        input    rclk
    );

    modport dut_mp (
        input  rclk, rrst_n, rinc,  // DUT 接收读控制信号
        output rdata, rempty         // DUT 输出读数据和空标志
    );

endinterface : fifo_read_if
