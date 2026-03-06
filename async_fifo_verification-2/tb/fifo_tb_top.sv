// ============================================================================
// 文件名: fifo_tb_top.sv
// 描述:   TB顶层模块（Testbench Top）
//
// 功能说明:
//   这是仿真的入口模块，负责：
//   1. 产生写时钟和读时钟（两个独立时钟）
//   2. 实例化DUT（待测设计）
//   3. 实例化接口（interface）
//   4. 将接口与DUT连接
//   5. 通过编译宏(+define+)选择要运行的测试
//
// 时钟配置:
//   写时钟: 100MHz (period=10ns)
//   读时钟:  75MHz (period=13.3ns) - 异步，与写时钟非整数倍关系
// ============================================================================

`timescale 1ns/1ps

// 包含所有接口定义
`include "interface/fifo_if.sv"

// 根据编译时定义选择测试
`ifdef NORMAL_TEST
    `include "test/fifo_normal_test.sv"
`elsif FULL_EMPTY_TEST
    `include "test/fifo_full_empty_test.sv"
`elsif RANDOM_TEST
    `include "test/fifo_random_test.sv"
`else
    `include "test/fifo_normal_test.sv"  // 默认运行正常测试
`endif

module fifo_tb_top;

    // ================================================================
    // 参数定义
    // ================================================================
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 4;
    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);  // 16

    // ================================================================
    // 时钟信号
    // ================================================================
    logic wclk;  // 写时钟 100MHz
    logic rclk;  // 读时钟 75MHz（与写时钟异步）

    // 写时钟：100MHz，周期10ns
    initial wclk = 0;
    always #5 wclk = ~wclk;

    // 读时钟：75MHz，周期约13.33ns（异步于写时钟）
    // 使用不同频率模拟真实异步场景
    initial rclk = 0;
    always #6.667 rclk = ~rclk;

    // ================================================================
    // 接口实例化
    // ================================================================
    fifo_write_if #(DATA_WIDTH) write_if (.wclk(wclk));
    fifo_read_if  #(DATA_WIDTH) read_if  (.rclk(rclk));

    // ================================================================
    // DUT实例化
    // ================================================================
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        // 写端口
        .wclk   (wclk),
        .wrst_n (write_if.wrst_n),
        .winc   (write_if.winc),
        .wdata  (write_if.wdata),
        .wfull  (write_if.wfull),
        // 读端口
        .rclk   (rclk),
        .rrst_n (read_if.rrst_n),
        .rinc   (read_if.rinc),
        .rdata  (read_if.rdata),
        .rempty (read_if.rempty)
    );

    // ================================================================
    // 断言（Assertions）：实时检查协议规则
    // ================================================================

    // 断言1：wfull有效时写入不应改变存储内容
    // (这里做简单的接口协议检查)

    // 断言2：rempty有效时rdata应保持不变
    property rempty_stable;
        @(posedge rclk) disable iff (!read_if.rrst_n)
        (read_if.rempty && !read_if.rinc) |=> (read_if.rempty);
    endproperty
    assert property (rempty_stable)
        else $warning("[ASSERT] rempty unexpectedly deasserted without rinc");

    // 断言3：复位后rempty应为1
    property reset_rempty;
        @(posedge rclk)
        (!read_if.rrst_n) |-> (read_if.rempty);
    endproperty
    assert property (reset_rempty)
        else $error("[ASSERT] rempty should be 1 after reset!");

    // 断言4：复位后wfull应为0
    property reset_wfull;
        @(posedge wclk)
        (!write_if.wrst_n) |-> (!write_if.wfull);
    endproperty
    assert property (reset_wfull)
        else $error("[ASSERT] wfull should be 0 after reset!");

    // ================================================================
    // 波形转储（VCD / FSDB）
    // ================================================================
    initial begin
        // VCD格式（所有工具支持）
        $dumpfile("waves/fifo_sim.vcd");
        $dumpvars(0, fifo_tb_top);

        // FSDB格式（Verdi专用，需要fsdb dumper）
        `ifdef DUMP_FSDB
            $fsdbDumpfile("waves/fifo_sim.fsdb");
            $fsdbDumpvars(0, fifo_tb_top);
            $fsdbDumpMDA(); // 转储存储器
        `endif
    end

    // ================================================================
    // 测试主程序
    // ================================================================
    initial begin
        // 打印仿真信息
        $display("╔══════════════════════════════════════════╗");
        $display("║    Async FIFO Verification Started       ║");
        $display("║    DATA_WIDTH=%0d  ADDR_WIDTH=%0d            ║",
                 DATA_WIDTH, ADDR_WIDTH);
        $display("║    FIFO Depth=%0d                         ║", FIFO_DEPTH);
        $display("╚══════════════════════════════════════════╝");

        // 选择测试
        `ifdef NORMAL_TEST
            begin
                fifo_normal_test #(DATA_WIDTH, ADDR_WIDTH) test;
                test = new("NormalTest", write_if, read_if);
                test.run();
            end
        `elsif FULL_EMPTY_TEST
            begin
                fifo_full_empty_test #(DATA_WIDTH, ADDR_WIDTH) test;
                test = new("FullEmptyTest", write_if, read_if);
                test.run();
            end
        `elsif RANDOM_TEST
            begin
                fifo_random_test #(DATA_WIDTH, ADDR_WIDTH) test;
                test = new("RandomTest", write_if, read_if);
                test.run();
            end
        `else
            begin
                fifo_normal_test #(DATA_WIDTH, ADDR_WIDTH) test;
                test = new("NormalTest", write_if, read_if);
                test.run();
            end
        `endif

        $display("\n[SIM] Simulation completed!");
        $finish;
    end

    // 超时保护：10ms内必须完成
    initial begin
        #10_000_000;
        $error("[SIM] Timeout! Simulation exceeded 10ms");
        $finish;
    end

endmodule
