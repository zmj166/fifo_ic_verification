// ============================================================================
// 文件名 : fifo_monitor.sv
// 功  能 : 监测器类（Monitor Class）— 被动观察 DUT 的信号输出
//
// ── Monitor 的职责 ────────────────────────────────────────────────────────────
//   Monitor 是验证平台中的"观察者"：
//   1. 被动监测接口上的信号，绝对不主动驱动任何信号
//   2. 当检测到有效操作时，把信号值打包成 Transaction
//   3. 通过 Mailbox 把 Transaction 发送给 Scoreboard 进行数据比较
//
//   比喻：Driver 是"操作员"，Monitor 是"审计员"，
//         审计员只看不动，记录所有操作供事后核查。
//
// ── 关键时序说明（BUG 修复记录）─────────────────────────────────────────────
//
//   RTL 中 rdata 的产生逻辑（fifo_mem 子模块）：
//     assign rdata = mem[raddr];   ← 组合逻辑，无时钟
//     raddr = rptr[ADDR_WIDTH-1:0]; ← rptr 是时序逻辑寄存器
//
//   时序分析（以 rclk 上升沿为基准）：
//     上升沿 N 之前：rptr=N，raddr=N，rdata=mem[N]（已稳定）
//     上升沿 N 触发：rinc=1 → rptr 在本拍加1 → rptr 变为 N+1
//     上升沿 N 之后：raddr=N+1，rdata=mem[N+1]（变为下一个数据）
//
//   clocking block 在上升沿前 1ns 采样：
//     此时 rptr 还是 N（旧值），rdata=mem[N]（正确的当前数据）
//
//   结论：Monitor 应在 rinc=1 的【同一拍】直接采样 rdata
//
//   曾经的 BUG：原代码在检测到 rinc=1 后，多等了一个 @(read_mon_cb)，
//     导致采样时机在 rptr 已更新后，读到的是 mem[N+1]（下一个数据），
//     造成所有读出数据整体偏移一位，Scoreboard 全部 FAIL。
//
//   修复方法：删除多余的 @(read_mon_cb)，在同一拍直接采样。
//
// ── 本文件包含两个 Monitor 类 ────────────────────────────────────────────────
//   fifo_write_monitor : 监测写端口，捕获每次成功写入的数据
//   fifo_read_monitor  : 监测读端口，捕获每次读出的数据
// ============================================================================

// ============================================================================
// 写端口监测器：fifo_write_monitor
// ============================================================================
class fifo_write_monitor #(parameter DATA_WIDTH = 8);

    // 虚接口：只读访问写端口的所有信号
    virtual fifo_write_if #(DATA_WIDTH) vif;

    // 发送给 Scoreboard 的 Mailbox
    // 每次检测到有效写操作，就往这个 Mailbox 里放一个 Transaction
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

    // ── 主运行任务 ────────────────────────────────────────────────────────────
    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        $display("[%0t][%s] Monitor started", $time, name);

        // 永久循环，持续监测
        forever begin
            // 等待写时钟上升沿（通过 write_mon_cb 触发）
            @(vif.write_mon_cb);

            // 检测条件：winc=1（写请求有效）且 wfull=0（FIFO 未满）
            // 只有两个条件同时满足，数据才真正被写入 DUT
            if (vif.write_mon_cb.winc && !vif.write_mon_cb.wfull) begin

                // 创建新的 Transaction 并填充字段
                trans            = new();
                trans.trans_type = fifo_transaction #(DATA_WIDTH)::WRITE;
                trans.data       = vif.write_mon_cb.wdata;   // 采样写数据
                trans.full       = vif.write_mon_cb.wfull;   // 记录当前满状态
                trans.timestamp  = $time;

                $display("[%0t][%s] Captured WRITE data=0x%02h",
                         $time, name, trans.data);

                // 把 Transaction 放入 Mailbox，Scoreboard 会异步取走
                scb_mbx.put(trans);
            end
        end
    endtask

endclass : fifo_write_monitor


// ============================================================================
// 读端口监测器：fifo_read_monitor
// ============================================================================
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

    // ── 主运行任务 ────────────────────────────────────────────────────────────
    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        $display("[%0t][%s] Monitor started", $time, name);

        forever begin
            // 等待读时钟上升沿（通过 read_mon_cb 触发，在上升沿前 1ns 采样）
            @(vif.read_mon_cb);

            // 检测条件：rinc=1（读请求有效）且 rempty=0（FIFO 非空）
            if (vif.read_mon_cb.rinc && !vif.read_mon_cb.rempty) begin

                // ────────────────────────────────────────────────────────────
                // 【关键】直接在本拍采样 rdata，不等下一拍！
                //
                // 原因分析：
                //   - fifo_mem 的 rdata 是组合逻辑：assign rdata = mem[raddr]
                //   - raddr 来自 rptr 的低位（时序寄存器）
                //   - 在本拍上升沿前 1ns（clocking block 采样时刻）：
                //     rptr 还未更新（要等本拍上升沿触发后才加1）
                //     所以 raddr=rptr_old，rdata=mem[rptr_old]，是当前读出数据 ✓
                //   - 如果多等一个 @(read_mon_cb)（等到下一拍）：
                //     rptr 已经更新为 rptr_old+1
                //     rdata=mem[rptr_old+1]，是下一个数据 ✗（错位！）
                // ────────────────────────────────────────────────────────────
                trans            = new();
                trans.trans_type = fifo_transaction #(DATA_WIDTH)::READ;
                trans.data       = vif.read_mon_cb.rdata;   // 同一拍采样，正确！
                trans.empty      = vif.read_mon_cb.rempty;
                trans.timestamp  = $time;

                $display("[%0t][%s] Captured READ  data=0x%02h",
                         $time, name, trans.data);

                scb_mbx.put(trans);
            end
        end
    endtask

endclass : fifo_read_monitor
