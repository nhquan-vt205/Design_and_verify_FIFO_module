// =============================================================
//  CLASS: fifo_driver
//  Nhận fifo_transaction từ gen2drv mailbox → drive DUT pins.
//
//  Giao thức timing:
//    1 transaction = 1 chu kỳ clock
//    Khi có txn: @(posedge clk) → #1 → gán wr_en/rd_en/din
//    Khi mailbox rỗng: tự de-assert wr_en/rd_en về 0 (idle)
//
//  Không dùng virtual interface:
//    run() nhận ref trỏ trực tiếp đến signal của module fifo_tb.
//    Kỹ thuật này tương đương virtual interface ở mức cơ bản.
//
//  Timing đúng với DUT:
//    - Driver set wr_en/din tại posedge+#1 (sau rising edge)
//    - DUT latch tín hiệu ở posedge tiếp theo
//    - Monitor quan sát tại posedge → thấy giá trị driver đã set
//      ở cycle TRƯỚC → đồng bộ với DUT ✓
// =============================================================

class fifo_driver;

    mailbox #(fifo_transaction) gen2drv;
    int txn_count;

    function new(mailbox #(fifo_transaction) mb);
        gen2drv   = mb;
        txn_count = 0;
    endfunction

    // ----------------------------------------------------------
    // run() — vòng lặp drive vô tận
    //   Gọi trong: fork drv.run(...); join_none
    //   ref params: trỏ trực tiếp đến signal của module fifo_tb
    // ----------------------------------------------------------
    task run(
        ref logic       clk,
        ref logic       rst_n,
        ref logic       wr_en,
        ref logic       rd_en,
        ref logic [7:0] din,
        ref logic       full,
        ref logic       empty
    );
        fifo_transaction txn;

        // Khởi tạo idle (an toàn trước khi reset deassert)
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = 8'h00;

        forever begin
            @(posedge clk); #1;  // đồng bộ rising edge + setup delay #1
            if (rst_n && gen2drv.try_get(txn)) begin
                // Có txn mới → drive DUT theo txn
                wr_en = txn.wr_en;
                rd_en = txn.rd_en;
                din   = txn.din;
                txn_count++;
            end else begin
                // Mailbox rỗng hoặc đang reset → idle DUT
                wr_en = 1'b0;
                rd_en = 1'b0;
            end
        end
    endtask

    function void report();
        $display("[DRV] Total transactions driven: %0d", txn_count);
    endfunction

endclass
