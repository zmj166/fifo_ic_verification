// ============================================================================
// 文件名: fifo_scoreboard.sv
// 描述:   记分板（Scoreboard）
//
// 功能说明:
//   Scoreboard 是验证的核心检查机制：
//   1. 接收写监测器捕获的写数据 => 存入参考队列（reference model）
//   2. 接收读监测器捕获的读数据 => 与参考队列头部数据比较
//   3. 若匹配 => PASS；若不匹配 => FAIL（报错）
//
//   这相当于用软件实现了一个"理想的FIFO模型"，
//   然后检查DUT的行为是否与理想模型一致。
//
// 统计信息:
//   记录总事务数、通过数、失败数，最终输出验证报告
// ============================================================================

class fifo_scoreboard #(parameter DATA_WIDTH = 8);

    // 从写监测器接收事务的mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_mbx;
    // 从读监测器接收事务的mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_mbx;

    // 参考模型：先入先出队列（模拟理想FIFO行为）
    // SV中queue用[$]表示，自动动态分配
    logic [DATA_WIDTH-1:0] ref_queue[$];

    // 统计计数器
    int unsigned total_writes;  // 总写入次数
    int unsigned total_reads;   // 总读出次数
    int unsigned pass_count;    // 数据比较通过次数
    int unsigned fail_count;    // 数据比较失败次数

    string name;

    // ---- 构造函数 ----
    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) wr_mbx,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) rd_mbx);
        this.name        = name;
        this.wr_mbx      = wr_mbx;
        this.rd_mbx      = rd_mbx;
        this.total_writes = 0;
        this.total_reads  = 0;
        this.pass_count   = 0;
        this.fail_count   = 0;
    endfunction

    // ---- 处理写事务 ----
    task run_write();
        fifo_transaction #(DATA_WIDTH) trans;
        forever begin
            wr_mbx.get(trans);
            // 写数据压入参考队列尾部
            ref_queue.push_back(trans.data);
            total_writes++;
            $display("[%0t][%s] SCB: WRITE data=0x%02h => ref_queue size=%0d",
                     $time, name, trans.data, ref_queue.size());
        end
    endtask

    // ---- 处理读事务 ----
    task run_read();
        fifo_transaction #(DATA_WIDTH) trans;
        logic [DATA_WIDTH-1:0] expected;
        forever begin
            rd_mbx.get(trans);
            total_reads++;

            if (ref_queue.size() == 0) begin
                // 参考队列为空时读到数据 => 错误
                $error("[%0t][%s] SCB: READ when ref_queue is EMPTY! data=0x%02h",
                       $time, name, trans.data);
                fail_count++;
            end else begin
                // 从参考队列头部弹出期望值
                expected = ref_queue.pop_front();

                if (trans.data === expected) begin
                    // 数据匹配 => PASS
                    $display("[%0t][%s] SCB: PASS READ data=0x%02h (expected=0x%02h)",
                             $time, name, trans.data, expected);
                    pass_count++;
                end else begin
                    // 数据不匹配 => FAIL
                    $error("[%0t][%s] SCB: FAIL READ data=0x%02h (expected=0x%02h)",
                           $time, name, trans.data, expected);
                    fail_count++;
                end
            end
        end
    endtask

    // ---- 并行运行写和读检查 ----
    task run();
        fork
            run_write();
            run_read();
        join
    endtask

    // ---- 报告最终结果 ----
    function void report();
        $display("╔══════════════════════════════════════╗");
        $display("║        SCOREBOARD REPORT             ║");
        $display("╠══════════════════════════════════════╣");
        $display("║  Total Writes : %4d                 ║", total_writes);
        $display("║  Total Reads  : %4d                 ║", total_reads);
        $display("║  PASS         : %4d                 ║", pass_count);
        $display("║  FAIL         : %4d                 ║", fail_count);
        $display("║  Ref Queue    : %4d (should be 0)   ║", ref_queue.size());
        $display("╠══════════════════════════════════════╣");
        if (fail_count == 0 && ref_queue.size() == 0)
            $display("║  *** VERIFICATION PASSED ***         ║");
        else
            $display("║  *** VERIFICATION FAILED ***         ║");
        $display("╚══════════════════════════════════════╝");
    endfunction

endclass : fifo_scoreboard
