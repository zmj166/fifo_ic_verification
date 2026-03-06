// ============================================================================
// 文件名: fifo_env.sv
// 描述:   验证环境顶层（Verification Environment）
//
// 功能说明:
//   Environment 是整个验证环境的容器，负责：
//   1. 创建并连接所有验证组件（Driver、Monitor、Scoreboard、Coverage）
//   2. 管理组件之间的通信通道（mailbox）
//   3. 提供统一的run()接口启动所有组件
//
// 验证架构图:
//
//   [Sequence] --wr_drv_mbx--> [WriteDriver] --> [DUT Write Port]
//   [Sequence] --rd_drv_mbx--> [ReadDriver]  --> [DUT Read Port]
//
//   [DUT Write Port] --> [WriteMon] --wr_scb_mbx--> [Scoreboard] --> PASS/FAIL
//   [DUT Read Port]  --> [ReadMon]  --rd_scb_mbx--> [Scoreboard]
//
//   [WriteMon] --wr_cov_mbx--> [Coverage]
//   [ReadMon]  --rd_cov_mbx--> [Coverage]
// ============================================================================

`include "fifo_transaction.sv"
`include "fifo_driver.sv"
`include "fifo_monitor.sv"
`include "fifo_scoreboard.sv"
`include "../coverage/fifo_coverage.sv"

class fifo_env #(parameter DATA_WIDTH = 8);

    // ---- 验证组件 ----
    fifo_write_driver  #(DATA_WIDTH) write_drv;
    fifo_read_driver   #(DATA_WIDTH) read_drv;
    fifo_write_monitor #(DATA_WIDTH) write_mon;
    fifo_read_monitor  #(DATA_WIDTH) read_mon;
    fifo_scoreboard    #(DATA_WIDTH) scoreboard;
    fifo_coverage      #(DATA_WIDTH) coverage;

    // ---- 通信通道（mailbox）----
    // Driver接收激励的mailbox（由Sequence填充）
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_drv_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_drv_mbx;

    // Monitor向Scoreboard发送数据的mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_scb_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_scb_mbx;

    // Monitor向Coverage发送数据的mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_cov_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_cov_mbx;

    // 虚接口句柄
    virtual fifo_write_if #(DATA_WIDTH) w_vif;
    virtual fifo_read_if  #(DATA_WIDTH) r_vif;

    string name;

    // ---- 构造函数 ----
    function new(string name,
                 virtual fifo_write_if #(DATA_WIDTH) w_vif,
                 virtual fifo_read_if  #(DATA_WIDTH) r_vif);
        this.name  = name;
        this.w_vif = w_vif;
        this.r_vif = r_vif;
        build();
    endfunction

    // ---- 创建所有组件和mailbox ----
    function void build();
        // 创建mailbox（size=0表示无限容量）
        wr_drv_mbx = new();
        rd_drv_mbx = new();
        wr_scb_mbx = new();
        rd_scb_mbx = new();
        wr_cov_mbx = new();
        rd_cov_mbx = new();

        // 创建驱动器
        write_drv = new("write_drv", w_vif, wr_drv_mbx);
        read_drv  = new("read_drv",  r_vif, rd_drv_mbx);

        // 创建监测器
        // 注意：monitor需要向scoreboard和coverage各发一份
        // 这里简化处理，monitor直接连接scoreboard
        write_mon = new("write_mon", w_vif, wr_scb_mbx);
        read_mon  = new("read_mon",  r_vif, rd_scb_mbx);

        // 创建记分板
        scoreboard = new("scoreboard", wr_scb_mbx, rd_scb_mbx);

        // 创建覆盖率（这里复用scb_mbx，实际项目中应使用独立通道）
        coverage = new("coverage", wr_cov_mbx, rd_cov_mbx);

        $display("[%s] Environment built successfully", name);
    endfunction

    // ---- 复位 ----
    task reset();
        fork
            write_drv.reset();
            read_drv.reset();
        join
    endtask

    // ---- 启动所有组件 ----
    task run();
        $display("[%0t][%s] Environment running...", $time, name);
        fork
            write_drv.run();
            read_drv.run();
            write_mon.run();
            read_mon.run();
            scoreboard.run();
            // coverage.run();  // 覆盖率采集（可选启用）
        join_none  // 所有组件并行运行，不等待完成
    endtask

    // ---- 最终报告 ----
    function void report();
        scoreboard.report();
        // coverage.report();
    endfunction

endclass : fifo_env
