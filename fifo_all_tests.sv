// ============================================================================
// 文件名 : fifo_base_test.sv
// 功  能 : 基础测试类（Base Test）— 所有测试的公共基类
//
// ── 测试类的职责 ──────────────────────────────────────────────────────────────
//   Test 是验证平台的最顶层控制者，它决定"怎么测"：
//   1. 创建并初始化验证环境（env）
//   2. 控制复位时序
//   3. 选择并运行测试序列（run_sequences）
//   4. 等待所有事务完成后打印验证报告
//
// ── 基类 + 继承的设计模式 ────────────────────────────────────────────────────
//   fifo_base_test 定义通用流程（reset→run→sequences→report）
//   各个子类（normal/full_empty/random）只需重写 run_sequences()，
//   不需要重复编写复位、等待、报告等代码，符合 DRY 原则。
//
//   virtual task run_sequences() 是"模板方法"：
//     基类提供默认实现，子类可以覆盖（override）
// ============================================================================

`include "../env/fifo_env.sv"
`include "../sequence/fifo_sequence.sv"

class fifo_base_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4);

    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);  // 2^4 = 16

    fifo_env #(DATA_WIDTH) env;  // 验证环境实例

    string name;

    // 虚接口（由 TB Top 在实例化 Test 时传入）
    virtual fifo_write_if #(DATA_WIDTH) w_vif;
    virtual fifo_read_if  #(DATA_WIDTH) r_vif;

    // ── 构造函数 ─────────────────────────────────────────────────────────────
    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) w_vif,
        virtual fifo_read_if  #(DATA_WIDTH) r_vif
    );
        this.name  = name;
        this.w_vif = w_vif;
        this.r_vif = r_vif;
        // 创建验证环境，把接口传进去
        env = new("env", w_vif, r_vif);
    endfunction

    // ── 测试主流程（模板方法）────────────────────────────────────────────────
    // 子类不重写这个方法，保持统一的测试流程
    virtual task run();
        $display("\n========================================");
        $display("  Test: %s", name);
        $display("========================================\n");

        // Step 1：执行复位（写端和读端并行复位）
        env.reset();

        // Step 2：启动环境（所有 Driver/Monitor/Scoreboard 后台 fork 运行）
        env.run();

        // Step 3：执行测试激励（调用子类重写的 run_sequences）
        run_sequences();

        // Step 4：等待所有事务完成
        // 2000ns 足够所有 Transaction 在 DUT 中传播完成
        // 实际项目中可以用 mailbox.size()==0 来判断更精确
        #2000;

        // Step 5：打印验证结果报告
        env.report();
    endtask

    // ── 默认测试序列（子类应重写此方法）─────────────────────────────────────
    // virtual 关键字允许子类用 override 覆盖
    virtual task run_sequences();
        fifo_write_seq #(DATA_WIDTH) wr_seq;
        fifo_read_seq  #(DATA_WIDTH) rd_seq;

        // 默认：写 8 个，等 100ns，读 8 个
        wr_seq = new("wr_seq", env.wr_drv_mbx, 8);
        rd_seq = new("rd_seq", env.rd_drv_mbx, 8);

        wr_seq.run();
        #100;
        rd_seq.run();
    endtask

endclass : fifo_base_test


// ============================================================================
// 文件名 : fifo_normal_test.sv
// 功  能 : 正常功能测试
//
// 测试场景：
//   1. 先写入 8 个随机数据（顺序写）
//   2. 等待 500ns（让数据在 CDC 两级同步器中传播完）
//   3. 再读出 8 个数据
//
// 验证目标：
//   - 读出顺序与写入顺序完全一致（FIFO 先进先出特性）
//   - CDC 同步链路工作正常（写指针能正确传递到读时钟域）
//   - Scoreboard 全部 PASS
// ============================================================================
`include "fifo_base_test.sv"

class fifo_normal_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4)
    extends fifo_base_test #(DATA_WIDTH, ADDR_WIDTH);  // 继承基类

    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) w_vif,
        virtual fifo_read_if  #(DATA_WIDTH) r_vif
    );
        // super.new 调用基类构造函数
        super.new(name, w_vif, r_vif);
    endfunction

    // 重写 run_sequences：先写后读
    virtual task run_sequences();
        fifo_write_seq #(DATA_WIDTH) wr_seq;
        fifo_read_seq  #(DATA_WIDTH) rd_seq;

        $display("[%s] Normal Test: write 8, then read 8", name);

        wr_seq = new("wr_seq", env.wr_drv_mbx, 8);
        rd_seq = new("rd_seq", env.rd_drv_mbx, 8);

        wr_seq.run();   // 先完成所有写操作
        #500;           // 等待写指针经过 2FF 同步器传播到读时钟域（至少 2 个读时钟周期）
        rd_seq.run();   // 再执行所有读操作
    endtask

endclass : fifo_normal_test


// ============================================================================
// 文件名 : fifo_full_empty_test.sv
// 功  能 : 满/空边界测试
//
// 测试场景：
//   1. 写满 FIFO（写 fifo_depth+2 个数据，后 2 个会被 wfull 保护拦截）
//   2. 等待 1000ns（让 CDC 同步稳定）
//   3. 读空 FIFO（读 fifo_depth+2 个，后 2 个会被 rempty 保护拦截）
//
// 验证目标：
//   - wfull 信号在正确时机拉高（第 16 个数据写入后）
//   - wfull=1 时 DUT 拒绝新写入（数据不被覆盖）
//   - rempty 信号在正确时机拉高
//   - rempty=1 时 DUT 拒绝读出（不产生垃圾数据）
//   - Scoreboard 中 16 笔数据全部 PASS
// ============================================================================
`include "fifo_base_test.sv"

class fifo_full_empty_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4)
    extends fifo_base_test #(DATA_WIDTH, ADDR_WIDTH);

    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) w_vif,
        virtual fifo_read_if  #(DATA_WIDTH) r_vif
    );
        super.new(name, w_vif, r_vif);
    endfunction

    virtual task run_sequences();
        fifo_full_seq  #(DATA_WIDTH) full_seq;
        fifo_empty_seq #(DATA_WIDTH) empty_seq;

        $display("[%s] Full/Empty Test: fill then drain", name);

        // 写满 FIFO
        full_seq = new("full_seq", env.wr_drv_mbx, FIFO_DEPTH);
        full_seq.run();

        #1000; // 等待满标志经过同步器传播

        // 读空 FIFO
        empty_seq = new("empty_seq", env.rd_drv_mbx, FIFO_DEPTH);
        empty_seq.run();
    endtask

endclass : fifo_full_empty_test


// ============================================================================
// 文件名 : fifo_random_test.sv
// 功  能 : 随机并发测试（压力测试）
//
// 测试场景：
//   写和读同时并发进行，共 64 组事务，随机延迟，随机数据
//
// 验证目标：
//   - 在写比读快/读比写快/相近速率三种情况下，数据都正确
//   - FIFO 满时写端能正确暂停，不丢数据
//   - FIFO 空时读端能正确等待，不读垃圾
//   - 跨时钟域同步在长时间并发下不出错
//   - 这是最严格的测试，通过此测试基本可以说明设计正确
// ============================================================================
`include "fifo_base_test.sv"

class fifo_random_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4)
    extends fifo_base_test #(DATA_WIDTH, ADDR_WIDTH);

    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) w_vif,
        virtual fifo_read_if  #(DATA_WIDTH) r_vif
    );
        super.new(name, w_vif, r_vif);
    endfunction

    virtual task run_sequences();
        fifo_back2back_seq #(DATA_WIDTH) b2b_seq;

        $display("[%s] Random Concurrent Test: 64 transactions", name);

        // 使用背靠背序列，同时给写和读 Driver 的 Mailbox 投递事务
        b2b_seq = new("b2b_seq", env.wr_drv_mbx, env.rd_drv_mbx, 64);
        b2b_seq.run();
    endtask

endclass : fifo_random_test
