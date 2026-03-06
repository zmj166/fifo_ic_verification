// ============================================================================
// 文件名: fifo_full_empty_test.sv
// 描述:   满/空边界测试
// 场景:   写满FIFO，验证wfull；再读空FIFO，验证rempty
// ============================================================================

`include "fifo_base_test.sv"

class fifo_full_empty_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4)
    extends fifo_base_test #(DATA_WIDTH, ADDR_WIDTH);

    function new(string name,
                 virtual fifo_write_if #(DATA_WIDTH) w_vif,
                 virtual fifo_read_if  #(DATA_WIDTH) r_vif);
        super.new(name, w_vif, r_vif);
    endfunction

    virtual task run_sequences();
        fifo_full_seq  #(DATA_WIDTH) full_seq;
        fifo_empty_seq #(DATA_WIDTH) empty_seq;

        $display("[%s] Full/Empty Test: fill then drain", name);

        // 先写满
        full_seq = new("full_seq", env.wr_drv_mbx, FIFO_DEPTH);
        full_seq.run();

        #1000; // 等待同步延迟

        // 再读空
        empty_seq = new("empty_seq", env.rd_drv_mbx, FIFO_DEPTH);
        empty_seq.run();
    endtask

endclass : fifo_full_empty_test
