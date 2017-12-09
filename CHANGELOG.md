## 0.12.0:
- Maintenance: Catchup vmp changes, no longer use service.Base, use getClass instead.

## 0.11.1:
- Maintenance: Catchup minor vmp changes, and update broken specs.

## 0.11.0:
- Maintenance: Convert all code(except test) to JavaScript from CoffeeScript.
  - Now all operation classes are ES6 class.
  - Prep for upcoming vmp changes(ES6-class-based-vmp-operations), since CoffeeScript's class cannot inherit from ES6 class.

## 0.10.0
- Use `activationCommands` to reduce startup time of atom.

## 0.9.0
- Fix to work in vmp v0.85 or later. This version is not work in v0.84.1 and older version.

## 0.8.2
- Fix: down/up move, duplicate in `visual-characterwise` mode.
  - Need to update vim-mode-plus 0.84.1 or later.

## 0.8.1
- Internal: Refactoring. DONE!!
- Spec: Add complex movement with overwrite=true and undo grouping behavior.

## 0.8.0
- Internal: Rewrote from scratch for maintainability. Fix corner case bug.

## 0.7.0
- Fix: Still not perfect but now works in latest vim-mode-plus(v0.80.0).

## 0.6.2
- Fix: Deprecation warning for use of `::shadow`. #2

## 0.6.1
- Minor change.

## 0.6.0
- Improve: Use new concise keystroke format for spec.
- Breaking: Rename `toggle-overwrite` to `move-selected-text-toggle-overwrite`.

## 0.5.0
- Update to support vmp v0.33.0

## 0.4.1
- Fix: linewise move-down didn't extend EOF.
- Spec: Add spec 30% done.

## 0.4.0
- New: full support duplicate operation.

## 0.3.0
- New: Support overwrite mode.
- Improve: Lots of bug fix, refactoring.

## 0.2.0 - Improve
- Improve: blockwise movement.

## 0.1.0 - Initial release
- created
