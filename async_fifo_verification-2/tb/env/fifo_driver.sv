// ============================================================================
// 文件名: fifo_driver.sv
// 描述:   驱动器类（Driver Class）
//
// 功能说明:
//   Driver 负责将 Sequence 产生的事务（transaction）转化为
//   实际的信号波形，驱动到DUT的接口上。
//
//   写驱动器: 向写端口施加写激励
//   读驱动器: 向读端口施加读激励
//
// 通信机制:
//   使用 mailbox 作为 Sequence 和 Driver 之间的通信管道
//   (类似于生产者-消费者模型)
// ============================================================================

// ============================================================
// 写驱动器
// ============================================================
class fifo_write_driver #(parameter DATA_WIDTH = 8);

    // 接口句柄（通过构造函数传入）
    virtual fifo_write_if #(DATA_WIDTH) vif;

    // mailbox：从Sequence接收事务
    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;

    // 驱动器名称（用于日志）
    string name;

    // ---- 构造函数 ----
    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) vif,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx
    );
        this.name    = name;
        this.vif     = vif;
        this.drv_mbx = drv_mbx;
    endfunction

    // ---- 复位DUT ----
    task reset();
        $display("[%0t][%s] Applying reset...", $time, name);
        vif.write_cb.wrst_n <= 1'b0;
        vif.write_cb.winc   <= 1'b0;
        vif.write_cb.wdata  <= 0;
        repeat(4) @(vif.write_cb);  // 保持复位4个周期
        vif.write_cb.wrst_n <= 1'b1;
        @(vif.write_cb);
        $display("[%0t][%s] Reset done", $time, name);
    endtask

    // ---- 主运行任务 ----
    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        // 等待复位完成
        @(posedge vif.wclk iff vif.wrst_n);
        @(vif.write_cb);

        forever begin
            // 从mailbox获取事务（阻塞等待）
            drv_mbx.get(trans);

            // 等待指定延迟周期
            repeat(trans.delay) @(vif.write_cb);

            // 记录FIFO状态
            trans.full      = vif.write_cb.wfull;
            trans.timestamp = $time;

            // 驱动写操作
            if (!vif.write_cb.wfull) begin
                vif.write_cb.winc  <= 1'b1;
                vif.write_cb.wdata <= trans.data;
                @(vif.write_cb);           // 等待一个时钟沿
                vif.write_cb.winc  <= 1'b0;
                $display("[%0t][%s] Write data=0x%02h", $time, name, trans.data);
            end else begin
                $display("[%0t][%s] FIFO FULL! Skip write data=0x%02h", $time, name, trans.data);
                @(vif.write_cb);
            end
        end
    endtask

endclass : fifo_write_driver


// ============================================================
// 读驱动器
// ============================================================
class fifo_read_driver #(parameter DATA_WIDTH = 8);

    virtual fifo_read_if #(DATA_WIDTH) vif;
    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;
    string name;

    function new(
        string name,
        virtual fifo_read_if #(DATA_WIDTH) vif,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx
    );
        this.name    = name;
        this.vif     = vif;
        this.drv_mbx = drv_mbx;
    endfunction

    task reset();
        vif.read_cb.rrst_n <= 1'b0;
        vif.read_cb.rinc   <= 1'b0;
        repeat(4) @(vif.read_cb);
        vif.read_cb.rrst_n <= 1'b1;
        @(vif.read_cb);
    endtask

    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        @(posedge vif.rclk iff vif.rrst_n);
        @(vif.read_cb);

        forever begin
            drv_mbx.get(trans);
            repeat(trans.delay) @(vif.read_cb);

            trans.empty     = vif.read_cb.rempty;
            trans.timestamp = $time;

            if (!vif.read_cb.rempty) begin
                vif.read_cb.rinc <= 1'b1;
                @(vif.read_cb);
                vif.read_cb.rinc <= 1'b0;
                $display("[%0t][%s] Read issued (data will be captured by monitor)",
                         $time, name);
            end else begin
                $display("[%0t][%s] FIFO EMPTY! Skip read", $time, name);
                @(vif.read_cb);
            end
        end
    endtask

endclass : fifo_read_driver
