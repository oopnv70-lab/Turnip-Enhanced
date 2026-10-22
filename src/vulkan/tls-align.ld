SECTIONS
{
  .tdata : ALIGN(64) { *(.tdata .tdata.*) }
  .tbss : ALIGN(64) { *(.tbss .tbss.*) }
}
INSERT AFTER .bss;
