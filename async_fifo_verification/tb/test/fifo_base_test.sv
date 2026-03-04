// ============================================================================
// 文件名: fifo_base_test.sv
// 描述:   基础测试类（Base Test）
//
// 功能说明:
//   Test 是验证的最顶层控制，负责：
//   1. 创建并配置验证环境
//   2. 选择和运行测试序列
//   3. 控制仿真结束时机
//
//   基础测试类作为所有测试的基类，定义通用流程
// ============================================================================

`include "../env/fifo_env.sv"
`include "../sequence/fifo_sequence.sv"

class fifo_base_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4);

    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);

    fifo_env #(DATA_WIDTH) env;
    string name;

    // 虚接口（从TB顶层传入）
    virtual fifo_write_if #(DATA_WIDTH) w_vif;
    virtual fifo_read_if  #(DATA_WIDTH) r_vif;

    function new(string name,
                 virtual fifo_write_if #(DATA_WIDTH) w_vif,
                 virtual fifo_read_if  #(DATA_WIDTH) r_vif);
        this.name  = name;
        this.w_vif = w_vif;
        this.r_vif = r_vif;
        env = new("env", w_vif, r_vif);
    endfunction

    // ---- 测试主流程 ----
    virtual task run();
        $display("\n========================================");
        $display("  Test: %s", name);
        $display("========================================\n");

        // 步骤1：复位
        env.reset();

        // 步骤2：启动环境（所有Monitor、Scoreboard后台运行）
        env.run();

        // 步骤3：执行测试体（子类实现）
        run_sequences();

        // 步骤4：等待所有事务完成
        #2000;

        // 步骤5：打印报告
        env.report();
    endtask

    // 子类重写此方法实现不同测试场景
    virtual task run_sequences();
        // 基类默认：基本写读
        fifo_write_seq #(DATA_WIDTH) wr_seq;
        fifo_read_seq  #(DATA_WIDTH) rd_seq;

        wr_seq = new("wr_seq", env.wr_drv_mbx, 8);
        rd_seq = new("rd_seq", env.rd_drv_mbx, 8);

        wr_seq.run();
        #100;
        rd_seq.run();
    endtask

endclass : fifo_base_test
