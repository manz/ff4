"""Shared bank-20 relocated-code pool declaration.

Every module that wraps its body in `.alloc <name> in bank20_reloc { ... }`
must include this header so the pool is visible at the module's
codegen pass. Pool decls are idempotent across modules — the
linker dedupes identical ranges via `_merge_one_pool_decl`."""

.pool bank20_reloc {
    range 0x208000 0x20FFFF
    strategy order
}
