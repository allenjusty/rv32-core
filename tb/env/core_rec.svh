// One trace record: a retired instruction (R) or a trap (T).
// to_string() gives exactly the expected-trace file format, so a record from the RTL
// and a line from the Spike trace can be compared as text.
class core_rec extends uvm_object;
  `uvm_object_utils(core_rec)

  bit          is_trap;
  bit [31:0]   pc, insn;
  bit          rd_we;
  bit [4:0]    rd;
  bit [31:0]   rd_val;
  bit          st_valid;
  bit [31:0]   st_addr, st_data;
  bit [1:0]    st_size;
  bit          csr_valid;
  bit [11:0]   csr_addr;
  bit [31:0]   csr_val;
  bit [31:0]   cause, epc, tval;

  function new(string name = "core_rec");
    super.new(name);
  endfunction

  virtual function string convert2string();
    string rd_s, st_s, csr_s;
    if (is_trap) return $sformatf("T %0d %08x %08x", cause, epc, tval);
    rd_s  = rd_we     ? $sformatf("%0d:%08x", rd, rd_val) : "-";
    st_s  = st_valid  ? $sformatf("%08x:%08x:%0d", st_addr, st_data, st_size) : "-";
    csr_s = csr_valid ? $sformatf("%03x:%08x", csr_addr, csr_val) : "-";
    return $sformatf("R %08x %08x %s %s %s", pc, insn, rd_s, st_s, csr_s);
  endfunction
endclass
