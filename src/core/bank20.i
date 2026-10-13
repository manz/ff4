"""
Bank $20 relocated-code pool. Include it in every module that uses `.alloc <name> in bank20_reloc`; identical pool
declarations merge.
"""


.pool bank20_reloc {
    range 0x208000 0x20FFFF
    strategy order
}
