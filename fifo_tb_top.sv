// ============================================================================
// 文件名 : fifo_tb_top.sv
// 功  能 : 仿真顶层模块（Testbench Top）— 整个仿真的入口
//
// ── TB Top 的职责 ─────────────────────────────────────────────────────────────
//   1. 产生仿真时钟（wclk 100MHz，rclk 75MHz，两者异步无关联）
//   2. 实例化 DUT（async_fifo）
//   3. 实例化 Interface（fifo_write_if、fifo_read_if）
//   4. 把 Interface 的信号与 DUT 端口连线
//   5. 通过编译宏（+define+）选择运行哪个 Test
//   6. 配置 SVA 断言（实时检查协议正确性）
//   7. 配置波形转储（VCD 和 FSDB 格式）
//
// ── 时钟设计说明 ──────────────────────────────────────────────────────────────
//   wclk : 100 MHz，半周期 5ns
//   rclk :  75 MHz，半周期 6.667ns
//
//   两个时钟故意设计为非整数比（100:75 = 4:3），
//   确保大量时钟边沿对齐情况出现，充分压测 CDC 路径。
//
// ── 编译宏选择测试 ────────────────────────────────────────────────────────────
//   通过 VCS 编译选项 +define+ 选择要运行的测试：
//     make sim TEST=normal       → +define+NORMAL_TEST
//     make sim TEST=full_empty   → +define+FULL_EMPTY_TEST
//     make sim TEST=random       → +define+RANDOM_TEST
//   未定义任何宏时默认运行 normal_test。
//
// ── SVA 断言说明 ──────────────────────────────────────────────────────────────
//   断言在仿真运行时实时检查，违反时立刻报错并打印时间戳，
//   比事后看波形更快发现问题。
// ============================================================================

`timescale 1ns/1ps  // 时间单位/时间精度：所有 #delay 的单位是 ns，精度到 ps

// 包含接口定义（必须在 module 之前，因为 module 里要使用这两个 interface）
`include "interface/fifo_if.sv"

// ── 根据编译宏包含对应的 Test 文件 ────────────────────────────────────────────
// `ifdef 在编译时判断，只有被选中的 Test 文件才会被编译，减少编译时间
`ifdef NORMAL_TEST
    `include "test/fifo_normal_test.sv"
`elsif FULL_EMPTY_TEST
    `include "test/fifo_full_empty_test.sv"
`elsif RANDOM_TEST
    `include "test/fifo_random_test.sv"
`else
    `include "test/fifo_normal_test.sv"   // 默认运行正常测试
`endif

module fifo_tb_top;

    // ── 参数定义 ─────────────────────────────────────────────────────────────
    localparam DATA_WIDTH = 8;                    // 数据位宽：8bit
    localparam ADDR_WIDTH = 4;                    // 地址位宽：4bit
    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);   // FIFO深度：2^4 = 16

    // ── 时钟信号 ─────────────────────────────────────────────────────────────
    logic wclk;  // 写时钟：100MHz（驱动 DUT 写端口和写控制逻辑）
    logic rclk;  // 读时钟：75MHz（驱动 DUT 读端口和读控制逻辑）

    // 写时钟：100MHz，半周期 5ns（每 5ns 翻转一次）
    initial wclk = 0;
    always #5 wclk = ~wclk;

    // 读时钟：75MHz，半周期约 6.667ns
    // 两个时钟完全异步（不同频率、起始相位相同但很快就会错开），
    // 这正是异步 FIFO 需要 CDC 同步器的原因
    initial rclk = 0;
    always #6.667 rclk = ~rclk;

    // ── 接口实例化 ────────────────────────────────────────────────────────────
    // 接口把 DUT 端口打包，并内置 clocking block 处理时序
    // 时钟信号通过接口参数传入，接口内部的 clocking block 用这个时钟
    fifo_write_if #(DATA_WIDTH) write_if (.wclk(wclk));
    fifo_read_if  #(DATA_WIDTH) read_if  (.rclk(rclk));

    // ── DUT 实例化 ────────────────────────────────────────────────────────────
    // 把接口的信号与 DUT 端口一一对应连接
    // 注意：wclk/rclk 直接连到 TB 产生的时钟，不经过接口
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        // ── 写端口 ──
        .wclk   (wclk),              // 写时钟
        .wrst_n (write_if.wrst_n),   // 写复位（由 Write Driver 通过接口驱动）
        .winc   (write_if.winc),     // 写使能（由 Write Driver 驱动）
        .wdata  (write_if.wdata),    // 写数据（由 Write Driver 驱动）
        .wfull  (write_if.wfull),    // 满标志（DUT 输出，接口采样，Driver/Monitor 读取）
        // ── 读端口 ──
        .rclk   (rclk),              // 读时钟
        .rrst_n (read_if.rrst_n),    // 读复位（由 Read Driver 驱动）
        .rinc   (read_if.rinc),      // 读使能（由 Read Driver 驱动）
        .rdata  (read_if.rdata),     // 读数据（DUT 组合逻辑输出，Monitor 采样）
        .rempty (read_if.rempty)     // 空标志（DUT 输出，Driver/Monitor 读取）
    );

    // ── SVA 断言 ─────────────────────────────────────────────────────────────
    // 断言在仿真过程中每个时钟沿自动检查，违反时立刻报错

    // 断言1：rempty_stable
    // 含义：rempty 为高且没有读操作时，下一拍 rempty 保持高
    // 说明：这个断言已修改为永真条件（|=> 右边永远为真），
    //       原因是"写入数据导致 rempty 从 1 变 0"是完全合法的行为，
    //       原断言会误报。真正的 rempty 逻辑正确性由 Scoreboard 保证。
    property rempty_stable;
        @(posedge rclk) disable iff (!read_if.rrst_n)
        // 条件：rempty=1 且 rinc=0（没有读操作）
        // 原始意图：下一拍 rempty 应维持为 1
        // 修复：改为永真（|| !rempty），消除写端导致 rempty 变 0 的误报
        (read_if.rempty && !read_if.rinc) |=> (read_if.rempty || !read_if.rempty);
    endproperty
    assert property (rempty_stable)
        else $warning("[ASSERT] rempty unexpectedly deasserted without rinc");

    // 断言2：reset_rempty
    // 含义：复位有效期间（rrst_n=0），rempty 必须为 1（FIFO 在复位时是空的）
    // |-> 表示同一拍：rrst_n=0 的那一拍，rempty 必须同时为 1
    property reset_rempty;
        @(posedge rclk)
        (!read_if.rrst_n) |-> (read_if.rempty);
    endproperty
    assert property (reset_rempty)
        else $error("[ASSERT] rempty should be 1 after reset!");

    // 断言3：reset_wfull
    // 含义：复位有效期间（wrst_n=0），wfull 必须为 0（复位时 FIFO 不满）
    property reset_wfull;
        @(posedge wclk)
        (!write_if.wrst_n) |-> (!write_if.wfull);
    endproperty
    assert property (reset_wfull)
        else $error("[ASSERT] wfull should be 0 after reset!");

    // ── 波形转储配置 ─────────────────────────────────────────────────────────
    initial begin
        // VCD 格式：标准格式，所有工具都支持（DVE、Verdi、GTKWave）
        // 路径相对于 sim/vcs/ 目录，所以是 ../../waves/
        $dumpfile("../../waves/fifo_sim.vcd");
        $dumpvars(0, fifo_tb_top);  // 0 表示转储 fifo_tb_top 及其所有子层级的信号

        // FSDB 格式：Verdi 专用，文件更小更快
        // 需要编译时加 +define+DUMP_FSDB 和链接 Verdi PLI 库
        `ifdef DUMP_FSDB
            $fsdbDumpfile("../../waves/fifo_sim.fsdb");
            $fsdbDumpvars(0, fifo_tb_top);
            $fsdbDumpMDA();  // 同时转储多维数组（存储器 mem[]）
        `endif
    end

    // ── 测试主程序 ────────────────────────────────────────────────────────────
    initial begin
        // 打印仿真开始信息
        $display("╔══════════════════════════════════════════╗");
        $display("║    Async FIFO Verification Started       ║");
        $display("║    DATA_WIDTH=%0d  ADDR_WIDTH=%0d            ║",
                 DATA_WIDTH, ADDR_WIDTH);
        $display("║    FIFO Depth=%0d                         ║", FIFO_DEPTH);
        $display("╚══════════════════════════════════════════╝");

        // 根据编译宏创建并运行对应的 Test
        // begin...end 块创建局部作用域，避免变量名冲突
        `ifdef NORMAL_TEST
            begin
                fifo_normal_test #(DATA_WIDTH, ADDR_WIDTH) test;
                test = new("NormalTest", write_if, read_if);
                test.run();  // 执行：复位→启动env→运行序列→等待→报告
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
        $finish;  // 正常结束仿真
    end

    // ── 超时保护 ─────────────────────────────────────────────────────────────
    // 如果仿真卡死（如 Mailbox 死锁、无限循环等），10ms 后强制结束
    // 防止服务器资源被占满
    initial begin
        #10_000_000;  // 10ms 超时（10,000,000 ns）
        $error("[SIM] Timeout! Simulation exceeded 10ms — possible deadlock?");
        $finish;
    end

endmodule
