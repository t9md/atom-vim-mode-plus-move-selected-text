{
  ensureBufferEndWithNewLine
  extendLastBufferRowToRow
  insertTextAtPoint
  insertSpacesToPoint
  isMultiLineSelection
  repeatArray
  replaceRange
  requireFrom
  rotateChars
  rotateRows
  setBufferRangesForBlockwiseSelection
  rowCountForSelection
} = require './utils'
swrap = {switchToLinewise} = requireFrom('vim-mode-plus', 'selection-wrapper')

Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

StateManager = require './state-manager'
stateManager = new StateManager()

class MoveOrDuplicateSelectedText extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'

  isOverwriteMode: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  getWise: ->
    {submode} = @vimState
    if submode is 'characterwise' and @editor.getSelections().some(isMultiLineSelection)
      'linewise'
    else
      submode

  getSelections: ->
    selections = @editor.getSelectionsOrderedByBufferPosition()
    if @direction is 'down'
      selections.reverse()
    selections

# Move
# -------------------------
class MoveSelectedText extends MoveOrDuplicateSelectedText
  getOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.get(selection)

  setOverwrittenForSelection: (selection, overwritten) ->
    stateManager.get(@editor).overwrittenBySelection.set(selection, overwritten)

  getCount: ->
    count = super
    if @direction is 'up'
      startRow = @editor.getSelectionsOrderedByBufferPosition()[0].getBufferRowRange()[0]
      Math.min(count, startRow)
    else
      count

  withGroupChanges: (fn) ->
    stateManager.resetIfNecessary(@editor)
    @editor.transact(fn)
    stateManager.groupChanges(@editor)

  moveSelections: (fn) ->
    @countTimes @getCount(), =>
      for selection in @getSelections()
        fn(selection)
        swrap(selection).saveProperties()
        swrap(selection).fixPropertyRowToRowRange()

  execute: ->
    @withGroupChanges =>
      if @getWise() is 'linewise'
        linewiseDisposable = switchToLinewise(@editor) unless @vimState.isMode('visual', 'linewise')
        @moveSelections(@moveLinewise.bind(this))
        linewiseDisposable?.dispose()
      else
        @moveSelections(@moveCharacterwise.bind(this))

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  moveCharacterwise: (selection) ->
    # Swap srcRange with dstRange(the characterwise block one line above of current block)
    srcRange = selection.getBufferRange()
    dstRange = switch @direction
      when 'up' then srcRange.translate([-1, 0])
      when 'down' then srcRange.translate([+1, 0])

    extendLastBufferRowToRow(@editor, dstRange.end.row)
    insertSpacesToPoint(@editor, dstRange.end)
    srcText = @editor.getTextInBufferRange(srcRange)
    dstText = @editor.getTextInBufferRange(dstRange)

    if @isOverwriteMode()
      overwritten = @getOverwrittenForSelection(selection) ? new Array(srcText.length).fill(' ')
      @setOverwrittenForSelection(selection, dstText.split(''))
      dstText = overwritten?.join('')

    @editor.setTextInBufferRange(srcRange, dstText)
    @editor.setTextInBufferRange(dstRange, srcText)
    selection.setBufferRange(dstRange, reversed: selection.isReversed())

  moveLinewise: (selection) ->
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]

    rangeToMutate = selection.getBufferRange().translate(translation...)
    extendLastBufferRowToRow(@editor, rangeToMutate.end.row)
    newRange = replaceRange(@editor, rangeToMutate, (text) => @rotateRows(text, selection))
    rangeToSelect = newRange.translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, reversed: selection.isReversed())

  rotateRows: (text, selection) ->
    rows = text.replace(/\n$/, '').split("\n")

    if @isOverwriteMode()
      overwritten = @getOverwrittenForSelection(selection) ? new Array(rows.length - 1).fill('')

    {rows, overwritten} = rotateRows(rows, @direction, {overwritten})
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    rows.join("\n") + "\n"

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  direction: 'left'

  moveCharacterwise: (selection) ->
    if @direction is 'left' and selection.getBufferRange().start.column is 0
      return

    translation = switch @direction
      when 'right' then [[0, 0], [0, 1]]
      when 'left' then [[0, -1], [0, 0]]

    rangeToMutate = selection.getBufferRange().translate(translation...)
    insertSpacesToPoint(@editor, rangeToMutate.end)
    newRange = replaceRange(@editor, rangeToMutate, (text) => @rotateChars(text, selection))
    rangeToSelect = newRange.translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, reversed: selection.isReversed())

  rotateChars: (text, selection) ->
    chars = text.split('')

    if @isOverwriteMode()
      overwritten = @getOverwrittenForSelection(selection) ? new Array(chars.length - 1).fill(' ')

    {chars, overwritten} = rotateChars(chars, @direction, {overwritten})
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    chars.join('')

  moveLinewise: (selection) ->
    switch @direction
      when 'left'
        selection.outdentSelectedRows()
      when 'right'
        selection.indentSelectedRows()

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

# Duplicate
# -------------------------
class DuplicateSelectedText extends MoveOrDuplicateSelectedText
  duplicateSelectionsLinewise: ->
    linewiseDisposable = switchToLinewise(@editor) unless @vimState.isMode('visual', 'linewise')
    for selection in @getSelections()
      @duplicateLinewise(selection)
      swrap(selection).fixPropertyRowToRowRange()
    linewiseDisposable?.dispose()

class DuplicateSelectedTextUp extends DuplicateSelectedText
  direction: 'up'

  getBlockwiseSelections: ->
    blockwiseSelections = @vimState.getBlockwiseSelectionsOrderedByBufferPosition()
    blockwiseSelections.reverse() if @direction is 'down'
    blockwiseSelections

  execute: ->
    @editor.transact =>
      if @getWise() is 'linewise'
        @duplicateSelectionsLinewise()
      else
        if wasCharacterwise = @vimState.isMode('visual', 'characterwise')
          @vimState.activate('visual', 'blockwise')

        for blockwiseSelection in @getBlockwiseSelections()
          @duplicateBlockwise(blockwiseSelection)
        for $selection in swrap.getSelections(@editor)
          $selection.saveProperties()

        isOneHeight = (blockwiseSelection) -> blockwiseSelection.getHeight() is 1
        if wasCharacterwise and @vimState.getBlockwiseSelections().every(isOneHeight)
          @vimState.activate('visual', 'characterwise')

  getCountForSelection: (selectionOrBlockwiseSelection) ->
    count = @getCount()
    if @isOverwriteMode() and @direction is 'up'
      startRow = selectionOrBlockwiseSelection.getBufferRowRange()[0]
      countMax = Math.floor(startRow / rowCountForSelection(selectionOrBlockwiseSelection))
      Math.min(countMax, count)
    else
      count

  duplicateLinewise: (selection) ->
    return unless count = @getCountForSelection(selection)

    selectedText = selection.getText()
    selectedText += "\n" unless selectedText.endsWith("\n")
    newText = selectedText.repeat(count)
    height = rowCountForSelection(selection) * count

    {start, end} = selection.getBufferRange()
    if @direction is 'down'
      if end.isEqual(@editor.getEofBufferPosition())
        end = ensureBufferEndWithNewLine(@editor)

    rangeToMutate = switch @direction
      when 'up'
        if @isOverwriteMode()
          [start.translate([-height, 0]), start]
        else
          [start, start]
      when 'down'
        if @isOverwriteMode()
          [end, end.translate([+height, 0])]
        else
          [end, end]

    newRange = @editor.setTextInBufferRange(rangeToMutate, newText)
    selection.setBufferRange(newRange, reversed: selection.isReversed())

  duplicateBlockwise: (blockwiseSelection)  ->
    return unless count = @getCountForSelection(blockwiseSelection)

    [startRow, endRow] = blockwiseSelection.getBufferRowRange()
    height = blockwiseSelection.getHeight() * count
    if @isOverwriteMode()
      insertionStartRow = switch @direction
        when 'up' then startRow - height
        when 'down' then endRow + 1
      extendLastBufferRowToRow(@editor, insertionStartRow + height)
    else
      insertionStartRow = switch @direction
        when 'up' then startRow
        when 'down' then endRow + 1
      insertTextAtPoint(@editor, [insertionStartRow, 0], "\n".repeat(height))

    newRanges = []
    selectionsOrderd = blockwiseSelection.selections.sort (a, b) -> a.compare(b)
    for selection in repeatArray(selectionsOrderd, count)
      {start, end} = selection.getBufferRange()
      start.row = end.row = insertionStartRow
      insertionStartRow++
      insertSpacesToPoint(@editor, start)
      newRanges.push(@editor.setTextInBufferRange([start, end], selection.getText()))

    setBufferRangesForBlockwiseSelection(blockwiseSelection, newRanges)

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp
  direction: 'down'

class DuplicateSelectedTextLeft extends DuplicateSelectedText
  direction: 'left'
  execute: ->
    @editor.transact =>
      if @getWise() is 'linewise'
        @duplicateSelectionsLinewise()
      else
        for selection in @getSelections()
          @duplicateCharacterwise(selection)

  # No behavior diff by isOverwriteMode() and direction('left' or 'right')
  duplicateLinewise: (selection) ->
    amount = @getCount() + 1
    rows = selection.getText().split("\n").map((row) -> row.repeat(amount))
    selection.insertText(rows.join("\n"), select: true)

  # Return adjusted count to avoid partial duplicate in overwrite-mode
  getCountForSelection: (selection) ->
    count = @getCount()
    if @isOverwriteMode() and @direction is 'left'
      {start} = selection.getBufferRange()
      countMax = Math.floor(start.column / selection.getText().length)
      Math.min(countMax, count)
    else
      count

  duplicateCharacterwise: (selection) ->
    return unless count = @getCountForSelection(selection)

    newText = selection.getText().repeat(count)
    width = newText.length
    {start, end} = selection.getBufferRange()
    rangeToMutate = switch @direction
      when 'left'
        if @isOverwriteMode()
          [start.translate([0, -width]), start]
        else
          [start, start]
      when 'right'
        if @isOverwriteMode()
          [end, end.translate([0, width])]
        else
          [end, end]

    newRange = @editor.setTextInBufferRange(rangeToMutate, newText)
    selection.setBufferRange(newRange, reversed: selection.isReversed())

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft
  direction: 'right'

module.exports = {
  stateManager: stateManager
  commands: {
    MoveSelectedTextUp
    MoveSelectedTextDown
    MoveSelectedTextLeft
    MoveSelectedTextRight

    DuplicateSelectedTextUp
    DuplicateSelectedTextDown
    DuplicateSelectedTextLeft
    DuplicateSelectedTextRight
  }
}
