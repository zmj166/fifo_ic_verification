// ============================================================================
// 文件名 : fifo_driver.sv
// 功  能 : 驱动器类（Driver Class）— 把 Transaction 转换为真实信号波形
//
// ── Driver 的职责 ─────────────────────────────────────────────────────────────
//   Driver 是验证平台和 DUT 之间的"翻译层"：
//   1. 从 Mailbox 取出 Sequence 产生的 Transaction（高层数据包）
//   2. 根据 Transaction 的内容，在接口上驱动具体的信号电平
//   3. 等待 clocking block 的时钟沿，确保信号在正确时刻发出
//
//   比喻：如果 Transaction 是"发一封信"的指令，
//         Driver 就是拿着信按照正确的步骤把信放入邮箱的那个人。
//
// ── 通信机制 ─────────────────────────────────────────────────────────────────
//   Sequence → [Mailbox] → Driver → [Interface] → DUT
//
//   Mailbox 就像一个缓冲队列，Sequence 往里放，Driver 从里取，
//   两者可以独立运行（异步解耦），不需要一对一同步。
//
// ── 本文件包含两个 Driver 类 ─────────────────────────────────────────────────
//   fifo_write_driver : 驱动写端口（winc、wdata、wrst_n）
//   fifo_read_driver  : 驱动读端口（rinc、rrst_n）
// ============================================================================

// ============================================================================
// 写驱动器：fifo_write_driver
// ============================================================================
class fifo_write_driver #(parameter DATA_WIDTH = 8);

    // 虚接口句柄：指向 TB Top 中实例化的真实接口
    // virtual 关键字表示"可以指向任何兼容的实际接口实例"
    virtual fifo_write_if #(DATA_WIDTH) vif;

    // Mailbox：从 Sequence 接收 Transaction
    // #(fifo_transaction) 是参数化类型，只允许放入/取出 fifo_transaction 类型对象
    mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx;

    string name;  // 组件名称，用于日志打印，便于区分多个 Driver 实例

    // ── 构造函数 ─────────────────────────────────────────────────────────────
    // 在 fifo_env 的 build() 中调用：write_drv = new("write_drv", w_vif, wr_drv_mbx);
    function new(
        string name,
        virtual fifo_write_if #(DATA_WIDTH) vif,
        mailbox #(fifo_transaction #(DATA_WIDTH)) drv_mbx
    );
        this.name    = name;
        this.vif     = vif;
        this.drv_mbx = drv_mbx;
    endfunction

    // ── 复位任务 ─────────────────────────────────────────────────────────────
    // 仿真开始时先拉低复位信号，保持 4 个时钟周期后释放
    // 这模拟真实硬件上电复位的行为
    task reset();
        $display("[%0t][%s] Applying reset...", $time, name);

        // 拉低复位，同时把所有输出置为安全初始值（防止 X 状态传播）
        vif.write_cb.wrst_n <= 1'b0;  // 激活复位（低有效）
        vif.write_cb.winc   <= 1'b0;  // 写使能无效
        vif.write_cb.wdata  <= 0;     // 写数据为0

        // 等待 4 个写时钟周期，确保 DUT 完成复位
        // @(vif.write_cb) 等待一个 clocking block 时钟沿
        repeat(4) @(vif.write_cb);

        // 释放复位
        vif.write_cb.wrst_n <= 1'b1;

        // 再等一个周期确认复位已被 DUT 识别
        @(vif.write_cb);

        $display("[%0t][%s] Reset done", $time, name);
    endtask

    // ── 主运行任务 ────────────────────────────────────────────────────────────
    // 在 fifo_env.run() 中用 fork...join_none 启动，永远循环
    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        // 等待复位释放后再开始处理事务
        // iff 是 SV 的等待条件：等到 rrst_n=1 的那个上升沿
        @(posedge vif.wclk iff vif.wrst_n);
        @(vif.write_cb);  // 再等一个周期，确保时序稳定

        // 永久循环：不断从 Mailbox 取事务并驱动
        forever begin
            // get() 是阻塞调用：如果 Mailbox 为空，就在此等待
            // 直到 Sequence 往里放了新的 Transaction
            drv_mbx.get(trans);

            // 执行 Transaction 中指定的延迟（0~5 个周期）
            // 模拟真实场景中操作之间的时间间隔
            repeat(trans.delay) @(vif.write_cb);

            // 记录操作时 FIFO 的状态（用于 Transaction 的调试信息）
            trans.full      = vif.write_cb.wfull;
            trans.timestamp = $time;

            // 执行写操作（前提：FIFO 不满）
            if (!vif.write_cb.wfull) begin
                // 在 clocking block 驱动时刻（上升沿后 2ns）拉高 winc 并放上 wdata
                vif.write_cb.winc  <= 1'b1;
                vif.write_cb.wdata <= trans.data;

                // 等待一个时钟周期（让 DUT 采样到 winc=1）
                @(vif.write_cb);

                // 拉低 winc（只保持一个周期的脉冲）
                vif.write_cb.winc  <= 1'b0;

                $display("[%0t][%s] Write data=0x%02h", $time, name, trans.data);
            end else begin
                // FIFO 满时跳过写操作，但仍然消耗掉这个 Transaction
                // 这样 Sequence 的事务数量统计不会受影响
                $display("[%0t][%s] FIFO FULL! Skip write data=0x%02h",
                         $time, name, trans.data);
                @(vif.write_cb);  // 等一个周期再检查下一个事务
            end
        end
    endtask

endclass : fifo_write_driver


// ============================================================================
// 读驱动器：fifo_read_driver
// ============================================================================
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

    // ── 复位任务 ─────────────────────────────────────────────────────────────
    // 与写复位对称，拉低 rrst_n 保持 4 个读时钟周期后释放
    task reset();
        vif.read_cb.rrst_n <= 1'b0;  // 激活读端口复位
        vif.read_cb.rinc   <= 1'b0;  // 读使能无效
        repeat(4) @(vif.read_cb);
        vif.read_cb.rrst_n <= 1'b1;  // 释放复位
        @(vif.read_cb);
    endtask

    // ── 主运行任务 ────────────────────────────────────────────────────────────
    task run();
        fifo_transaction #(DATA_WIDTH) trans;

        @(posedge vif.rclk iff vif.rrst_n);
        @(vif.read_cb);

        forever begin
            drv_mbx.get(trans);

            // 等待 Transaction 指定的延迟周期
            repeat(trans.delay) @(vif.read_cb);

            trans.empty     = vif.read_cb.rempty;
            trans.timestamp = $time;

            // 执行读操作（前提：FIFO 不空）
            if (!vif.read_cb.rempty) begin
                // 拉高 rinc 一个时钟周期，触发 DUT 推进读指针
                // 注意：rdata 是组合逻辑，此时 rdata 已经是当前读地址的数据
                //       Monitor 会在同一拍（rinc=1 时）采样 rdata，不需要等到下一拍
                vif.read_cb.rinc <= 1'b1;
                @(vif.read_cb);           // 等一个周期（DUT 更新读指针）
                vif.read_cb.rinc <= 1'b0; // 拉低 rinc

                $display("[%0t][%s] Read issued (data will be captured by monitor)",
                         $time, name);
            end else begin
                // FIFO 空时跳过读操作
                $display("[%0t][%s] FIFO EMPTY! Skip read", $time, name);
                @(vif.read_cb);
            end
        end
    endtask

endclass : fifo_read_driver
