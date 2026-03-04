// ============================================================================
// 文件名: fifo_coverage.sv
// 描述:   功能覆盖率模型（Functional Coverage Model）
//
// 概念说明:
//   功能覆盖率（Functional Coverage）用于衡量我们的测试
//   是否覆盖了所有感兴趣的功能场景。
//
//   与代码覆盖率（Code Coverage）不同：
//   - 代码覆盖率：哪些代码行被执行了
//   - 功能覆盖率：哪些功能场景被测试了
//
//   covergroup: 覆盖率组，包含多个coverpoint
//   coverpoint: 定义需要覆盖的信号或表达式
//   cross:      两个coverpoint的交叉覆盖
//   bins:       将取值范围分成不同的桶（bucket）
// ============================================================================

class fifo_coverage #(parameter DATA_WIDTH = 8);

    // 从监测器接收事务的mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_cov_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_cov_mbx;

    // ---- 写端口覆盖率组 ----
    covergroup write_cg;
        // 覆盖写数据的范围
        cp_wdata: coverpoint wr_trans.data {
            bins zero       = {0};                      // 数据为0
            bins max_val    = {(1<<DATA_WIDTH)-1};      // 数据为最大值
            bins low_range  = {[1  : 63]};              // 低范围
            bins mid_range  = {[64 : 191]};             // 中间范围
            bins high_range = {[192: 254]};             // 高范围
        }

        // 覆盖FIFO满状态
        cp_wfull: coverpoint wr_trans.full {
            bins not_full = {0};  // 写入时不满
            bins full     = {1};  // 写入时满（会被丢弃，测试wfull保护）
        }

        // 交叉覆盖：在满/不满状态下的数据范围
        cx_data_full: cross cp_wdata, cp_wfull;
    endgroup

    // ---- 读端口覆盖率组 ----
    covergroup read_cg;
        cp_rdata: coverpoint rd_trans.data {
            bins zero       = {0};
            bins max_val    = {(1<<DATA_WIDTH)-1};
            bins low_range  = {[1  : 63]};
            bins mid_range  = {[64 : 191]};
            bins high_range = {[192: 254]};
        }

        cp_rempty: coverpoint rd_trans.empty {
            bins not_empty = {0};
            bins empty     = {1};  // 读时空（会被忽略，测试rempty保护）
        }
    endgroup

    // 当前处理的事务（covergroup采样使用）
    fifo_transaction #(DATA_WIDTH) wr_trans;
    fifo_transaction #(DATA_WIDTH) rd_trans;

    string name;

    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) wr_cov_mbx,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) rd_cov_mbx);
        this.name       = name;
        this.wr_cov_mbx = wr_cov_mbx;
        this.rd_cov_mbx = rd_cov_mbx;
        wr_trans = new();
        rd_trans = new();
        write_cg = new();
        read_cg  = new();
    endfunction

    // 采集写端覆盖率
    task run_write_cov();
        forever begin
            wr_cov_mbx.get(wr_trans);
            write_cg.sample();  // 触发采样
        end
    endtask

    // 采集读端覆盖率
    task run_read_cov();
        forever begin
            rd_cov_mbx.get(rd_trans);
            read_cg.sample();
        end
    endtask

    task run();
        fork
            run_write_cov();
            run_read_cov();
        join
    endtask

    // 打印覆盖率报告
    function void report();
        $display("╔══════════════════════════════════════╗");
        $display("║       COVERAGE REPORT                ║");
        $display("╠══════════════════════════════════════╣");
        $display("║  Write CG Coverage: %5.1f%%           ║", write_cg.get_coverage());
        $display("║  Read  CG Coverage: %5.1f%%           ║", read_cg.get_coverage());
        $display("╚══════════════════════════════════════╝");
    endfunction

endclass : fifo_coverage
