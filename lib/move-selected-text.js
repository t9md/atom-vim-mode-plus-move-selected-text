const {
  ensureBufferEndWithNewLine,
  extendLastBufferRowToRow,
  insertTextAtPoint,
  insertSpacesToPoint,
  isMultiLineSelection,
  repeatArray,
  replaceRange,
  rotateChars,
  rotateRows,
  setBufferRangesForBlockwiseSelection,
  rowCountForSelection,
} = require("./utils")

const StateManager = require("./state-manager")
const stateManager = new StateManager()

module.exports = function loadVmpCommands(getClass) {
  const Operator = getClass("Operator")

  class MoveOrDuplicateSelectedText extends Operator {
    isOverwriteMode() {
      return atom.config.get("vim-mode-plus-move-selected-text.overwrite")
    }

    getWise() {
      const {submode} = this.vimState
      return submode === "characterwise" && this.editor.getSelections().some(isMultiLineSelection)
        ? "linewise"
        : submode
    }

    getSelections() {
      const selections = this.editor.getSelectionsOrderedByBufferPosition()
      return this.direction === "down" ? selections.reverse() : selections
    }
  }
  MoveOrDuplicateSelectedText.commandScope = "atom-text-editor.vim-mode-plus.visual-mode"
  MoveOrDuplicateSelectedText.commandPrefix = "vim-mode-plus-user"

  // Move
  // -------------------------
  class MoveSelectedText extends MoveOrDuplicateSelectedText {
    getOverwrittenForSelection(selection) {
      return stateManager.get(this.editor).overwrittenBySelection.get(selection)
    }

    setOverwrittenForSelection(selection, overwritten) {
      return stateManager.get(this.editor).overwrittenBySelection.set(selection, overwritten)
    }

    getCount() {
      const count = super.getCount()
      if (this.direction === "up") {
        const startRow = this.editor.getSelectionsOrderedByBufferPosition()[0].getBufferRowRange()[0]
        return Math.min(count, startRow)
      } else {
        return count
      }
    }

    withGroupChanges(fn) {
      stateManager.resetIfNecessary(this.editor)
      this.editor.transact(fn)
      stateManager.groupChanges(this.editor)
    }

    moveSelections(fn) {
      this.countTimes(this.getCount(), () => {
        for (const selection of this.getSelections()) {
          fn(selection)
          this.swrap(selection).fixPropertyRowToRowRange()
        }
      })
    }

    execute() {
      this.withGroupChanges(() => {
        if (this.getWise() === "linewise") {
          let linewiseDisposable
          if (!this.vimState.isMode("visual", "linewise")) {
            linewiseDisposable = this.swrap.switchToLinewise(this.editor)
          }
          this.moveSelections(selection => this.moveLinewise(selection))
          if (linewiseDisposable) linewiseDisposable.dispose()
        } else {
          this.moveSelections(selection => this.moveCharacterwise(selection))
          for (const $selection of this.swrap.getSelections(this.editor)) {
            $selection.saveProperties()
          }
        }
      })
    }
  }

  class MoveSelectedTextUp extends MoveSelectedText {
    constructor(...args) {
      super(...args)
      this.direction = "up"
    }

    moveCharacterwise(selection) {
      // Swap srcRange with dstRange(the characterwise block one line above of current block)
      const srcRange = selection.getBufferRange()
      const dstRange = srcRange.translate([this.direction === "up" ? -1 : +1, 0])

      extendLastBufferRowToRow(this.editor, dstRange.end.row)
      insertSpacesToPoint(this.editor, dstRange.end)
      const srcText = this.editor.getTextInBufferRange(srcRange)
      let dstText = this.editor.getTextInBufferRange(dstRange)

      if (this.isOverwriteMode()) {
        const overwritten = this.getOverwrittenForSelection(selection) || new Array(srcText.length).fill(" ")
        this.setOverwrittenForSelection(selection, dstText.split(""))
        dstText = overwritten.join("")
      }

      this.editor.setTextInBufferRange(srcRange, dstText)
      this.editor.setTextInBufferRange(dstRange, srcText)
      selection.setBufferRange(dstRange, {reversed: selection.isReversed()})
    }

    moveLinewise(selection) {
      const translation = this.direction === "up" ? [[-1, 0], [0, 0]] : [[0, 0], [1, 0]]
      const rangeToMutate = selection.getBufferRange().translate(...translation)
      extendLastBufferRowToRow(this.editor, rangeToMutate.end.row)
      const newRange = replaceRange(this.editor, rangeToMutate, text => this.rotateRows(text, selection))
      const rangeToSelect = newRange.translate(...translation.reverse())
      selection.setBufferRange(rangeToSelect, {reversed: selection.isReversed()})
    }

    rotateRows(text, selection) {
      const rows = text.replace(/\n$/, "").split("\n")

      let overwritten
      if (this.isOverwriteMode()) {
        overwritten = this.getOverwrittenForSelection(selection) || new Array(rows.length - 1).fill("")
      }

      const result = rotateRows(rows, this.direction, {overwritten})
      {
        const {rows, overwritten} = result
        if (overwritten.length) this.setOverwrittenForSelection(selection, overwritten)
        return rows.join("\n") + "\n"
      }
    }
  }

  class MoveSelectedTextDown extends MoveSelectedTextUp {
    constructor(...args) {
      super(...args)
      this.direction = "down"
    }
  }

  class MoveSelectedTextLeft extends MoveSelectedText {
    constructor(...args) {
      super(...args)
      this.direction = "left"
    }

    moveCharacterwise(selection) {
      if (this.direction === "left" && selection.getBufferRange().start.column === 0) {
        return
      }
      const translation = this.direction === "right" ? [[0, 0], [0, 1]] : [[0, -1], [0, 0]]
      const rangeToMutate = selection.getBufferRange().translate(...translation)
      insertSpacesToPoint(this.editor, rangeToMutate.end)
      const newRange = replaceRange(this.editor, rangeToMutate, text => this.rotateChars(text, selection))
      const rangeToSelect = newRange.translate(...translation.reverse())
      selection.setBufferRange(rangeToSelect, {reversed: selection.isReversed()})
    }

    rotateChars(text, selection) {
      let chars = text.split("")

      let overwritten
      if (this.isOverwriteMode()) {
        overwritten = this.getOverwrittenForSelection(selection) || new Array(chars.length - 1).fill(" ")
      }

      const result = rotateChars(chars, this.direction, {overwritten})
      {
        const {chars, overwritten} = result
        if (overwritten.length) this.setOverwrittenForSelection(selection, overwritten)
        return chars.join("")
      }
    }

    moveLinewise(selection) {
      if (this.direction === "left") {
        selection.outdentSelectedRows()
      } else {
        selection.indentSelectedRows()
      }
    }
  }

  class MoveSelectedTextRight extends MoveSelectedTextLeft {
    constructor(...args) {
      super(...args)
      this.direction = "right"
    }
  }

  // Duplicate
  // -------------------------
  class DuplicateSelectedText extends MoveOrDuplicateSelectedText {
    duplicateSelectionsLinewise() {
      let linewiseDisposable
      if (!this.vimState.isMode("visual", "linewise")) {
        linewiseDisposable = this.swrap.switchToLinewise(this.editor)
      }
      for (const selection of this.getSelections()) {
        this.duplicateLinewise(selection)
        this.swrap(selection).fixPropertyRowToRowRange()
      }
      if (linewiseDisposable) linewiseDisposable.dispose()
    }
  }

  class DuplicateSelectedTextUp extends DuplicateSelectedText {
    constructor(...args) {
      super(...args)
      this.direction = "up"
    }

    getBlockwiseSelections() {
      const blockwiseSelections = this.vimState.getBlockwiseSelectionsOrderedByBufferPosition()
      return this.direction === "down" ? blockwiseSelections.reverse() : blockwiseSelections
    }

    execute() {
      this.editor.transact(() => {
        if (this.getWise() === "linewise") {
          this.duplicateSelectionsLinewise()
        } else {
          const wasCharacterwise = this.vimState.isMode("visual", "characterwise")
          if (wasCharacterwise) {
            this.vimState.activate("visual", "blockwise")
          }

          for (const blockwiseSelection of this.getBlockwiseSelections()) {
            this.duplicateBlockwise(blockwiseSelection)
          }
          for (const $selection of this.swrap.getSelections(this.editor)) {
            $selection.saveProperties()
          }

          const isOneHeight = blockwiseSelection => blockwiseSelection.getHeight() === 1
          if (wasCharacterwise && this.vimState.getBlockwiseSelections().every(isOneHeight)) {
            this.vimState.activate("visual", "characterwise")
          }
        }
      })
    }

    getCountForSelection(selectionOrBlockwiseSelection) {
      const count = this.getCount()
      if (this.isOverwriteMode() && this.direction === "up") {
        const startRow = selectionOrBlockwiseSelection.getBufferRowRange()[0]
        const countMax = Math.floor(startRow / rowCountForSelection(selectionOrBlockwiseSelection))
        return Math.min(countMax, count)
      } else {
        return count
      }
    }

    duplicateLinewise(selection) {
      const count = this.getCountForSelection(selection)
      if (!count) return

      let selectedText = selection.getText()
      if (!selectedText.endsWith("\n")) selectedText += "\n"

      const newText = selectedText.repeat(count)
      const height = rowCountForSelection(selection) * count

      let {start, end} = selection.getBufferRange()
      if (this.direction === "down") {
        if (end.isEqual(this.editor.getEofBufferPosition())) {
          end = ensureBufferEndWithNewLine(this.editor)
        }
      }

      const rangeToMutate =
        this.direction === "up"
          ? this.isOverwriteMode() ? [start.translate([-height, 0]), start] : [start, start]
          : this.isOverwriteMode() ? [end, end.translate([+height, 0])] : [end, end]

      const newRange = this.editor.setTextInBufferRange(rangeToMutate, newText)
      selection.setBufferRange(newRange, {reversed: selection.isReversed()})
    }

    duplicateBlockwise(blockwiseSelection) {
      const count = this.getCountForSelection(blockwiseSelection)
      if (!count) return

      const [startRow, endRow] = blockwiseSelection.getBufferRowRange()
      const height = blockwiseSelection.getHeight() * count

      let insertionStartRow
      if (this.isOverwriteMode()) {
        insertionStartRow = this.direction === "up" ? startRow - height : endRow + 1
        extendLastBufferRowToRow(this.editor, insertionStartRow + height)
      } else {
        insertionStartRow = this.direction === "up" ? startRow : endRow + 1
        insertTextAtPoint(this.editor, [insertionStartRow, 0], "\n".repeat(height))
      }

      const newRanges = []
      const selectionsOrderd = blockwiseSelection.selections.sort((a, b) => a.compare(b))
      for (const selection of repeatArray(selectionsOrderd, count)) {
        const {start, end} = selection.getBufferRange()
        start.row = end.row = insertionStartRow
        insertionStartRow++
        insertSpacesToPoint(this.editor, start)
        newRanges.push(this.editor.setTextInBufferRange([start, end], selection.getText()))
      }

      setBufferRangesForBlockwiseSelection(blockwiseSelection, newRanges)
    }
  }

  class DuplicateSelectedTextDown extends DuplicateSelectedTextUp {
    constructor(...args) {
      super(...args)
      this.direction = "down"
    }
  }

  class DuplicateSelectedTextLeft extends DuplicateSelectedText {
    constructor(...args) {
      super(...args)
      this.direction = "left"
    }

    execute() {
      this.editor.transact(() => {
        if (this.getWise() === "linewise") {
          this.duplicateSelectionsLinewise()
        } else {
          for (const selection of this.getSelections()) {
            this.duplicateCharacterwise(selection)
          }
        }
      })
    }

    // No behavior diff by isOverwriteMode() and direction('left' or 'right')
    duplicateLinewise(selection) {
      const amount = this.getCount() + 1
      const rows = selection
        .getText()
        .split("\n")
        .map(row => row.repeat(amount))
      selection.insertText(rows.join("\n"), {select: true})
    }

    // Return adjusted count to avoid partial duplicate in overwrite-mode
    getCountForSelection(selection) {
      const count = this.getCount()
      if (this.isOverwriteMode() && this.direction === "left") {
        const {start} = selection.getBufferRange()
        const countMax = Math.floor(start.column / selection.getText().length)
        return Math.min(countMax, count)
      } else {
        return count
      }
    }

    duplicateCharacterwise(selection) {
      const count = this.getCountForSelection(selection)
      if (!count) return

      const newText = selection.getText().repeat(count)
      const width = newText.length
      const {start, end} = selection.getBufferRange()
      const rangeToMutate =
        this.direction === "left"
          ? this.isOverwriteMode() ? [start.translate([0, -width]), start] : [start, start]
          : this.isOverwriteMode() ? [end, end.translate([0, width])] : [end, end]
      const newRange = this.editor.setTextInBufferRange(rangeToMutate, newText)
      selection.setBufferRange(newRange, {reversed: selection.isReversed()})
    }
  }

  class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft {
    constructor(...args) {
      super(...args)
      this.direction = "right"
    }
  }

  return {
    stateManager,
    commands: {
      MoveSelectedTextUp,
      MoveSelectedTextDown,
      MoveSelectedTextLeft,
      MoveSelectedTextRight,

      DuplicateSelectedTextUp,
      DuplicateSelectedTextDown,
      DuplicateSelectedTextLeft,
      DuplicateSelectedTextRight,
    },
  }
}
