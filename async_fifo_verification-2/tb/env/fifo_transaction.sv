// ============================================================================
// 文件名: fifo_transaction.sv
// 描述:   事务类（Transaction Class）
//
// 概念说明:
//   在UVM/SV验证中，"transaction"是验证的基本数据单元。
//   它代表一次完整的总线操作（写一个数据 或 读一个数据）。
//   通过将操作封装为对象，可以方便地传递、复制、比较。
//
// 随机化:
//   使用 rand 关键字声明的变量可以被 randomize() 调用随机化。
//   使用 constraint 约束随机值的范围，确保生成合法的激励。
// ============================================================================

class fifo_transaction #(parameter DATA_WIDTH = 8);

    // ---- 事务类型 ----
    typedef enum logic {
        WRITE = 1'b0,  // 写操作
        READ  = 1'b1   // 读操作
    } trans_type_e;

    // ---- 事务属性 ----
    rand trans_type_e          trans_type; // 事务类型（随机）
    rand logic [DATA_WIDTH-1:0] data;      // 数据（随机）
    rand int unsigned           delay;     // 操作间延迟周期（随机）

    // 非随机属性（仿真过程中记录）
    logic                       full;      // 操作时FIFO是否满
    logic                       empty;     // 操作时FIFO是否空
    time                        timestamp; // 时间戳

    // ---- 约束 ----
    // 约束1: 延迟范围0~5个周期
    constraint delay_c {
        delay inside {[0:5]};
    }

    // 约束2: 数据范围（可按需修改）
    constraint data_c {
        data inside {[0:255]};
    }

    // ---- 方法 ----
    // 构造函数
    function new();
        trans_type = WRITE;
        data       = 0;
        delay      = 0;
        full       = 0;
        empty      = 0;
        timestamp  = 0;
    endfunction

    // 深拷贝
    function fifo_transaction #(DATA_WIDTH) copy();
        copy = new();
        copy.trans_type = this.trans_type;
        copy.data       = this.data;
        copy.delay      = this.delay;
        copy.full       = this.full;
        copy.empty      = this.empty;
        copy.timestamp  = this.timestamp;
        return copy;
    endfunction

    // 比较（用于scoreboard）
    function bit compare(fifo_transaction #(DATA_WIDTH) other);
        return (this.data == other.data);
    endfunction

    // 打印信息
    function void print(string prefix = "");
        $display("%s[TRANS] type=%s data=0x%02h delay=%0d full=%b empty=%b @%0t",
                 prefix,
                 trans_type.name(),
                 data, delay, full, empty, timestamp);
    endfunction

endclass : fifo_transaction
