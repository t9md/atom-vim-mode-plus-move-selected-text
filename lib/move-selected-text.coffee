# Moving strategy
# -------------------------
# Two wise. correspoinding submode of visual-mode is below
#  - Linewise: linewise, characterwise(in case some selection is multi-row)
#  - Characterwise: characterwise(in case all selection is single-row), blockwise
#
# Four direction
#   ['up', 'down', 'right', 'left']
#
# Movability
#  up
#    - Linewise: can't move upward if row is 0
#    - Characterwise: can't move upward if top selection is at row 0
#  down
#    - Linewise: always movable since last row is automatically extended.
#    - Characterwise: always movable since last row is automatically extended.
#  right
#    - Linewise: always movable since EOL is automatically extended.
#    - Characterwise: always movable since EOL is automatically extended.
#  left
#    - Linewise: always true since indent/outdent command can handle it.
#    - Characterwise: can't move if start of selection is at column 0
#
# Moving method
#  up
#    - Linewise: rotate linewise
#    - Characterwise: swap single-row selection with upper block
#  down
#    - Linewise: rotate linewise
#    - Characterwise: swap single-row selection with lower block
#  right
#    - Linewise: indent line
#    - Characterwise: rotate charater in single-row selection.
#  left
#    - Linewise: outdent line
#    - Characterwise: rotate charater in single-row selection.

_ = require 'underscore-plus'
{CompositeDisposable, Range, Point} = require 'atom'
{
  sortRanges
  requireFrom
  getSelectedTexts
  insertTextAtPoint
  setTextInRangeAndSelect
  insertSpacesToPoint
  extendLastBufferRowToRow
  switchToLinewise
  ensureBufferEndWithNewLine
} = require './utils'
{inspect} = require 'util'

{pointIsAtEndOfLine, sortRanges, getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
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

  isOverwrite: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  isLinewise: ->
    switch @vimState.submode
      when 'linewise' then true
      when 'blockwise' then false
      when 'characterwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

  withLinewise: (fn) ->
    unless @vimState.submode is 'linewise'
      disposable = switchToLinewise(selection)
    fn()
    disposable?.dispose()

  getInitialOverwrittenBySelection: ->
    overwrittenBySelection = new Map
    isLinewise = @isLinewise()
    @editor.getSelections().forEach (selection) ->
      data =
        if isLinewise
          height = swrap(selection).getRows().length
          Array(height).fill('')
        else
          width = selection.getBufferRange().getExtent().column
          [' '.repeat(width)]
      overwrittenBySelection.set(selection, data)
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
  # - up: linewise, characterwise
  # - down: linewise, characterwise
  # - right: characterwise
  # - left: characterwise
  getOverwrittenForSelection: (selection, disappearing) ->
    {overwrittenBySelection} = @getState()
    # overwrittenArea must mutated in-place.
    overwrittenArea = overwrittenBySelection.get(selection)

    switch @direction
      when 'up'
        overwrittenArea.push(disappearing)
        overwrittenArea.shift()
      when 'down'
        overwrittenArea.unshift(disappearing)
        overwrittenArea.pop()
      when 'left'
        characters = overwrittenArea[0].split('')
        appearing = characters.pop()
        overwrittenArea.splice(0, Infinity, disappearing + characters.join(""))
        appearing
      when 'right'
        characters = overwrittenArea[0].split('')
        appearing = characters.shift()
        overwrittenArea.splice(0, Infinity, characters.join("") + disappearing)
        appearing

  # Used by
  # - up: linewise
  # - down: linewise
  # - right: characterwise
  # - left: characterwise
  rotateTextForSelection: (selection) ->
    reversed = selection.isReversed()
    # Pre mutate
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]
      when 'right' then [[0, 0], [0, +1]]
      when 'left' then [[0, -1], [0, 0]]

    if @direction is 'down' # auto insert new linew at last row
      extendLastBufferRowToRow(@editor, selection.getBufferRange().end.row)

    range = selection.getBufferRange().translate(translation...)
    selection.setBufferRange(range)

    text = switch @direction
      when 'up', 'down' then swrap(selection).lineTextForBufferRows()
      when 'right', 'left' then selection.getText().split('')

    newText = if @isLinewise()
      @rotateText(text, selection).join("\n") + "\n"
    else
      @rotateText(text, selection).join("")

    range = selection.insertText(newText)
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})

  # Used by
  # - up: linewise
  # - down: linewise
  # - right: characterwise
  # - left: characterwise
  rotateText: (text, selection) ->
    switch @direction
      when 'up', 'left'
        overwritten = text.shift()
        overwritten = @getOverwrittenForSelection(selection, overwritten) if @isOverwrite()
        text.push(overwritten)
        text
      when 'down', 'right'
        overwritten = text.pop()
        overwritten = @getOverwrittenForSelection(selection, overwritten) if @isOverwrite()
        text.unshift(overwritten)
        text

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

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
    @withLinewise =>
      @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    rowDelta = switch @direction
      when 'up' then -1
      when 'down' then 1

    fromRange = selection.getBufferRange()
    toRange = fromRange.translate([rowDelta, 0])

    extendLastBufferRowToRow(@editor, toRange.end.row)
    # Swap text from fromRange to toRange
    insertSpacesToPoint(@editor, toRange.end)
    movingText = @editor.getTextInBufferRange(fromRange)
    replacedText = @editor.getTextInBufferRange(toRange)
    replacedText = @getOverwrittenForSelection(selection, replacedText) if @isOverwrite()
    @editor.setTextInBufferRange(fromRange, replacedText)
    @editor.setTextInBufferRange(toRange, movingText)

    selection.setBufferRange(toRange, {reversed})

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextRight extends MoveSelectedTextUp
  direction: 'right'

  moveLinewise: (selection) ->
    selection.indentSelectedRows()

  moveCharacterwise: (selection) ->
    eol = selection.getBufferRange().end
    if pointIsAtEndOfLine(@editor, eol)
      insertTextAtPoint(@editor, eol, " ")

    @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

class MoveSelectedTextLeft extends MoveSelectedTextRight
  direction: 'left'

  moveLinewise: (selection) ->
    selection.outdentSelectedRows()

  moveCharacterwise: (selection) ->
    return if selection.getBufferRange().start.column is 0

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
            {start} = bs.getTop().getBufferRange()
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
    if wasCharacterwise
      @vimState.activate('visual', 'characterwise')

  execute: ->
    if @isLinewise() or (not @isLinewise() and (@direction in ['right', 'left']))
      super
    else
      @editor.transact =>
        return if (count = @getCount()) is 0
        @withBlockwise =>
          # if @direction is 'down'
          #   bottom = _.last(@editor.getSelectionsOrderedByBufferPosition())
          #   preservedRange = bottom.getBufferRange()
          #   ensureBufferEndWithNewLine(@editor)
          #   bottom.setBufferRange(preservedRange)
          #   # extendLastBufferRowToRow(@editor, selection.getBufferRange().end.row)

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

    @withLinewise =>
      text = getText()
      range = getRangeToInsert(text)
      setTextInRangeAndSelect(range, text, selection)

  duplicateCharacterwise: (blockwiseSelection, count)  ->
    insertBlankLine = (amount) =>
      [startRow, endRow] = blockwiseSelection.getBufferRowRange()
      if @isOverwrite()
        # if and @direction is 'down'
        null
        # console.log endRow + amount
        # extendLastBufferRowToRow(@editor, endRow + amount)
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

    select = (ranges) =>
      sortRanges(ranges)
      first = ranges[0]
      last = _.last(ranges)
      blockwiseSelection.setBufferRange(
        if blockwiseSelection.headReversedStateIsInSync()
          new Range(first.start, last.end)
        else
          new Range(first.end, last.start).translate([0, -1], [0, +1])
      )

    {selections} = blockwiseSelection
    height = blockwiseSelection.getHeight()
    insertBlankLine(height * count)

    ranges = []
    texts = (selection.getText() for selection in selections)
    for num in [1..count]
      selections.forEach (selection, i) =>
        range = getRangeToInsert(selection, num)
        insertSpacesToPoint(@editor, range.start)
        ranges.push @editor.setTextInBufferRange(range, texts[i])
    select(ranges)

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp
  direction: 'down'

class DuplicateSelectedTextRight extends DuplicateSelectedTextUp
  direction: 'right'

  duplicateLinewise: (selection, count) ->
    getText = ->
      swrap(selection).lineTextForBufferRows()
        .map (text) -> text.repeat(count+1)
        .join("\n") + "\n"

    @withLinewise =>
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

class DuplicateSelectedTextLeft extends DuplicateSelectedTextRight
  direction: 'left'

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft

  DuplicateSelectedTextDown, DuplicateSelectedTextUp
  DuplicateSelectedTextRight, DuplicateSelectedTextLeft
}
