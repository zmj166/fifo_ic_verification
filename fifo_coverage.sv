// ============================================================================
// 文件名 : fifo_coverage.sv
// 功  能 : 功能覆盖率模型（Functional Coverage Model）
//
// ── 功能覆盖率 vs 代码覆盖率 ─────────────────────────────────────────────────
//   代码覆盖率（由工具自动收集）：
//     测量哪些代码行/分支/翻转被执行——回答"代码有没有跑到"
//
//   功能覆盖率（由验证工程师手写）：
//     测量哪些功能场景被测试——回答"感兴趣的情况有没有覆盖到"
//     例如：有没有测试过"FIFO 满时继续写"？"数据值为0的边界"？
//
//   两者结合才能证明验证充分：代码跑到了，功能点也都覆盖了。
//
// ── 关键概念 ─────────────────────────────────────────────────────────────────
//   covergroup : 覆盖率组，把相关的覆盖点放在一起
//   coverpoint : 定义需要统计的信号/表达式
//   bins       : 把取值范围划分成若干"桶"，每个桶被触发一次就算覆盖
//   cross      : 交叉覆盖，统计两个 coverpoint 的所有组合
//
//   sample()   : 触发一次采样，更新覆盖率统计
//   get_coverage() : 返回当前覆盖率百分比（0.0~100.0）
//
// ── 本覆盖率模型包含 ─────────────────────────────────────────────────────────
//   write_cg : 写端覆盖率（写数据范围 × 满状态）
//   read_cg  : 读端覆盖率（读数据范围 × 空状态）
// ============================================================================

class fifo_coverage #(parameter DATA_WIDTH = 8);

    // 从写/读 Monitor 接收 Transaction 的 Mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_cov_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_cov_mbx;

    // 当前正在处理的 Transaction（covergroup 采样时直接访问这两个变量）
    fifo_transaction #(DATA_WIDTH) wr_trans;
    fifo_transaction #(DATA_WIDTH) rd_trans;

    // ── 写端覆盖率组 ─────────────────────────────────────────────────────────
    covergroup write_cg;

        // 覆盖写数据的不同范围
        // 目标：验证各种数值的数据都被测试过（边界值、中间值）
        cp_wdata: coverpoint wr_trans.data {
            bins zero       = {0};                       // 边界：全0
            bins max_val    = {(1<<DATA_WIDTH)-1};       // 边界：全F（255）
            bins low_range  = {[1   : 63]};              // 低值区（1~63）
            bins mid_range  = {[64  : 191]};             // 中值区（64~191）
            bins high_range = {[192 : 254]};             // 高值区（192~254）
        }

        // 覆盖写入时 FIFO 的满状态
        // 目标：确保既测试了正常写（not_full），也测试了满时写（full）
        cp_wfull: coverpoint wr_trans.full {
            bins not_full = {0};  // 正常写入（FIFO 不满）
            bins full     = {1};  // 满时写入（DUT 应忽略，wfull 保护测试）
        }

        // 交叉覆盖：验证"在各种满/非满状态下，各种数据值都出现过"
        // 共 5×2=10 个组合，每个组合都被触发才算 100% 交叉覆盖
        cx_data_full: cross cp_wdata, cp_wfull;

    endgroup

    // ── 读端覆盖率组 ─────────────────────────────────────────────────────────
    covergroup read_cg;

        // 覆盖读出数据的范围（与写端对称）
        cp_rdata: coverpoint rd_trans.data {
            bins zero       = {0};
            bins max_val    = {(1<<DATA_WIDTH)-1};
            bins low_range  = {[1   : 63]};
            bins mid_range  = {[64  : 191]};
            bins high_range = {[192 : 254]};
        }

        // 覆盖读取时 FIFO 的空状态
        cp_rempty: coverpoint rd_trans.empty {
            bins not_empty = {0};  // 正常读取
            bins empty     = {1};  // 空时读取（DUT 应忽略，rempty 保护测试）
        }

    endgroup

    string name;

    // ── 构造函数 ─────────────────────────────────────────────────────────────
    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) wr_cov_mbx,
        mailbox #(fifo_transaction #(DATA_WIDTH)) rd_cov_mbx
    );
        this.name       = name;
        this.wr_cov_mbx = wr_cov_mbx;
        this.rd_cov_mbx = rd_cov_mbx;

        // 初始化采样对象和 covergroup
        wr_trans = new();
        rd_trans = new();
        write_cg = new();  // 创建 covergroup 实例
        read_cg  = new();
    endfunction

    // ── 写端覆盖率采集 ────────────────────────────────────────────────────────
    task run_write_cov();
        forever begin
            wr_cov_mbx.get(wr_trans);  // 等待写操作 Transaction
            write_cg.sample();          // 以 wr_trans 的当前值触发一次采样
        end
    endtask

    // ── 读端覆盖率采集 ────────────────────────────────────────────────────────
    task run_read_cov();
        forever begin
            rd_cov_mbx.get(rd_trans);
            read_cg.sample();
        end
    endtask

    // ── 并行运行两个采集任务 ──────────────────────────────────────────────────
    task run();
        fork
            run_write_cov();
            run_read_cov();
        join
    endtask

    // ── 覆盖率报告 ────────────────────────────────────────────────────────────
    function void report();
        $display("╔══════════════════════════════════════╗");
        $display("║       COVERAGE REPORT                ║");
        $display("╠══════════════════════════════════════╣");
        $display("║  Write CG Coverage: %5.1f%%           ║", write_cg.get_coverage());
        $display("║  Read  CG Coverage: %5.1f%%           ║", read_cg.get_coverage());
        $display("╚══════════════════════════════════════╝");
    endfunction

endclass : fifo_coverage
