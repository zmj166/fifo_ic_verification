// ============================================================================
// 文件名: fifo_if.sv
// 描述:   异步FIFO的SystemVerilog接口定义
//
// 接口作用:
//   1. 将DUT的所有端口封装成一个接口，简化连接
//   2. 定义clocking block，用于指定信号的采样和驱动时序
//   3. modport约束不同角色（driver/monitor）的访问权限
//
// 说明:
//   由于是异步FIFO，写端和读端使用不同时钟，
//   因此定义了两个独立的接口: fifo_write_if 和 fifo_read_if
// ============================================================================

// ============================================================
// 写端口接口
// ============================================================
interface fifo_write_if #(parameter DATA_WIDTH = 8) (
    input logic wclk   // 写时钟（由TB提供）
);
    logic                  wrst_n; // 写复位
    logic                  winc;   // 写使能
    logic [DATA_WIDTH-1:0] wdata;  // 写数据
    logic                  wfull;  // 满标志（来自DUT）

    // ---- Clocking Block: 驱动端时序 ----
    // 在wclk上升沿后2ns驱动信号，在上升沿前1ns采样
    // 这样可以避免时序竞争（setup/hold violation）
    clocking write_cb @(posedge wclk);
        default input  #1ns;   // 采样时刻：上升沿前1ns
        default output #2ns;   // 驱动时刻：上升沿后2ns

        output wrst_n;
        output winc;
        output wdata;
        input  wfull;
    endclocking

    // ---- Clocking Block: 监测端时序 ----
    clocking write_mon_cb @(posedge wclk);
        default input #1ns;
        input wrst_n, winc, wdata, wfull;
    endclocking

    // ---- modport: 驱动器视角 ----
    modport driver_mp (
        clocking write_cb,
        input    wclk
    );

    // ---- modport: 监测器视角 ----
    modport monitor_mp (
        clocking write_mon_cb,
        input    wclk
    );

    // ---- modport: DUT连接视角 ----
    modport dut_mp (
        input  wclk, wrst_n, winc, wdata,
        output wfull
    );

endinterface : fifo_write_if


// ============================================================
// 读端口接口
// ============================================================
interface fifo_read_if #(parameter DATA_WIDTH = 8) (
    input logic rclk   // 读时钟
);
    logic                  rrst_n; // 读复位
    logic                  rinc;   // 读使能
    logic [DATA_WIDTH-1:0] rdata;  // 读数据（来自DUT）
    logic                  rempty; // 空标志（来自DUT）

    // ---- Clocking Block: 驱动端 ----
    clocking read_cb @(posedge rclk);
        default input  #1ns;
        default output #2ns;

        output rrst_n;
        output rinc;
        input  rdata;
        input  rempty;
    endclocking

    // ---- Clocking Block: 监测端 ----
    clocking read_mon_cb @(posedge rclk);
        default input #1ns;
        input rrst_n, rinc, rdata, rempty;
    endclocking

    // ---- modport ----
    modport driver_mp (
        clocking read_cb,
        input    rclk
    );

    modport monitor_mp (
        clocking read_mon_cb,
        input    rclk
    );

    modport dut_mp (
        input  rclk, rrst_n, rinc,
        output rdata, rempty
    );

endinterface : fifo_read_if
