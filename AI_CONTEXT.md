# AI Context

This document provides repository-wide context for AI coding agents.

Read this document before modifying any code.

Then read only the README for the subsystem being modified.

---

# Project Overview

Bunker Game is a Godot 4 colony survival game centered on building and maintaining a bunker before and after the collapse of civilization.

The project prioritizes meaningful tradeoffs, interconnected systems, and emergent gameplay over strict realism.

Simulation exists to create interesting decisions.

---

# Development Priorities

Priority order:

1. Preserve subsystem boundaries.
2. Keep implementations simple.
3. Reduce coupling.
4. Reuse existing architecture.
5. Maintain readability.

---

# Workflow

Before implementing:

1. Read AI_CONTEXT.md.
2. Read the subsystem README.
3. Read only the files required.
4. Expand outward only when dependencies require it.

Do not search the repository unless necessary.

---

# Architectural Rules

- Each subsystem owns its own state.
- Prefer composition over inheritance.
- Prefer signals/events over direct cross-system references.
- Avoid introducing new Autoloads.
- Preserve stable public APIs.
- Extend existing systems before creating new ones.

---

# Coding Standards

- Typed GDScript.
- Small focused functions.
- Avoid duplicate logic.
- Clear naming.
- Comment intent.
- Refactor instead of endlessly extending large classes.

---

# Never Assume

If ownership or behavior is unclear, consult the subsystem README or request clarification.

Do not infer architecture from filenames.

---

# Refactoring Preference

When adding functionality:

1. Extend existing abstractions.
2. Extract reusable code.
3. Avoid introducing new managers without strong justification.

---

# Context Budget

Always attempt to solve the task using the minimum reasonable amount of repository context.

Expand incrementally.

Consult subsystem documentation before searching code.

---

# When to Stop

Stop implementation if:

- Multiple subsystem boundaries are unexpectedly crossed.
- Architecture becomes unclear.
- Ownership conflicts arise.

Recommend discussion instead of making architectural assumptions.

---

# Goal

Produce correct, maintainable changes while minimizing repository context consumption.