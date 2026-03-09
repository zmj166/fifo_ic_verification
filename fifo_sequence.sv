// ============================================================================
// 文件名 : fifo_sequence.sv
// 功  能 : 激励序列（Sequence）— 产生测试激励并投递给 Driver
//
// ── 什么是 Sequence ────────────────────────────────────────────────────────────
//   Sequence 负责决定"测什么"：
//   - 写多少个数据？写什么数据？什么节奏写？
//   - 先写后读？还是并发读写？
//
//   Sequence 把这些决策封装成 Transaction 对象，
//   通过 Mailbox 发送给 Driver，Driver 再转换为信号驱动 DUT。
//
//   好处：测试场景和底层驱动分离，换场景只需换 Sequence，不需改 Driver。
//
// ── 本文件包含的序列 ──────────────────────────────────────────────────────────
//   fifo_write_seq     : 发送 N 个随机写事务
//   fifo_read_seq      : 发送 N 个随机读事务
//   fifo_full_seq      : 发送 FIFO深度+2 个写事务（测试写满和满保护）
//   fifo_empty_seq     : 发送 FIFO深度+2 个读事务（测试读空和空保护）
//   fifo_back2back_seq : 并发读写，模拟高负载场景
// ============================================================================

// ============================================================================
// 序列1：基础写序列 fifo_write_seq
// 场景：发送 num_trans 个随机写事务
// ============================================================================
class fifo_write_seq #(parameter DATA_WIDTH = 8);

    // 发送事务到 Write Driver 的 Mailbox（由 Env 创建，通过构造函数传入）
    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;

    int unsigned num_trans;  // 要发送的事务数量
    string name;

    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
        int unsigned num_trans = 8  // 默认发送 8 个事务
    );
        this.name      = name;
        this.drv_mbx   = drv_mbx;
        this.num_trans = num_trans;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Write sequence start: %0d transactions", $time, name, num_trans);

        repeat(num_trans) begin
            trans = new();  // 每次循环创建新对象（避免共享同一个对象的引用）

            // randomize() 自动按照 constraint 随机化所有 rand 变量
            // 失败时（极少发生）用 $fatal 终止仿真并报错
            if (!trans.randomize()) $fatal("[%s] Randomize failed!", name);

            // 强制指定类型为写操作（覆盖 randomize 可能产生的读类型）
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;

            // 投入 Mailbox，Driver 会异步取走并驱动
            drv_mbx.put(trans);
        end

        $display("[%0t][%s] Write sequence done", $time, name);
    endtask

endclass : fifo_write_seq


// ============================================================================
// 序列2：基础读序列 fifo_read_seq
// 场景：发送 num_trans 个读事务（触发 Driver 执行 rinc）
// ============================================================================
class fifo_read_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned num_trans;
    string name;

    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
        int unsigned num_trans = 8
    );
        this.name      = name;
        this.drv_mbx   = drv_mbx;
        this.num_trans = num_trans;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Read sequence start: %0d transactions", $time, name, num_trans);

        repeat(num_trans) begin
            trans = new();
            if (!trans.randomize()) $fatal("[%s] Randomize failed!", name);
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
            drv_mbx.put(trans);
        end

        $display("[%0t][%s] Read sequence done", $time, name);
    endtask

endclass : fifo_read_seq


// ============================================================================
// 序列3：写满序列 fifo_full_seq
// 场景：写入 FIFO深度+2 个数据，测试写满保护机制
//   - 前 fifo_depth 个：正常写入（wfull=0）
//   - 后 2 个：FIFO 已满（wfull=1），Driver 会跳过，测试满保护
// ============================================================================
class fifo_full_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned fifo_depth;  // FIFO 深度（用于计算写满所需的事务数）
    string name;

    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
        int unsigned fifo_depth = 16  // 默认深度 16（ADDR_WIDTH=4）
    );
        this.name       = name;
        this.drv_mbx    = drv_mbx;
        this.fifo_depth = fifo_depth;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Full test: writing %0d entries to fill FIFO",
                 $time, name, fifo_depth + 2);

        repeat(fifo_depth + 2) begin
            trans            = new();
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
            trans.data       = $urandom_range(0, (1<<DATA_WIDTH)-1);  // 随机数据
            trans.delay      = 0;  // 无延迟，尽可能快地写满
            drv_mbx.put(trans);
        end
    endtask

endclass : fifo_full_seq


// ============================================================================
// 序列4：读空序列 fifo_empty_seq
// 场景：发送 FIFO深度+2 个读事务，测试读空保护机制
//   - 前 fifo_depth 个：正常读出
//   - 后 2 个：FIFO 已空（rempty=1），Driver 跳过，测试空保护
// ============================================================================
class fifo_empty_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned fifo_depth;
    string name;

    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
        int unsigned fifo_depth = 16
    );
        this.name       = name;
        this.drv_mbx    = drv_mbx;
        this.fifo_depth = fifo_depth;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Empty test: reading %0d entries to empty FIFO",
                 $time, name, fifo_depth + 2);

        repeat(fifo_depth + 2) begin
            trans            = new();
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
            trans.delay      = 0;  // 无延迟，尽可能快地读空
            drv_mbx.put(trans);
        end
    endtask

endclass : fifo_empty_seq


// ============================================================================
// 序列5：背靠背并发序列 fifo_back2back_seq
// 场景：写和读同时进行，测试高负载下的并发正确性（随机测试用）
//
// 使用 fork...join 并发执行写线程和读线程：
//   写线程：持续发送 num_trans 个写事务（无延迟，最高速度）
//   读线程：等待 20ns 后开始（让 FIFO 里先有数据再读），然后发送读事务
//
// 注意：写和读的速率不同（写时钟 100MHz，读时钟 75MHz），
//       Scoreboard 会自动处理时序差异，只检查数据顺序正确性
// ============================================================================
class fifo_back2back_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_drv_mbx;  // 写 Driver 的 Mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_drv_mbx;  // 读 Driver 的 Mailbox
    int unsigned num_trans;
    string name;

    function new(
        string name,
        mailbox #(fifo_transaction #(DATA_WIDTH)) wr_drv_mbx,
        mailbox #(fifo_transaction #(DATA_WIDTH)) rd_drv_mbx,
        int unsigned num_trans = 32  // 默认发送 32 组读写事务
    );
        this.name       = name;
        this.wr_drv_mbx = wr_drv_mbx;
        this.rd_drv_mbx = rd_drv_mbx;
        this.num_trans  = num_trans;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) wr_trans, rd_trans;
        $display("[%0t][%s] Back-to-back sequence: %0d transactions", $time, name, num_trans);

        // fork...join：两个线程并行，都完成后 run() 才返回
        fork
            // ── 写线程：全速写入 ──────────────────────────────────────────
            begin
                repeat(num_trans) begin
                    wr_trans            = new();
                    wr_trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
                    wr_trans.data       = $urandom;  // 完全随机数据
                    wr_trans.delay      = 0;         // 背靠背，无间隙
                    wr_drv_mbx.put(wr_trans);
                end
            end

            // ── 读线程：稍微延迟后全速读取 ───────────────────────────────
            begin
                #20;  // 等待 20ns，让写端先写入几个数据（避免读到空 FIFO 太多）
                repeat(num_trans) begin
                    rd_trans            = new();
                    rd_trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
                    rd_trans.delay      = 0;
                    rd_drv_mbx.put(rd_trans);
                end
            end
        join
    endtask

endclass : fifo_back2back_seq
