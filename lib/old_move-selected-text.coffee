_ = require 'underscore-plus'
{CompositeDisposable, Range, Point} = require 'atom'
{
  requireFrom, getSelectedTexts, insertTextAtPoint, setTextInRangeAndSelect,
  insertSpacesToPoint, extendLastBufferRowToRow, switchToLinewise,
  ensureBufferEndWithNewLine,
  opposite
} = require './utils'
{inspect} = require 'util'
Area = require './area'

{pointIsAtEndOfLine} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
BlockwiseSelection = requireFrom('vim-mode-plus', 'blockwise-selection')
Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')
StateManager = require './state-manager'

# stateByEditor = new Map
stateManager = new StateManager()
disposableByEditor = new Map

# UndoJoin
#
# Move
# - overwrite: true
#   - linewise: rotateRows
#   - characterwise:
#     if multiRowSelection, behave as linewise
#   - blockwise
# - overwrite: false
#   - linewise
#   - characterwise
#   - blockwise
#
# Duplicate
# - overwrite: true
#   - linewise
#   - characterwise
#   - blockwise
# - overwrite: false
#   - linewise
#   - characterwise
#   - blockwise
#
# Move
# -------------------------
class MoveSelectedText extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

  isOverwriteMode: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  isLinewise: ->
    switch @vimState.submode
      when 'linewise' then true
      when 'blockwise' then false
      when 'characterwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

  withLinewise: (selection, fn) ->
    unless @vimState.submode is 'linewise'
      disposable = switchToLinewise(selection)
    fn(selection)
    disposable?.dispose()

# Duplicate
# -------------------------
class DuplicateSelectedText extends MoveSelectedText
  getCount: ->
    count = super
    return count unless @isOverwriteMode()
    switch @direction
      when 'up'
        if @isLinewise()
          counts = @editor.getSelections().map (selection) ->
            {start} = selection.getBufferRange()
            Math.floor(start.row / swrap(selection).getRowCount())
          count = Math.min([count, counts...]...)
        else if @vimState.isMode('visual', 'blockwise')
          counts = @vimState.getBlockwiseSelections().map (bs) ->
            {start} = bs.getStartSelection().getBufferRange()
            Math.floor(start.row / bs.getHeight())
          count = Math.min([count, counts...]...)
      when 'left'
        if @isLinewise()
          count = 0
        else
          counts = @editor.getSelections().map (selection) ->
            {start, end} = selection.getBufferRange()
            Math.floor(start.column / (end.column - start.column))
          count = Math.min([count, counts...]...)
    count

  execute: ->
    selections = @editor.getSelectionsOrderedByBufferPosition()
    selections.reverse() if @direction is 'down'
    return if (count = @getCount()) is 0
    @editor.transact =>
      for selection in selections
        if @isLinewise()
          @duplicateLinewise(selection, count)
        else
          @duplicateCharacterwise(selection, count)

# Up/Down
class DuplicateSelectedTextUp extends DuplicateSelectedText
  direction: 'up'
  withBlockwise: (fn) ->
    if wasCharacterwise = @vimState.isMode('visual', 'characterwise')
      @vimState.activate('visual', 'blockwise')
    fn()
    if wasCharacterwise and
        @vimState.getBlockwiseSelections().every((bs) -> bs.getHeight() is 1)
      @vimState.activate('visual', 'characterwise')

  execute: ->
    if @isLinewise() or @direction in ['right', 'left']
      return super @editor.transact => return if (count = @getCount()) is 0
      @withBlockwise =>
        if @direction is 'down'
          bottom = _.last(@editor.getSelectionsOrderedByBufferPosition())
          range = bottom.getBufferRange()
          if range.end.row is @editor.getLastBufferRow()
            # Since inserting new line modify selected range
            # We have to revert selction range to preserved one.
            ensureBufferEndWithNewLine(@editor)
            bottom.setBufferRange(range)

        bss = @vimState.getBlockwiseSelectionsOrderedByBufferPosition()
        bss.reverse() if @direction is 'down'
        for bs in bss
          @duplicateCharacterwise(bs, count)

  duplicateLinewise: (selection, count) ->
    getText = ->
      rows = swrap(selection).lineTextForBufferRows()
      _.flatten([1..count].map -> rows).join("\n") + "\n"

    getRangeToInsert = (text) =>
      {start, end} = selection.getBufferRange()
      if @direction is 'down' and end.isEqual(@editor.getEofBufferPosition())
        end = ensureBufferEndWithNewLine(@editor)
      if @isOverwriteMode()
        height = text.split("\n").length - 1
        switch @direction
          when 'up' then [start.translate([-height, 0]), start]
          when 'down' then [end, end.translate([+height, 0])]
      else
        switch @direction
          when 'up' then [start, start]
          when 'down' then [end, end]

    @withLinewise selection, ->
      text = getText()
      range = getRangeToInsert(text)
      setTextInRangeAndSelect(range, text, selection)

  duplicateCharacterwise: (blockwiseSelection, count)  ->
    insertBlankLine = (amount) =>
      [startRow, endRow] = blockwiseSelection.getBufferRowRange()
      if @isOverwriteMode()
        if @direction is 'down'
          extendLastBufferRowToRow(@editor, endRow + amount)
      else
        point = switch @direction
          when 'up' then [startRow - 1, Infinity]
          when 'down' then [endRow + 1, 0]
        insertTextAtPoint(@editor, point, "\n".repeat(amount))

    getRangeToInsert = (selection, count) =>
      selection.getBufferRange().translate(
        switch @direction
          when 'up' then [-height * count, 0]
          when 'down' then [+height * count, 0]
        )

    select = (ranges) ->
      head = blockwiseSelection.getHeadSelection()
      wasReversed = blockwiseSelection.isReversed()
      blockwiseSelection.setSelectedBufferRanges(ranges, {reversed: head.isReversed()})
      blockwiseSelection.reverse() if wasReversed

    height = blockwiseSelection.getHeight()
    insertBlankLine(height * count)

    ranges = []
    @countTimes @getCount(), ({count}) =>
      for selection, i in blockwiseSelection.selections
        text = selection.getText()
        range = getRangeToInsert(selection, count)
        insertSpacesToPoint(@editor, range.start)
        ranges.push @editor.setTextInBufferRange(range, text)
    select(ranges)

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp
  direction: 'down'

# Left/Right
class DuplicateSelectedTextLeft extends DuplicateSelectedText
  direction: 'left'

  # No behavior-diff by 'isOverwriteMode'
  duplicateLinewise: (selection, count) ->
    getText = ->
      swrap(selection).lineTextForBufferRows()
        .map (text) -> text.repeat(count+1)
        .join("\n") + "\n"

    getRange = ->
      selection.getBufferRange()

    @withLinewise selection, ->
      setTextInRangeAndSelect(getRange(), getText(), selection)

  duplicateCharacterwise: (selection, count) ->
    getText = ->
      selection.getText().repeat(count)

    getRange = =>
      width = getText().length
      {start, end} = selection.getBufferRange()
      switch @direction
        when 'right'
          range = new Range(end, end)
          if @isOverwriteMode()
            range.end = range.end.translate([0, +width])
          range
        when 'left'
          range = new Range(start, start)
          if @isOverwriteMode()
            range.start = range.start.translate([0, -width])
          range

    setTextInRangeAndSelect(getRange(), getText(), selection)

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft
  direction: 'right'

module.exports = {
  DuplicateSelectedTextUp, DuplicateSelectedTextDown
  DuplicateSelectedTextLeft, DuplicateSelectedTextRight
}
