class_name DebugOutput
## DebugOutput.gd — global master switch for ALL developer debug output.
## ─────────────────────────────────────────────────────────────────────────────
## Dev logging has accumulated across the project (wire registration prints,
## [GEN] generator logs, [ORACLE PASS] wire-verify checks, [PipeDebug], NPC
## activity logs, [SitSole] diagnostics, etc.). Each subsystem had its own
## const-DEBUG gate, and several were left ON — which floods the console /
## debugger bridge every frame and can be mistaken for in-game lag.
##
## This is the single kill-switch. Every debug helper (_wdbg/_pdbg/NPCDebug
## log_* functions) and direct dev print routes through DebugOutput.enabled
## instead of its own per-file const, so the F7 AdminMenu "Disable All Debug
## Outputs" button turns them ALL off at once. Off by keeping the flag true
## by default (current behavior); the F7 button toggles it.
##
## Explicit on-demand dumps (the F7 "Print ... Debug State" buttons, F9 wire
## dump) are deliberately NOT gated — those are deliberate user requests,
## not automatic flooding.
static var enabled: bool = true

## Prints only while the master switch is on. Route dev logging through this
## instead of raw print() so the single F7 switch truly silences everything.
static func out(msg: String) -> void:
	if enabled:
		print(msg)