// ============================================================================
// 文件名 : fifo_transaction.sv
// 功  能 : 事务类（Transaction Class）— 验证平台的基本数据单元
//
// ── 什么是 Transaction ────────────────────────────────────────────────────────
//   Transaction（事务）是验证中的抽象数据包，代表一次完整的总线操作。
//   在本项目中，一个 Transaction 代表"向 FIFO 写一个数据"或"从 FIFO 读一个数据"。
//
//   好处：
//     - 把底层信号电平操作抽象成高层数据对象，便于组合和传递
//     - 可以随机化（randomize），自动产生大量合法激励
//     - 可以在 Scoreboard 中直接比较两个 Transaction 的数据
//
// ── 随机化说明 ────────────────────────────────────────────────────────────────
//   rand   关键字：该变量会被 randomize() 自动随机赋值
//   constraint：约束随机值的合法范围，确保生成的激励是有意义的
//
//   调用方式：
//     trans = new();
//     if (!trans.randomize()) $fatal("randomize failed!");
//     // 之后 trans.data 和 trans.delay 都有了合法的随机值
// ============================================================================

class fifo_transaction #(parameter DATA_WIDTH = 8);

    // ── 事务类型枚举 ─────────────────────────────────────────────────────────
    // 用枚举而非直接用 0/1，代码可读性更高
    typedef enum logic {
        WRITE = 1'b0,  // 写操作：Driver 把数据写入 FIFO
        READ  = 1'b1   // 读操作：Driver 从 FIFO 读取数据
    } trans_type_e;

    // ── 可随机化的属性 ────────────────────────────────────────────────────────
    rand trans_type_e           trans_type; // 事务类型（WRITE or READ）
    rand logic [DATA_WIDTH-1:0] data;       // 数据值（写时为写入数据，读时为读出数据）
    rand int unsigned            delay;     // 本次操作前等待的时钟周期数（0~5）

    // ── 非随机化的属性（仿真过程中由 Driver/Monitor 记录）────────────────────
    logic full;       // 操作发生时 FIFO 是否为满（由 Driver 记录）
    logic empty;      // 操作发生时 FIFO 是否为空（由 Driver 记录）
    time  timestamp;  // 操作发生的仿真时刻（由 Monitor 记录，用于调试定位）

    // ── 随机化约束 ────────────────────────────────────────────────────────────

    // 约束1：延迟范围 0~5 个时钟周期
    // delay=0 表示紧接着上次操作立刻执行（背靠背）
    // delay=5 表示等待 5 个周期后再执行（模拟有间隙的操作）
    constraint delay_c {
        delay inside {[0:5]};
    }

    // 约束2：数据范围 0~255（8位全范围）
    // 若需要特定数据模式，可修改此约束
    constraint data_c {
        data inside {[0:255]};
    }

    // ── 构造函数 ─────────────────────────────────────────────────────────────
    // new() 在 Sequence 或 Test 中调用：trans = new();
    function new();
        trans_type = WRITE;  // 默认为写操作
        data       = 0;
        delay      = 0;
        full       = 0;
        empty      = 0;
        timestamp  = 0;
    endfunction

    // ── 深拷贝方法 ────────────────────────────────────────────────────────────
    // 浅拷贝（直接赋值）对对象只复制引用，修改副本会影响原件。
    // 深拷贝创建新对象并复制所有字段，两者完全独立。
    // Scoreboard 中保存数据时需要深拷贝，防止原对象被修改后比较结果出错。
    function fifo_transaction #(DATA_WIDTH) copy();
        copy = new();  // 创建新对象
        copy.trans_type = this.trans_type;
        copy.data       = this.data;
        copy.delay      = this.delay;
        copy.full       = this.full;
        copy.empty      = this.empty;
        copy.timestamp  = this.timestamp;
        return copy;
    endfunction

    // ── 数据比较方法 ─────────────────────────────────────────────────────────
    // Scoreboard 用此方法判断 DUT 读出的数据是否与期望值一致
    // 只比较 data 字段（trans_type、delay 等无需比较）
    function bit compare(fifo_transaction #(DATA_WIDTH) other);
        return (this.data == other.data);
    endfunction

    // ── 打印方法（调试用）────────────────────────────────────────────────────
    // 在需要查看 transaction 内容时调用：trans.print("[SCB]");
    function void print(string prefix = "");
        $display("%s[TRANS] type=%-5s data=0x%02h delay=%0d full=%b empty=%b @%0t",
                 prefix,
                 trans_type.name(),  // 打印枚举名称字符串（"WRITE" 或 "READ"）
                 data, delay, full, empty, timestamp);
    endfunction

endclass : fifo_transaction
