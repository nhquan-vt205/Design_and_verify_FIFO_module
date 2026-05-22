// =============================================================
//  [DEPRECATED] fifo_tests.sv
//  File này đã được thay thế bởi kiến trúc OOP mới.
//
//  Các test sequences cũ (task-based trong module) nay được
//  tái cấu trúc thành class-based sequences trong:
//
//    fifo_generator.sv → seq_fill_drain()     (thay test_fill_and_drain)
//                      → seq_overflow()        (thay test_overflow)
//                      → seq_underflow()       (thay test_underflow)
//                      → seq_simultaneous()    (thay test_simultaneous_rw)
//                      → seq_random()          (thay test_random)
//
//  Helper tasks cũ (write_one, read_one, idle, do_reset) nay được
//  xử lý bởi:
//    fifo_driver.sv  → protocol-level driving (1 txn per cycle)
//    fifo_tb.sv      → do_reset() task
//
//  Xem kiến trúc mới trong fifo_tb.sv.
// =============================================================
