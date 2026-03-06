// ============================================================================
// 文件名: fifo_sequence.sv
// 描述:   激励序列（Sequence）
//
// 概念说明:
//   Sequence 负责产生测试激励（transactions）并通过 mailbox 发送给 Driver。
//   不同的 Sequence 代表不同的测试场景，可灵活组合。
//
// 包含序列:
//   1. fifo_base_seq      - 基础序列（基类）
//   2. fifo_write_seq     - 基础写序列
//   3. fifo_read_seq      - 基础读序列
//   4. fifo_full_seq      - 写满测试序列
//   5. fifo_empty_seq     - 读空测试序列
//   6. fifo_random_seq    - 随机读写序列
//   7. fifo_back2back_seq - 背靠背（连续）操作序列
// ============================================================================

// ============================================================
// 基础写序列
// ============================================================
class fifo_write_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned num_trans;  // 事务数量
    string name;

    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
                 int unsigned num_trans = 8);
        this.name      = name;
        this.drv_mbx   = drv_mbx;
        this.num_trans = num_trans;
    endfunction

    // 发送num_trans个随机写事务
    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Write sequence start: %0d transactions", $time, name, num_trans);

        repeat(num_trans) begin
            trans = new();
            if (!trans.randomize()) $fatal("[%s] Randomize failed!", name);
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
            drv_mbx.put(trans);
        end
        $display("[%0t][%s] Write sequence done", $time, name);
    endtask

endclass : fifo_write_seq


// ============================================================
// 基础读序列
// ============================================================
class fifo_read_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned num_trans;
    string name;

    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
                 int unsigned num_trans = 8);
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


// ============================================================
// 写满序列：向FIFO写满数据
// ============================================================
class fifo_full_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned fifo_depth;  // FIFO深度
    string name;

    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
                 int unsigned fifo_depth = 16);
        this.name       = name;
        this.drv_mbx    = drv_mbx;
        this.fifo_depth = fifo_depth;
    endfunction

    // 写入 fifo_depth+2 个数据（多余的会被丢弃，验证wfull功能）
    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Full test: writing %0d entries to fill FIFO", 
                 $time, name, fifo_depth+2);

        repeat(fifo_depth + 2) begin
            trans = new();
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
            // 数据递增，方便调试
            trans.data       = $urandom_range(0, (1<<DATA_WIDTH)-1);
            trans.delay      = 0;  // 无延迟，最快速写入
            drv_mbx.put(trans);
        end
    endtask

endclass : fifo_full_seq


// ============================================================
// 读空序列：从FIFO读空所有数据
// ============================================================
class fifo_empty_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    int unsigned fifo_depth;
    string name;

    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx,
                 int unsigned fifo_depth = 16);
        this.name       = name;
        this.drv_mbx    = drv_mbx;
        this.fifo_depth = fifo_depth;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;
        $display("[%0t][%s] Empty test: reading %0d entries to empty FIFO", 
                 $time, name, fifo_depth+2);

        repeat(fifo_depth + 2) begin
            trans = new();
            trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
            trans.delay      = 0;
            drv_mbx.put(trans);
        end
    endtask

endclass : fifo_empty_seq


// ============================================================
// 背靠背序列：连续无间隔操作
// 用于测试最高性能场景下的正确性
// ============================================================
class fifo_back2back_seq #(parameter DATA_WIDTH = 8);

    mailbox #(fifo_transaction #(DATA_WIDTH)) wr_drv_mbx;
    mailbox #(fifo_transaction #(DATA_WIDTH)) rd_drv_mbx;
    int unsigned num_trans;
    string name;

    function new(string name,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) wr_drv_mbx,
                 mailbox #(fifo_transaction #(DATA_WIDTH)) rd_drv_mbx,
                 int unsigned num_trans = 32);
        this.name       = name;
        this.wr_drv_mbx = wr_drv_mbx;
        this.rd_drv_mbx = rd_drv_mbx;
        this.num_trans  = num_trans;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) wr_trans, rd_trans;
        $display("[%0t][%s] Back-to-back sequence: %0d", $time, name, num_trans);

        // 并发写和读
        fork
            // 写线程
            begin
                repeat(num_trans) begin
                    wr_trans = new();
                    wr_trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
                    wr_trans.data       = $urandom;
                    wr_trans.delay      = 0;
                    wr_drv_mbx.put(wr_trans);
                end
            end
            // 读线程（稍微延迟，等待有数据可读）
            begin
                #20; // 等待一些数据先写入
                repeat(num_trans) begin
                    rd_trans = new();
                    rd_trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
                    rd_trans.delay      = 0;
                    rd_drv_mbx.put(rd_trans);
                end
            end
        join
    endtask

endclass : fifo_back2back_seq
