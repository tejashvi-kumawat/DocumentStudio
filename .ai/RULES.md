# AI Development Rules — Document Studio

Mandatory for ALL AI coding agents.

These rules override the tendency to implement isolated buttons, minimal demos, scaffolds, or partial feature slices.

---

# 1. PRODUCT DEVELOPMENT PHILOSOPHY

Document Studio is a complete professional document application.

DO NOT implement features as isolated:
- buttons
- dialogs
- upload → process → download screens
- minimal proof-of-concepts
- backend-only functionality
- engine-only functionality
- UI-only mockups

Every feature must be developed as a COMPLETE USER WORKFLOW.

A feature is not "done" because its underlying engine works.

A feature is not "done" because a UI screen exists.

A feature is not "done" because one happy-path test passes.

A feature is DONE only when the complete feature experience works end-to-end.

---

# 2. FEATURE-FIRST DEVELOPMENT IS MANDATORY

The Lead agent MUST select a FEATURE GROUP and finish it completely before moving to another major feature group.

DO NOT scatter implementation across dozens of unrelated features.

Preferred execution:

1. Select one feature group.
2. Read its complete feature specification.
3. Read every related inventory/checklist item.
4. Identify all dependencies.
5. Design the complete UX.
6. Implement the complete UI.
7. Implement the domain/application layer.
8. Implement the engine/native integration.
9. Implement all related interactions.
10. Implement error/loading/empty/progress states.
11. Implement desktop/mobile/tablet behavior.
12. Implement keyboard/touch/drag interactions.
13. Implement tests.
14. Perform actual visual UX review.
15. Verify all related checklist items.
16. Only then mark the feature group complete.
17. Then move to the next feature group.

Do NOT mark a feature complete while substantial parts of the user workflow are missing.

---

# 3. FEATURE COMPLETENESS GATE

Before marking ANY feature `[x]`, verify ALL of the following:

## Product
- Complete user workflow exists.
- Feature is discoverable.
- Related operations are logically grouped.
- Feature does not expose unnecessary technical complexity.

## UX
- Desktop UX implemented.
- Tablet UX implemented.
- Mobile UX implemented where applicable.
- Drag and drop implemented where applicable.
- Multi-selection implemented where applicable.
- Range selection implemented where applicable.
- Touch interactions implemented where applicable.
- Keyboard shortcuts implemented where applicable.
- Context menus implemented where applicable.
- Undo/redo implemented where applicable.
- Preview implemented where useful.
- Progress indication implemented.
- Cancellation implemented.
- Empty state implemented.
- Loading state implemented.
- Error state implemented.
- Success/completion state implemented.
- Confirmation flows implemented where destructive.
- Save/export flow implemented.

## UI
- Professional visual hierarchy.
- Consistent spacing.
- Consistent typography.
- Consistent icons.
- Consistent buttons and controls.
- Proper responsive layout.
- No accidental overflow.
- No giant empty areas.
- No cramped controls.
- No random buttons scattered across screens.
- No developer-looking placeholder UI.
- No unnecessary dialogs.
- No feature-specific UI that contradicts the global design system.

## Engineering
- Domain layer implemented.
- Application/use-case layer implemented.
- Engine/adapter implemented.
- Tool registered in ToolRegistry.
- Platform integration implemented where required.
- Proper job/progress/cancellation handling.
- Real file processing implemented.

## Reliability
- Unit tests.
- Widget tests.
- Integration tests where appropriate.
- Error handling.
- Malformed/invalid input handling.
- Large-file handling.
- Permission/file-lock handling.
- Disk-full handling where applicable.
- Cancellation testing.

## Privacy/Security
- No document content in logs.
- No unnecessary network access.
- Secure handling of temporary files.
- Security implications reviewed.
- Destructive operations handled safely.

## Documentation
- Feature specification updated.
- Architecture documentation updated.
- ADR created/updated if required.
- Dependency documentation updated.
- CHECKLIST updated.
- Platform matrix updated.

ONLY AFTER ALL OF THESE PASS MAY `[x]` BE USED.

---

# 4. DO NOT BUILD "MINIMAL FEATURE SCREENS"

NEVER implement this pattern:

Home
→ Click "Merge PDF"
→ Upload files
→ Merge
→ Download

That is only the engine happy path.

Instead, build a complete document workspace.

For example, PDF page organization should support the complete workflow:

- drag files into the workspace
- browse/import files
- multi-file selection
- thumbnails
- page selection
- select all
- range selection
- Ctrl/Cmd selection
- Shift selection
- drag reorder
- cross-document page movement
- duplicate
- delete
- rotate
- extract
- insert
- replace
- blank page
- split
- reverse
- odd/even operations
- page preview
- page numbering where applicable
- undo/redo
- keyboard shortcuts
- context menu
- zoom
- search
- output configuration
- preview before export
- progress
- cancellation
- error recovery
- save/export

The exact operations depend on the feature specification, but the principle applies to EVERY feature.

---

# 5. UI/UX IS A CORE DELIVERABLE

UI/UX MUST NOT be treated as final polish.

For every feature, UX design begins BEFORE implementation.

The agent must ask internally:

"What is the complete workflow a real user would expect?"

Not:

"What button can I add to expose this API?"

The application should feel like a coherent professional document workstation rather than a collection of independent utilities.

---

# 6. DOCUMENT WORKSPACE PRINCIPLE

Where multiple document operations are related, prefer a unified workspace over separate upload screens.

For example:

PDF organization should use a workspace containing:

- document tabs
- file/document area
- page thumbnails
- main preview
- selection state
- contextual toolbar
- right-side properties/actions where appropriate
- drag/drop targets
- context menus
- bottom/status/progress area where appropriate

Avoid repeatedly forcing the user through:

"Open feature → Upload → Process → Back → Open another feature → Upload again."

Reuse documents and workspace state whenever logically possible.

---

# 7. DRAG & DROP

Desktop document workflows MUST support drag and drop wherever it is natural.

Examples:

- files → application
- files → workspace
- pages → reorder
- pages → another document
- pages → insert position
- images → document
- files → batch queue
- annotations/objects → reposition
- workflow actions → reorder

Drag/drop must have proper:
- hover state
- drop target state
- insertion indicator
- invalid-drop feedback
- cancellation/recovery behavior

Do not merely implement `onDrop` without designing the interaction.

---

# 8. SELECTION SYSTEM

Selection is a first-class interaction.

Where applicable, support:

- single selection
- multi-selection
- select all
- deselect
- Ctrl/Cmd selection
- Shift/range selection
- marquee selection where useful
- selection count
- contextual actions
- keyboard navigation
- touch selection on mobile/tablet

Selected items must have a clear visual state.

---

# 9. FEATURE GROUPS

Treat related checklist items as ONE cohesive product feature.

Examples:

### PDF Viewer
Must be developed as a complete viewer experience, not just "render PDF".

### Page Organization
Merge/split/extract/delete/reorder/insert/replace/duplicate/rotate/etc. must be treated as one cohesive page-management workspace.

### Compression
Compression is not just "compress PDF".
It includes:
- profile selection
- estimated output size
- quality tradeoffs
- image handling
- statistics
- preview where appropriate
- progress
- cancellation
- output handling
- errors

### OCR
OCR is not just "run Tesseract".
It includes:
- source selection
- language selection
- preprocessing
- preview
- correction where specified
- searchable PDF generation
- progress
- cancellation
- batch handling
- output verification

### Annotations
Annotations are not just drawing rectangles.
Implement the complete annotation workflow defined by the specification.

### Forms
Forms are not just field detection.
Implement detection, selection, editing/filling, navigation, validation, flattening, save/export, etc. according to the specification.

### Security
Encryption, permissions, password workflows, redaction, metadata removal, warnings, verification, etc. must be treated as complete workflows.

---

# 10. AGENT ASSIGNMENT RULE

The Lead must NOT assign one agent to every tiny checklist row.

Instead, assign agents to coherent feature groups.

BAD:

Agent 1 → merge button
Agent 2 → split button
Agent 3 → rotate button
Agent 4 → thumbnail button

GOOD:

Agent 1 → Complete PDF Page Organization Workspace

That agent owns the complete user workflow and coordinates its engine/UI/test dependencies.

---

# 11. PARALLELISM

Parallelism is allowed ONLY between independent feature groups.

Do not sacrifice feature completeness merely to increase agent count.

The Lead should maintain approximately 8–15 active agents when sufficient independent feature groups exist.

However:

DO NOT split one feature into many conflicting agents unless ownership is explicitly defined.

For one active feature group, use supporting agents for:
- engine
- UI
- tests
- platform integration
- UX review

with one Lead/feature owner coordinating them.

---

# 12. UI/UX REVIEW AGENT

Every major feature MUST have a dedicated UX review before completion.

The UX reviewer must actually inspect the running application and identify:

- missing interactions
- poor navigation
- missing selection
- missing drag/drop
- poor information hierarchy
- excessive dialogs
- confusing terminology
- inconsistent controls
- bad spacing
- poor responsive behavior
- missing empty/loading/error states
- missing shortcuts
- missing contextual actions
- unnecessary navigation
- inconsistent design

"Looks okay" is NOT an acceptable UX review.

---

# 13. VISUAL QA

Agents must run the actual application.

Do not judge UI quality from source code alone.

Verify:
- desktop
- tablet
- mobile
- light theme
- dark theme
- small window
- large window
- long filenames
- many pages
- many documents
- empty states
- loading states
- errors
- large PDFs

Fix problems discovered during visual QA before marking the feature complete.

---

# 14. FEATURE CHECKLIST RULE

The checklist is an EXECUTION GATE, not merely documentation.

Before starting a feature:
- read every related checklist item
- identify the complete scope

During implementation:
- update progress

Before completion:
- verify every related checklist item

Only then:
- mark `[x]`

Never mark individual pieces `[x]` when the overall feature experience remains incomplete.

---

# 15. DO NOT MOVE FORWARD PREMATURELY

If the current feature is incomplete:

DO NOT start unrelated major features simply because another agent is idle.

Instead:
- improve the current feature
- complete missing UX
- complete missing interactions
- complete tests
- perform visual QA
- fix edge cases
- finish documentation

The objective is COMPLETE FEATURES, not maximum number of changed files.

---

# 16. ARCHITECTURE

1. Read `docs/MASTER-SPECIFICATION.md` before major changes.
2. Read `docs/DECISIONS.md` before modifying engines/dependencies.
3. Preserve architectural layers.
4. No PDFium/qpdf/Tesseract calls from widgets.
5. Register tools in the ToolRegistry.
6. No one-off processing scripts in `lib/features/`.
7. Never silently change architecture.
8. Create/update ADRs for architectural changes.

---

# 17. PRODUCT CONSTRAINTS

Never violate without explicit written approval:

- No backend.
- No cloud processing.
- No document upload.
- No LLM/local AI.
- No ads.
- No paywall.
- Core features remain free.
- Privacy-first.
- No document content in logs/analytics.

Distinguish clearly:
- overlay editing vs true PDF editing
- visual signature vs cryptographic signature
- simulated capability vs real capability

Never fake functionality.

---

# 18. DEPENDENCIES

No new dependency without:
- purpose
- license
- platform support
- integration method
- architecture justification

Reject by default:
- GPL
- AGPL
- LGPL static linking
- Syncfusion as core engine
- Ghostscript in application binary

---

# 19. TESTING

Every completed feature must have appropriate:

- unit tests
- widget tests
- integration tests
- regression tests
- corpus tests where applicable
- malformed-input tests
- cancellation tests
- large-file tests where applicable

---

# 20. DEFINITION OF DONE

A feature is DONE only when:

USER CAN DISCOVER IT
→ USER CAN IMPORT/OPEN DATA
→ USER CAN INTERACT WITH IT
→ USER CAN SELECT/MANIPULATE IT
→ USER CAN PREVIEW IT
→ USER CAN CONFIGURE IT
→ ENGINE PERFORMS REAL OPERATION
→ PROGRESS IS SHOWN
→ USER CAN CANCEL
→ ERRORS ARE HANDLED
→ RESULT IS VERIFIED
→ USER CAN SAVE/EXPORT
→ WORKFLOW IS TESTED
→ UI/UX IS REVIEWED
→ DOCUMENTATION IS UPDATED
→ CHECKLIST EXIT CRITERIA ARE SATISFIED

If any important part is missing, the feature is NOT DONE.

---

# 21. PHASE 0 AUTHORIZATION

Do not independently create engine dependencies, native plugin implementations, or change blocking architecture decisions before the documented decisions D-01, D-02, D-03, D-05 and D-10 are resolved, unless the project owner explicitly authorizes Phase 0.

Respect the existing master specification and decision records.

---

# 22. PRIMARY OBJECTIVE

Build a complete professional Document Studio.

Do not optimize for:
- number of commits
- number of files changed
- number of buttons
- number of agents used
- number of checklist rows superficially marked complete

Optimize for:

COMPLETE, COHERENT, POLISHED USER FEATURES.