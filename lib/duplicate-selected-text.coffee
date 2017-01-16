{
  requireFrom
  switchToLinewise
  isMultiLineSelection
  ensureBufferEndWithNewLine
  extendLastBufferRowToRow
  insertSpacesToPoint
  repeatArray
  setBufferRangesForBlockwiseSelection
  insertBlankRowAtPoint
  includeBaseMixin
  setBufferRangeForSelectionBy
  replaceRangeAndSelect
} = require './utils'

Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

class DuplicateSelectedText extends Operator
  includeBaseMixin(this)
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

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

    setBufferRangeForSelectionBy selection, =>
      @editor.setTextInBufferRange(rangeToMutate, newText)

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
    replaceRangeAndSelect selection, selection.getBufferRange(), {}, (text) ->
      text.split("\n")
        .map (rowText) -> rowText.repeat(amount)
        .join("\n")

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

    setBufferRangeForSelectionBy selection, =>
      @editor.setTextInBufferRange(rangeToMutate, newText)

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft
  direction: 'right'

module.exports = {
  DuplicateSelectedTextUp
  DuplicateSelectedTextDown
  DuplicateSelectedTextLeft
  DuplicateSelectedTextRight
}
