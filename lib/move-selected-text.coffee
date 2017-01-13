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

# Up/Down
class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  initialize: ->
    stateManager.set(@editor) unless stateManager.has(@editor)
    unless disposableByEditor.has(@editor)
      disposable = @vimState.modeManager.onDidDeactivateMode ({mode}) =>
        stateManager.remove(@editor) if mode is 'visual'

      disposableByEditor.set @editor, @editor.onDidDestroy =>
        disposable.dispose()
        disposableByEditor.delete(@editor)
        stateManager.remove(@editor)

    super

  getInitialOverwrittenBySelection: ->
    overwrittenBySelection = new Map

    getInitalAreaForSelection = (selection) =>
      text = if @isLinewise()
        height = swrap(selection).getRowCount()
        "\n".repeat(height)
      else
        width = selection.getBufferRange().getExtent().column
        ' '.repeat(width)
      new Area(text, @isLinewise())

    for selection in @editor.getSelections()
      area = getInitalAreaForSelection(selection)
      overwrittenBySelection.set(selection, area)
    overwrittenBySelection

  withUndoJoin: (fn) ->
    state = stateManager.get(@editor)
    state.init() unless state.isSequential()
    unless state.overwrittenBySelection?
      state.overwrittenBySelection = @getInitialOverwrittenBySelection()

    fn()
    state.updateSelectedTexts()
    state.groupChanges()

  # Used by
  # - up: linewise
  # - down: linewise
  # - right: characterwise
  # - left: characterwise
  rotateTextForSelection: (selection) ->
    reversed = selection.isReversed()
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]
      when 'right' then [[0, 0], [0, +1]]
      when 'left' then [[0, -1], [0, 0]]

    if @direction is 'down'
      if selection.getBufferRange().end.row is @editor.getLastBufferRow()
        ensureBufferEndWithNewLine(@editor)

    range = selection.getBufferRange().translate(translation...)
    if @direction is 'down' # auto insert new linew at last row
      extendLastBufferRowToRow(@editor, range.end.row)

    if @isOverwriteMode()
      overwrittenArea = stateManager.get(@editor).overwrittenBySelection.get(selection)
    area = new Area(@editor.getTextInBufferRange(range), @isLinewise(), overwrittenArea)
    range = @editor.setTextInBufferRange(range, area.getTextByRotate(@direction))
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})

  # Return 0 when no longer movable
  getCount: ->
    count = super
    if @direction is 'up'
      topSelection = @editor.getSelectionsOrderedByBufferPosition()[0]
      startRow = topSelection.getBufferRange().start.row
      Math.min(startRow, count)
    else
      count

  execute: ->
    @withUndoJoin =>
      selections = @editor.getSelectionsOrderedByBufferPosition()
      selections.reverse() if @direction is 'down'
      @editor.transact =>
        @countTimes @getCount(), =>
          for selection in selections
            if @isLinewise()
              @moveLinewise(selection)
            else
              @moveCharacterwise(selection)

  moveLinewise: (selection) ->
    @withLinewise selection, =>
      @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    translation = switch @direction
      when 'up' then [[-1, 0]]
      when 'down' then [[+1, 0]]

    fromRange = selection.getBufferRange()
    toRange = fromRange.translate(translation...)

    extendLastBufferRowToRow(@editor, toRange.end.row)
    # Swap text from fromRange to toRange
    insertSpacesToPoint(@editor, toRange.end)
    movingText = @editor.getTextInBufferRange(fromRange)
    replacedText = @editor.getTextInBufferRange(toRange)

    if @isOverwriteMode()
      area = stateManager.get(@editor).overwrittenBySelection.get(selection)
      replacedText = area.pushOut(replacedText, opposite(@direction))
    @editor.setTextInBufferRange(fromRange, replacedText)
    @editor.setTextInBufferRange(toRange, movingText)

    selection.setBufferRange(toRange, {reversed})

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

# Left/Right
class MoveSelectedTextLeft extends MoveSelectedTextUp
  direction: 'left'

  moveLinewise: (selection) ->
    switch @direction
      when 'left' then selection.outdentSelectedRows()
      when 'right' then selection.indentSelectedRows()

  moveCharacterwise: (selection) ->
    if @direction is 'left'
      return unless selection.getBufferRange().start.column > 0

    if @direction is 'right'
      endPoint = selection.getBufferRange().end
      insertTextAtPoint(@editor, endPoint, " ") if pointIsAtEndOfLine(@editor, endPoint)

    @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition(center: true)

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

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
      return super

    @editor.transact =>
      return if (count = @getCount()) is 0
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
  MoveSelectedTextUp, MoveSelectedTextDown
  MoveSelectedTextLeft, MoveSelectedTextRight

  DuplicateSelectedTextUp, DuplicateSelectedTextDown
  DuplicateSelectedTextLeft, DuplicateSelectedTextRight
}
