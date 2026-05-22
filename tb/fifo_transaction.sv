// =============================================================
//  CLASS: fifo_transaction
//  Đối tượng kích thích (stimulus object) — 1 txn = 1 chu kỳ clock.
//
//  Luồng: Generator tạo → mailbox gen2drv → Driver drive DUT.
//
//  Trường dữ liệu:
//    rand wr_en — write enable (bias 70% active)
//    rand rd_en — read  enable (bias 70% active)
//    rand din   — dữ liệu ghi vào (8-bit)
// =============================================================

class fifo_transaction;

    rand logic       wr_en;
    rand logic       rd_en;
    rand logic [7:0] din;

    // Bias về phía active để test nhanh đến biên full/empty
    constraint activity_c {
        wr_en dist {1 := 70, 0 := 30};
        rd_en dist {1 := 70, 0 := 30};
    }

    // Deep copy — tránh aliasing khi put vào mailbox
    function fifo_transaction copy();
        fifo_transaction t = new();
        t.wr_en = this.wr_en;
        t.rd_en = this.rd_en;
        t.din   = this.din;
        return t;
    endfunction

    function void print(string tag = "TXN");
        $display("[%s] wr_en=%0b  rd_en=%0b  din=0x%02h",
                 tag, wr_en, rd_en, din);
    endfunction

endclass
