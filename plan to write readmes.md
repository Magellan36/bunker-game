Objective

Create documentation that allows a new AI agent to make routine modifications to the subsystem while reading the minimum possible amount of code.

The README should reduce required context—not duplicate implementation.

Do not explain every class.

Do not document implementation details.

Instead, document architectural boundaries, ownership, and navigation.

Template (Use for Every Subsystem)
# Overview

One paragraph describing the subsystem's purpose.

---

# Responsibilities

Bullet list.

What this subsystem owns.

---

# Does Not Own

Bullet list.

Explicitly list responsibilities belonging to other subsystems.

This section is mandatory.

---

# Architecture

High-level description only.

No implementation details.

Explain the flow of information and major components.

---

# Public API

List only the classes or interfaces intended for other subsystems.

Do not document every file.

---

# Data Ownership

Describe exactly what state belongs to this subsystem.

Avoid duplicate ownership.

---

# Dependencies

List legitimate subsystem dependencies.

Do not list implementation dependencies.

---

# Extension Points

Describe where developers should begin when:

- adding a feature
- adding a new implementation
- extending behavior

---

# Common Tasks

Examples:

Adding a new generator

Changing battery capacity

Adding a new NPC behavior

For each task, specify which files should be read.

---

# Common Mistakes

List frequent architectural mistakes.

Examples:

- storing data in the wrong subsystem
- bypassing public APIs
- introducing circular dependencies

---

# Files to Read First

Ordered list.

Only include the files required for understanding routine modifications.

Avoid listing the entire subsystem.
README Quality Checklist

A completed README should satisfy all of these:

It is under ~1000 words.
It documents ownership instead of implementation.
It minimizes AI context.
It clearly states subsystem boundaries.
It identifies extension points.
It tells the reader exactly where to begin.
A new AI should be able to perform 80% of routine changes after reading:
AI_CONTEXT.md
This README
2–5 source files.

I think this is a solid v1.0 package. It stays focused on your actual objective—reducing AI context while improving architectural understanding—without turning the repository into a documentation project. The philosophy and pillars provide stable guidance for you as the designer, AI_CONTEXT.md teaches every new agent how to work in the repository, and the subsystem READMEs become the localized navigation layer that keeps context usage low.