// ============================================================================
// 文件名: fifo_monitor.sv
// 描述:   监测器类（Monitor Class）
//
// 功能说明:
//   Monitor 被动监测接口上的信号，不主动驱动任何信号。
//   它将观测到的信号序列重新打包成 transaction，
//   通过 mailbox 发送给 scoreboard 进行检查。
//
//   写监测器: 监测写操作，记录成功写入的数据
//   读监测器: 监测读操作，记录从DUT读出的数据
// ============================================================================

// ============================================================
// 写端口监测器
// ============================================================
class fifo_write_monitor #(parameter DATA_WIDTH = 8);

    virtual fifo_write_if #(DATA_WIDTH) vif;

    // 发送给scoreboard的mailbox
    mailbox #(fifo_transaction #(DATA_WIDTH)) scb_mbx;

    string name;

    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) vif,
        mailbox #(fifo_transaction #(DATA_WIDTH)) scb_mbx
    );
        this.name    = name;
        this.vif     = vif;
        this.scb_mbx = scb_mbx;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        $display("[%0t][%s] Monitor started", $time, name);

        forever begin
            // 等待写操作发生
            // 条件：winc=1 且 wfull=0（实际写入成功）
            @(vif.write_mon_cb);

            if (vif.write_mon_cb.winc && !vif.write_mon_cb.wfull) begin
                // 捕获到一次有效写操作
                trans           = new();
                trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
                trans.data      = vif.write_mon_cb.wdata;
                trans.full      = vif.write_mon_cb.wfull;
                trans.timestamp = $time;

                $display("[%0t][%s] Captured WRITE data=0x%02h",
                         $time, name, trans.data);

                // 将事务发送给scoreboard
                scb_mbx.put(trans);
            end
        end
    endtask

endclass : fifo_write_monitor


// ============================================================
// 读端口监测器
// ============================================================
class fifo_read_monitor #(parameter DATA_WIDTH = 8);

    virtual fifo_read_if #(DATA_WIDTH) vif;
    mailbox #(fifo_transaction #(DATA_WIDTH)) scb_mbx;
    string name;

    function new(
        string name,
        virtual fifo_read_if #(DATA_WIDTH) vif,
        mailbox #(fifo_transaction #(DATA_WIDTH)) scb_mbx
    );
        this.name    = name;
        this.vif     = vif;
        this.scb_mbx = scb_mbx;
    endfunction

    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        $display("[%0t][%s] Monitor started", $time, name);

        forever begin
            @(vif.read_mon_cb);

            // rinc=1 且 rempty=0：有效读操作
            // 数据在rinc的下一拍有效（异步FIFO特性）
            if (vif.read_mon_cb.rinc && !vif.read_mon_cb.rempty) begin
                // 等待下一个读时钟沿获取有效数据
                @(vif.read_mon_cb);

                trans           = new();
                trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
                trans.data      = vif.read_mon_cb.rdata;
                trans.empty     = vif.read_mon_cb.rempty;
                trans.timestamp = $time;

                $display("[%0t][%s] Captured READ  data=0x%02h",
                         $time, name, trans.data);

                scb_mbx.put(trans);
            end
        end
    endtask

endclass : fifo_read_monitor
