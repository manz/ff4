"""
Final Fantasy IV, French translation.

The root imports one module per area; each pulls in the rest of its area. a816 links every imported module, and
each module gates its own code on its feature flags (a816.toml [defines]).
"""

.import "system"
.import "intro"
.import "minimal_vwf_patches"
.import "ingame"
.import "battle"
.import "debug"
