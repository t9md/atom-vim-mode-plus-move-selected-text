_ = require 'underscore-plus'
{Range} = require 'atom'

{
  requireFrom
  switchToLinewise
  isMultiLineSelection
  ensureBufferEndWithNewLine
  extendLastBufferRowToRow
  insertSpacesToPoint
} = require './utils'

{inspect} = require 'util'
p = (args...) -> console.log inspect(args...)

Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

class DuplicateSelectedText extends Operator
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
    reversed = selection.isReversed()
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
    selection.setBufferRange(newRange, {reversed})

  duplicateBlockwise: (blockwiseSelection)  ->
    count = @getCount()
    insertBlankLine = (amount) =>
      [startRow, endRow] = blockwiseSelection.getBufferRowRange()
      if @isOverwriteMode()
        if @direction is 'down'
          extendLastBufferRowToRow(@editor, endRow + amount)
      else
        point = switch @direction
          when 'up' then [startRow - 1, Infinity]
          when 'down' then [endRow + 1, 0]
        @editor.setTextInBufferRange([point, point], "\n".repeat(amount))

    getRangeToInsert = (selection, count) =>
      selection.getBufferRange().translate(
        switch @direction
          when 'up' then [-height * count, 0]
          when 'down' then [+height * count, 0]
        )

    height = blockwiseSelection.getHeight()
    insertBlankLine(height * count)

    newRanges = []
    @countTimes @getCount(), ({count}) =>
      for selection, i in blockwiseSelection.selections
        text = selection.getText()
        range = getRangeToInsert(selection, count)
        insertSpacesToPoint(@editor, range.start)
        newRanges.push @editor.setTextInBufferRange(range, text)

    head = blockwiseSelection.getHeadSelection()
    wasReversed = blockwiseSelection.isReversed()
    blockwiseSelection.setSelectedBufferRanges(newRanges, {reversed: head.isReversed()})
    blockwiseSelection.reverse() if wasReversed

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
    reversed = selection.isReversed()
    count = @getCount()
    [startRow, endRow ] = selection.getBufferRowRange()
    newText = [startRow..endRow]
      .map (row) => @editor.lineTextForBufferRow(row).repeat(count + 1)
      .join("\n") + "\n"
    newRange = selection.insertText(newText)
    selection.setBufferRange(newRange, {reversed})

  duplicateCharacterwise: (selection) ->
    count = @getCount()
    reversed = selection.isReversed()
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
    selection.setBufferRange(newRange, {reversed})

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft
  direction: 'right'

module.exports = {
  DuplicateSelectedTextUp
  DuplicateSelectedTextDown
  DuplicateSelectedTextLeft
  DuplicateSelectedTextRight
}
