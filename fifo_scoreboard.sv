// ============================================================================
// 文件名 : fifo_scoreboard.sv
// 功  能 : 记分板（Scoreboard）— 验证平台的"裁判"
//
// ── Scoreboard 的核心原理 ─────────────────────────────────────────────────────
//   Scoreboard 实现了一个"软件参考模型"（Reference Model）：
//
//   1. 当写 Monitor 捕获到一次写操作 → 把数据压入 ref_queue（参考队列）
//      ref_queue 就是一个软件实现的理想 FIFO，先进先出
//
//   2. 当读 Monitor 捕获到一次读操作 → 从 ref_queue 头部弹出期望值
//      对比：DUT 实际读出的值 vs 软件 FIFO 的期望值
//      相等 → PASS，不等 → FAIL（报错，并记录到 fail_count）
//
//   比喻：
//     - 写 Monitor 是"记账员"，每次写入都记下来
//     - 读 Monitor 是"核对员"，每次读出来都和账本核对
//     - Scoreboard 是账本和裁判的结合体
//
// ── 并行运行 ─────────────────────────────────────────────────────────────────
//   run_write() 和 run_read() 同时运行（fork...join），
//   因为写操作和读操作是并发发生的（不等写完再读）
//
// ── 队列操作 ─────────────────────────────────────────────────────────────────
//   SV 中动态队列用 [$] 表示：
//     push_back(x)  : 往队列尾部插入 x（对应 FIFO 写入）
//     pop_front()   : 从队列头部弹出（对应 FIFO 读出，先进先出）
//     size()        : 返回队列当前元素个数
// ============================================================================

class fifo_scoreboard #(parameter DATA_WIDTH = 8);

    // 接收写 Monitor 发来的 Transaction（写操作记录）
    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_mbx;

    // 接收读 Monitor 发来的 Transaction（读操作记录）
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_mbx;

    // ── 软件参考模型：理想 FIFO 队列 ─────────────────────────────────────────
    // 用 SV 内置队列模拟理想的 FIFO 行为
    // 写入时 push_back，读出时 pop_front，天然先进先出
    logic [DATA_WIDTH-1:0] ref_queue[$];

    // ── 统计计数器 ────────────────────────────────────────────────────────────
    int unsigned total_writes;  // 累计写入次数
    int unsigned total_reads;   // 累计读出次数
    int unsigned pass_count;    // 数据比对通过次数
    int unsigned fail_count;    // 数据比对失败次数（>0 则验证失败）

    string name;

    // ── 构造函数 ─────────────────────────────────────────────────────────────
    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) wr_mbx,
        mailbox #(fifo_transaction #(DATA_WIDTH)) rd_mbx
    );
        this.name         = name;
        this.wr_mbx       = wr_mbx;
        this.rd_mbx       = rd_mbx;
        this.total_writes = 0;
        this.total_reads  = 0;
        this.pass_count   = 0;
        this.fail_count   = 0;
    endfunction

    // ── 写操作处理任务 ────────────────────────────────────────────────────────
    // 永远循环，等待写 Monitor 发来的 Transaction
    // 每收到一个写操作记录，就把数据压入参考队列
    task run_write();
        fifo_transaction #(DATA_WIDTH) trans;
        forever begin
            wr_mbx.get(trans);  // 阻塞等待写操作

            // 把写入的数据保存到参考队列尾部（对应 FIFO 写入）
            ref_queue.push_back(trans.data);
            total_writes++;

            $display("[%0t][%s] SCB: WRITE data=0x%02h => ref_queue size=%0d",
                     $time, name, trans.data, ref_queue.size());
        end
    endtask

    // ── 读操作处理任务 ────────────────────────────────────────────────────────
    // 永远循环，等待读 Monitor 发来的 Transaction
    // 每收到一个读操作记录，就从参考队列取出期望值并比对
    task run_read();
        fifo_transaction #(DATA_WIDTH) trans;
        logic [DATA_WIDTH-1:0] expected;  // 期望值（来自参考队列）

        forever begin
            rd_mbx.get(trans);  // 阻塞等待读操作
            total_reads++;

            if (ref_queue.size() == 0) begin
                // 异常情况：参考队列为空时 DUT 仍然输出了数据
                // 说明 DUT 在 FIFO 空时还在输出数据，rempty 保护可能失效
                $error("[%0t][%s] SCB: READ when ref_queue is EMPTY! data=0x%02h",
                       $time, name, trans.data);
                fail_count++;
            end else begin
                // 从参考队列头部弹出期望值（先进先出）
                expected = ref_queue.pop_front();

                if (trans.data === expected) begin
                    // === 是 SV 的精确比较（考虑 X/Z 值），这里数据应为确定值
                    // 数据一致 → PASS
                    $display("[%0t][%s] SCB: PASS READ data=0x%02h (expected=0x%02h)",
                             $time, name, trans.data, expected);
                    pass_count++;
                end else begin
                    // 数据不一致 → FAIL，打印期望值和实际值便于调试
                    $error("[%0t][%s] SCB: FAIL READ data=0x%02h (expected=0x%02h)",
                           $time, name, trans.data, expected);
                    fail_count++;
                end
            end
        end
    endtask

    // ── 并行运行写检查和读检查 ────────────────────────────────────────────────
    // fork...join：两个任务并行启动，都完成后才返回
    // 但由于两个任务都是 forever 循环，实际上不会返回，由上层 fork...join_none 控制
    task run();
        fork
            run_write();
            run_read();
        join
    endtask

    // ── 最终验证报告 ─────────────────────────────────────────────────────────
    // 在仿真结束时由 Test 调用，打印完整的验证结果
    function void report();
        $display("╔══════════════════════════════════════╗");
        $display("║        SCOREBOARD REPORT             ║");
        $display("╠══════════════════════════════════════╣");
        $display("║  Total Writes : %4d                 ║", total_writes);
        $display("║  Total Reads  : %4d                 ║", total_reads);
        $display("║  PASS         : %4d                 ║", pass_count);
        $display("║  FAIL         : %4d                 ║", fail_count);
        // ref_queue.size()!=0 说明有数据写入但没有被读出，FIFO 读取可能不完整
        $display("║  Ref Queue    : %4d (should be 0)   ║", ref_queue.size());
        $display("╠══════════════════════════════════════╣");
        if (fail_count == 0 && ref_queue.size() == 0)
            $display("║  *** VERIFICATION PASSED ***         ║");
        else
            $display("║  *** VERIFICATION FAILED ***         ║");
        $display("╚══════════════════════════════════════╝");
    endfunction

endclass : fifo_scoreboard
