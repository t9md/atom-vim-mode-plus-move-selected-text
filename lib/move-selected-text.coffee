{
  ensureBufferEndWithNewLine
  extendLastBufferRowToRow
  includeBaseMixin
  insertBlankRowAtPoint
  insertSpacesToPoint
  isMultiLineSelection
  repeatArray
  replaceBufferRangeBy
  requireFrom
  rotateChars
  rotateRows
  setBufferRangesForBlockwiseSelection
  switchToLinewise
} = require './utils'

Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

StateManager = require './state-manager'
stateManager = new StateManager()

class MoveOrDuplicateSelectedText extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

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
  hasOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.has(selection)

  getOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.get(selection)

  setOverwrittenForSelection: (selection, overwritten) ->
    stateManager.get(@editor).overwrittenBySelection.set(selection, overwritten)

  getOrInitOverwrittenForSelection: (selection, initializer) ->
    unless @hasOverwrittenForSelection(selection)
      @setOverwrittenForSelection(selection, initializer())
    @getOverwrittenForSelection(selection)

  canMove: (selection, wise) ->
    switch @direction
      when 'up'
        selection.getBufferRange().start.row > 0
      when 'down', 'right'
        true
      when 'left'
        if wise in ['characterwise', 'blockwise']
          selection.getBufferRange().start.column > 0
        else
          true

  withGroupChanges: (fn) ->
    stateManager.resetIfNecessary(@editor)
    @editor.transact(fn)
    stateManager.groupChanges(@editor)

  moveSelections: (fn) ->
    wise = @getWise()
    @countTimes @getCount(), =>
      for selection in @getSelections() when @canMove(selection, wise)
        fn(selection)

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
    reversed = selection.isReversed()
    srcRange = selection.getBufferRange()

    dstRange = switch @direction
      when 'up' then srcRange.translate([-1, 0])
      when 'down' then srcRange.translate([+1, 0])

    extendLastBufferRowToRow(@editor, dstRange.end.row)
    insertSpacesToPoint(@editor, dstRange.end)
    srcText = @editor.getTextInBufferRange(srcRange)
    dstText = @editor.getTextInBufferRange(dstRange)

    if @isOverwriteMode()
      overwritten = @getOrInitOverwrittenForSelection selection, ->
        new Array(srcText.length).fill(' ')
      @setOverwrittenForSelection(selection, dstText.split(''))
      dstText = overwritten.join('')

    @editor.setTextInBufferRange(srcRange, dstText)
    @editor.setTextInBufferRange(dstRange, srcText)
    selection.setBufferRange(dstRange, {reversed})

  moveLinewise: (selection) ->
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]

    range = selection.getBufferRange()
    rangeToMutate = range.translate(translation...)
    extendLastBufferRowToRow(@editor, rangeToMutate.end.row)

    overwritten = null
    if @isOverwriteMode()
      height = range.getRowCount() - 1
      overwritten = @getOrInitOverwrittenForSelection selection, ->
        new Array(height).fill('')

    translation.reverse()
    newRange = replaceBufferRangeBy @editor, rangeToMutate, (text) =>
      rows = text.replace(/\n$/, '').split("\n")
      {rows, overwritten} = rotateRows(rows, @direction, {overwritten})
      @setOverwrittenForSelection(selection, overwritten) if overwritten.length
      rows.join("\n") + "\n"

    selection.setBufferRange(newRange.translate(translation...), reversed: selection.isReversed())

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  direction: 'left'

  moveCharacterwise: (selection) ->
    translation = switch @direction
      when 'right' then [[0, 0], [0, 1]]
      when 'left' then [[0, -1], [0, 0]]

    rangeToMutate = selection.getBufferRange().translate(translation...)
    insertSpacesToPoint(@editor, rangeToMutate.end)

    overwritten = null
    if @isOverwriteMode()
      textLength = selection.getText().length
      overwritten = @getOrInitOverwrittenForSelection selection, ->
        new Array(textLength).fill(' ')

    translation.reverse()
    newRange = replaceBufferRangeBy @editor, rangeToMutate, (text) =>
      {chars, overwritten} = rotateChars(text.split(''), @direction, {overwritten})
      @setOverwrittenForSelection(selection, overwritten) if overwritten.length
      chars.join('')
    selection.setBufferRange(newRange.translate(translation...), reversed: selection.isReversed())

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

        isOneHeight = (blockwiseSelection) -> blockwiseSelection.getHeight() is 1
        if wasCharacterwise and @vimState.getBlockwiseSelections().every(isOneHeight)
          @vimState.activate('visual', 'characterwise')

  duplicateLinewise: (selection) ->
    count = @getCount()

    [startRow, endRow ] = selection.getBufferRowRange()
    rows = [startRow..endRow]

    if @isOverwriteMode() and @direction is 'up'
      # Adjust count to avoid partial duplicate.
      countMax = Math.floor(startRow / rows.length)
      count = Math.min(countMax, count)
      return if count is 0

    height = rows.length * count
    rowsText = rows.map((row) => @editor.lineTextForBufferRow(row))
    newText = (rowsText.join("\n") + "\n").repeat(count)

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
    count = @getCount()
    height = blockwiseSelection.getHeight() * count
    [startRow, endRow] = blockwiseSelection.getBufferRowRange()
    switch @direction
      when 'up'
        if @isOverwriteMode()
          insertStartRow = startRow - height
        else
          insertBlankRowAtPoint(@editor, [startRow, 0], height)
          insertStartRow = startRow
      when 'down'
        if @isOverwriteMode()
          extendLastBufferRowToRow(@editor, endRow + height)
        else
          insertBlankRowAtPoint(@editor, [endRow + 1, 0], height)
        insertStartRow = endRow + 1

    newRanges = []
    selectionsOrderd = blockwiseSelection.selections.sort (a, b) -> a.compare(b)
    for selection in repeatArray(selectionsOrderd, count)
      {start, end} = selection.getBufferRange()
      start.row = end.row = insertStartRow
      insertStartRow++
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
    newText = selection.getText().split("\n")
      .map (rowText) -> rowText.repeat(amount)
      .join("\n")
    selection.insertText(newText, select: true)

  duplicateCharacterwise: (selection) ->
    count = @getCount()
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
