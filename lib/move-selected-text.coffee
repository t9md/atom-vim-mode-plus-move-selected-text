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

{pointIsAtEndOfLine, sortRanges} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
BlockwiseSelection = requireFrom('vim-mode-plus', 'blockwise-selection')
Base = requireFrom('vim-mode-plus', 'base')
TransformString = Base.getClass('Operator')

class State
  selectedTexts: null
  checkpoint: null
  overwrittenBySelection: null

stateByEditor = new Map
disposableByEditor = new Map

# Move
# -------------------------
class MoveSelectedText extends TransformString
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

  isOverwrite: ->
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

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  initState: ->
    stateByEditor.set(@editor, new State())

  getState: ->
    stateByEditor.get(@editor)

  hasState: ->
    stateByEditor.has(@editor)

  removeState: ->
    stateByEditor.delete(@editor)

  initialize: ->
    @initState() unless @hasState()
    unless disposableByEditor.has(@editor)
      disposable = @vimState.modeManager.onDidDeactivateMode ({mode}) =>
        @removeState() if mode is 'visual'

      disposableByEditor.set @editor, @editor.onDidDestroy =>
        disposable.dispose()
        disposableByEditor.delete(@editor)
        @removeState()

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
    state = @getState()
    isSequential = state.selectedTexts is getSelectedTexts(@editor)
    unless isSequential
      state.checkpoint = @editor.createCheckpoint()
      state.overwrittenBySelection = null
    unless state.overwrittenBySelection?
      state.overwrittenBySelection = @getInitialOverwrittenBySelection()
    fn()
    state.selectedTexts = getSelectedTexts(@editor)
    if isSequential
      @editor.groupChangesSinceCheckpoint(state.checkpoint)

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

    if @isOverwrite()
      overwrittenArea = @getState().overwrittenBySelection.get(selection)
    area = new Area(@editor.getTextInBufferRange(range), @isLinewise(), overwrittenArea)
    range = @editor.setTextInBufferRange(range, area.getTextByRotate(@direction))
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})

  # Return 0 when no longer movable
  getCount: =>
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
        @countTimes =>
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

    if @isOverwrite()
      area = @getState().overwrittenBySelection.get(selection)
      replacedText = area.pushOut(replacedText, opposite(@direction))
    @editor.setTextInBufferRange(fromRange, replacedText)
    @editor.setTextInBufferRange(toRange, movingText)

    selection.setBufferRange(toRange, {reversed})

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedTextUp
  direction: 'left'

  moveLinewise: (selection) ->
    selection.outdentSelectedRows()

  moveCharacterwise: (selection) ->
    return if selection.getBufferRange().start.column is 0

    @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

  moveLinewise: (selection) ->
    selection.indentSelectedRows()

  moveCharacterwise: (selection) ->
    eol = selection.getBufferRange().end
    if pointIsAtEndOfLine(@editor, eol)
      insertTextAtPoint(@editor, eol, " ")

    @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

# Duplicate
# -------------------------
class DuplicateSelectedText extends MoveSelectedText
  getCount: ->
    count = super
    return count unless @isOverwrite()
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
    if @isLinewise() or (not @isLinewise() and (@direction in ['right', 'left']))
      super
    else
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
      if @isOverwrite()
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
      if @isOverwrite()
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
    @countTimes (num) =>
      for selection, i in blockwiseSelection.selections
        text = selection.getText()
        range = getRangeToInsert(selection, num)
        insertSpacesToPoint(@editor, range.start)
        ranges.push @editor.setTextInBufferRange(range, text)
    select(ranges)

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp
  direction: 'down'

class DuplicateSelectedTextLeft extends DuplicateSelectedTextUp
  direction: 'left'

  duplicateLinewise: (selection, count) ->
    getText = ->
      swrap(selection).lineTextForBufferRows()
        .map (text) -> text.repeat(count+1)
        .join("\n") + "\n"

    @withLinewise selection, ->
      text = getText()
      range = selection.getBufferRange()
      setTextInRangeAndSelect(range, text, selection)

  duplicateCharacterwise: (selection, count) ->
    getRangeToInsert = (text) =>
      {start, end} = selection.getBufferRange()
      if @isOverwrite()
        width = text.length
        switch @direction
          when 'right' then [end, end.translate([0, +width])]
          when 'left' then [start.translate([0, -width]), start]
      else
        switch @direction
          when 'right' then [end, end]
          when 'left' then [start, start]

    text = selection.getText().repeat(count)
    range = getRangeToInsert(text)
    setTextInRangeAndSelect(range, text, selection)

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft
  direction: 'right'

module.exports = {
  MoveSelectedTextUp, MoveSelectedTextDown
  MoveSelectedTextLeft, MoveSelectedTextRight

  DuplicateSelectedTextUp, DuplicateSelectedTextDown
  DuplicateSelectedTextLeft, DuplicateSelectedTextRight
}
