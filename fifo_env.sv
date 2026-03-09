// ============================================================================
// 文件名 : fifo_env.sv
// 功  能 : 验证环境顶层（Verification Environment）
//
// ── 什么是 Environment ────────────────────────────────────────────────────────
//   Environment 是整个验证平台的"容器"或"骨架"，它：
//   1. 创建所有验证组件（Driver、Monitor、Scoreboard、Coverage）
//   2. 创建组件间通信用的 Mailbox
//   3. 把正确的 Mailbox 分配给正确的组件（连线）
//   4. 提供统一的 run() 接口，Test 只需调用 env.run() 就能启动全部组件
//
// ── 完整数据流图 ──────────────────────────────────────────────────────────────
//
//  [Sequence]──wr_drv_mbx──►[WriteDriver]──►[DUT 写端口]
//  [Sequence]──rd_drv_mbx──►[ReadDriver] ──►[DUT 读端口]
//
//  [DUT 写端口]──►[WriteMonitor]──wr_scb_mbx──►[Scoreboard]──►PASS/FAIL
//  [DUT 读端口]──►[ReadMonitor] ──rd_scb_mbx──►[Scoreboard]
//
//  [WriteMonitor]──wr_cov_mbx──►[Coverage]──►覆盖率报告
//  [ReadMonitor] ──rd_cov_mbx──►[Coverage]
//
// ── Mailbox 命名规则 ─────────────────────────────────────────────────────────
//   wr_drv_mbx : 写 Driver 的输入（Sequence 往这里放写事务）
//   rd_drv_mbx : 读 Driver 的输入（Sequence 往这里放读事务）
//   wr_scb_mbx : 写 Monitor 到 Scoreboard（写操作记录）
//   rd_scb_mbx : 读 Monitor 到 Scoreboard（读操作记录）
//   wr_cov_mbx : 写 Monitor 到 Coverage（写操作记录，用于覆盖率）
//   rd_cov_mbx : 读 Monitor 到 Coverage（读操作记录，用于覆盖率）
// ============================================================================

// `include 把其他文件的内容直接插入到这里
// 编译时按照顺序包含所有依赖文件
`include "fifo_transaction.sv"
`include "fifo_driver.sv"
`include "fifo_monitor.sv"
`include "fifo_scoreboard.sv"
`include "../coverage/fifo_coverage.sv"

class fifo_env #(parameter DATA_WIDTH = 8);

    // ── 验证组件句柄 ─────────────────────────────────────────────────────────
    fifo_write_driver  #(DATA_WIDTH) write_drv;    // 写驱动器
    fifo_read_driver   #(DATA_WIDTH) read_drv;     // 读驱动器
    fifo_write_monitor #(DATA_WIDTH) write_mon;    // 写监测器
    fifo_read_monitor  #(DATA_WIDTH) read_mon;     // 读监测器
    fifo_scoreboard    #(DATA_WIDTH) scoreboard;   // 记分板
    fifo_coverage      #(DATA_WIDTH) coverage;     // 覆盖率收集器

    // ── 通信 Mailbox ─────────────────────────────────────────────────────────
    // Driver 的输入 Mailbox（由 Test/Sequence 向外暴露，Test 通过这里投递激励）
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_drv_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_drv_mbx;

    // Monitor → Scoreboard 的 Mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_scb_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_scb_mbx;

    // Monitor → Coverage 的 Mailbox（实际项目中 Monitor 会 broadcast 到多个 Mailbox）
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_cov_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_cov_mbx;

    // 虚接口句柄（从 TB Top 通过构造函数传入）
    virtual fifo_write_if #(DATA_WIDTH) w_vif;
    virtual fifo_read_if  #(DATA_WIDTH) r_vif;

    string name;

    // ── 构造函数 ─────────────────────────────────────────────────────────────
    // 由 Test 调用：env = new("env", write_if, read_if);
    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) w_vif,
        virtual fifo_read_if  #(DATA_WIDTH) r_vif
    );
        this.name  = name;
        this.w_vif = w_vif;
        this.r_vif = r_vif;
        build();  // 构造完成后立即创建所有子组件
    endfunction

    // ── build：创建所有组件和 Mailbox ─────────────────────────────────────────
    // 类似于 UVM 的 build_phase
    function void build();
        // 创建所有 Mailbox（size=0 表示无限容量，不会阻塞 put）
        wr_drv_mbx = new();
        rd_drv_mbx = new();
        wr_scb_mbx = new();
        rd_scb_mbx = new();
        wr_cov_mbx = new();
        rd_cov_mbx = new();

        // 创建驱动器，传入：名称、虚接口、对应的 Mailbox
        write_drv = new("write_drv", w_vif, wr_drv_mbx);
        read_drv  = new("read_drv",  r_vif, rd_drv_mbx);

        // 创建监测器，传入：名称、虚接口、发往 Scoreboard 的 Mailbox
        write_mon = new("write_mon", w_vif, wr_scb_mbx);
        read_mon  = new("read_mon",  r_vif, rd_scb_mbx);

        // 创建记分板，传入两个接收 Monitor 数据的 Mailbox
        scoreboard = new("scoreboard", wr_scb_mbx, rd_scb_mbx);

        // 创建覆盖率收集器（本项目中简化，Coverage 复用 cov_mbx，
        // 实际项目中 Monitor 应 broadcast 到 scb 和 cov 两个 Mailbox）
        coverage = new("coverage", wr_cov_mbx, rd_cov_mbx);

        $display("[%s] Environment built successfully", name);
    endfunction

    // ── reset：执行复位 ────────────────────────────────────────────────────────
    // fork...join：写复位和读复位并行执行，两者都完成后 reset 才返回
    task reset();
        fork
            write_drv.reset();  // 写时钟域复位
            read_drv.reset();   // 读时钟域复位（两个异步时钟域同时复位）
        join
    endtask

    // ── run：启动所有组件 ─────────────────────────────────────────────────────
    // fork...join_none：所有组件并行后台运行，run() 立即返回
    // join_none 是关键：让所有 forever 循环都在后台独立运行，
    // run() 返回后 Test 可以继续执行 Sequence
    task run();
        $display("[%0t][%s] Environment running...", $time, name);
        fork
            write_drv.run();    // 写驱动器：永久循环，从 Mailbox 取事务并驱动
            read_drv.run();     // 读驱动器：永久循环
            write_mon.run();    // 写监测器：永久循环，监测写端口
            read_mon.run();     // 读监测器：永久循环，监测读端口
            scoreboard.run();   // 记分板：永久循环，比对数据
            // coverage.run();  // 覆盖率（可选启用，需要连接 cov_mbx）
        join_none  // 所有任务后台并行，当前 task 立即返回
    endtask

    // ── report：打印最终报告 ──────────────────────────────────────────────────
    // 在仿真 #2000 等待结束后，由 Test 调用
    function void report();
        scoreboard.report();
        // coverage.report();  // 覆盖率报告（可选）
    endfunction

endclass : fifo_env
