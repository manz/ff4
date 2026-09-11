"""
Shared bank-20 relocated-code pool declaration.

Every module that wraps its body in `.alloc <name> in bank20_reloc { ... }`
must include this header so the pool is visible at the module's
codegen pass. Pool decls are idempotent across modules — the
linker dedupes identical ranges via `_merge_one_pool_decl`.
"""


; The ROM map travels with the pool, for the same reason: `.map` is per
; translation unit, an imported module does not inherit the
; patch-main's, and a pool in bank $20 needs that bank described where
; the module can see it. Identical decls are deduped by the linker.
.map identifier=1 bank_range=0x00, 0x6f addr_range=0x8000, 0xffff mask=0x8000 mirror_bank_range=0x80, 0xcf

.pool bank20_reloc {
    range 0x208000 0x20FFFF
    strategy order
}
