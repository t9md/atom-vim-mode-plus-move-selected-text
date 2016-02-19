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
{inspect} = require 'util'

sortRanges = (ranges) ->
  ranges.sort((a, b) -> a.compare(b))

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

{pointIsAtEndOfLine, sortRanges, getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
Base = requireFrom('vim-mode-plus', 'base')
TransformString = Base.getClass('Operator')

newState = ->
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

  initialize: ->
    stateByEditor.set(@editor, newState()) unless stateByEditor.has(@editor)
    unless disposableByEditor.has(@editor)
      disposable = @vimState.modeManager.onDidDeactivateMode ({mode}) =>
        if mode is 'visual'
          stateByEditor.delete(@editor)

      disposableByEditor.set @editor, @editor.onDidDestroy =>
        disposable.dispose()
        stateByEditor.delete(@editor)
        disposableByEditor.delete(@editor)

  getSelectedTexts: ->
    @editor.getSelections().map((selection) -> selection.getText()).join("\n")

  insertTextAtPoint: (point, text) ->
    @editor.setTextInBufferRange([point, point], text)

  isOverwrite: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  isLinewise: ->
    switch @vimState.submode
      when 'linewise' then true
      when 'blockwise' then false
      when 'characterwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

  isCharacterwise: ->
    not @isLinewise()

  setTextInRangeAndSelect: (range, text, selection) ->
    newRange = @editor.setTextInBufferRange(range, text)
    selection.setBufferRange(newRange)

  complementSpacesToPoint: ({row, column}) ->
    eol = @editor.bufferRangeForBufferRow(row).end
    if (fillCount = column - eol.column) > 0
      @insertTextAtPoint(eol, ' '.repeat(fillCount))

  isMovable: (selection) ->
    {start} = selection.getBufferRange()
    switch @direction
      when 'down', 'right' then true
      when 'up' then start.row isnt 0
      when 'left'
        if @isLinewise() then true else start.column isnt 0

  execute: ->
    @withUndoJoin =>
      selections = @editor.getSelectionsOrderedByBufferPosition()
      return if @isCharacterwise() and (not @isMovable(selections[0]))
      selections.reverse() if @direction is 'down'
      @editor.transact =>
        @countTimes =>
          @mutateSelections(selections)

  mutateSelections: (selections) ->
    for selection in selections when @isMovable(selection)
      if @isLinewise()
        @moveLinewise(selection)
      else
        @moveCharacterwise(selection)

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
    state = stateByEditor.get(@editor)
    isSequential = state.selectedTexts is @getSelectedTexts()
    unless isSequential
      state.checkpoint = @editor.createCheckpoint()
      state.overwrittenBySelection = null

    unless state.overwrittenBySelection?
      state.overwrittenBySelection = @getInitialOverwrittenBySelection()

    fn()

    state.selectedTexts = @getSelectedTexts()
    if isSequential
      @editor.groupChangesSinceCheckpoint(state.checkpoint)

  # Used by
  # - up: linewise, characterwise
  # - down: linewise, characterwise
  # - right: characterwise
  # - left: characterwise
  getOverwrittenForSelection: (selection, disappearing) ->
    {overwrittenBySelection} = stateByEditor.get(@editor)
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
      endRow = selection.getBufferRange().end.row
      if endRow >= getVimLastBufferRow(@editor)
        @insertTextAtPoint(@editor.getEofBufferPosition(), "\n")

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
  flashTarget: false

  moveLinewise: (selection) ->
    if @vimState.submode is 'linewise'
      @rotateTextForSelection(selection)
    else
      swrap(selection).switchToLinewise =>
        @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    # Pre mutate
    translation = switch @direction
      when 'up' then [[-1, 0], [-1, 0]]
      when 'down' then [[1, 0], [1, 0]]

    fromRange = selection.getBufferRange()
    toRange = fromRange.translate(translation...)

    # Swap text from fromRange to toRange
    @complementSpacesToPoint(toRange.end)
    movingText = @editor.getTextInBufferRange(fromRange)
    replacedText = @editor.getTextInBufferRange(toRange)
    replacedText = @getOverwrittenForSelection(selection, replacedText) if @isOverwrite()
    @editor.setTextInBufferRange(fromRange, replacedText)
    @editor.setTextInBufferRange(toRange, movingText)

    selection.setBufferRange(toRange, {reversed})

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextRight extends MoveSelectedText
  direction: 'right'
  flashTarget: false

  moveLinewise: (selection) ->
    switch @direction
      when 'right' then selection.indentSelectedRows()
      when 'left' then selection.outdentSelectedRows()

  moveCharacterwise: (selection) ->
    # automatically append space at EOL
    if @direction is 'right'
      eol = selection.getBufferRange().end
      if pointIsAtEndOfLine(@editor, eol)
        @insertTextAtPoint(eol, " ")

    @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

class MoveSelectedTextLeft extends MoveSelectedTextRight
  direction: 'left'

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
      if @isLinewise()
        for selection in selections
          if @vimState.submode is 'linewise'
            @duplicateLinewise(selection, count)
          else
            swrap(selection).switchToLinewise =>
              @duplicateLinewise(selection, count)
      else
        switch @direction
          when 'right', 'left'
            for selection in selections
              @duplicateCharacterwise(selection, count)
          when 'up', 'down'
            if wasCharacterwise = @vimState.isMode('visual', 'characterwise')
              @vimState.activate('visual', 'blockwise')

            bss = @vimState.getBlockwiseSelectionsOrderedByBufferPosition()
            console.log bss.length
            bss.reverse() if @direction is 'down'
            # console.log count
            for bs in bss
              @duplicateBlockwiseSelection(bs, count)

            if wasCharacterwise
              @vimState.activate('visual', 'characterwise')

  duplicateLinewise: (selection, count) ->
    {start, end} = selection.getBufferRange()
    rows = swrap(selection).lineTextForBufferRows()
    lineTexts = switch @direction
      when 'up', 'down' then _.flatten([1..count].map -> rows)
      when 'left', 'right' then rows.map (text) -> text.repeat(count+1)

    height = lineTexts.length
    newText = lineTexts.join("\n") + "\n"

    range = switch @direction
      when 'up'
        if @isOverwrite()
          [start.translate([-height, 0]), start]
        else
          [start, start]
      when 'down'
        if @isOverwrite()
          [end, end.translate([+height, 0])]
        else
          [end, end]
      when 'left', 'right'
        selection.getBufferRange()
    @setTextInRangeAndSelect(range, newText, selection)

class DuplicateSelectedTextUp extends DuplicateSelectedText
  direction: 'up'

  duplicateBlockwiseSelection: (blockwiseSelection, count) ->
    {selections} = blockwiseSelection
    height = blockwiseSelection.getHeight()

    unless @isOverwrite() # Insert Blank row
      [startRow, endRow] = blockwiseSelection.getBufferRowRange()
      point = switch @direction
        when 'up' then [startRow - 1, Infinity]
        when 'down' then [endRow + 1, 0]
      @insertTextAtPoint(point, "\n".repeat(height * count))

    getTranslation = (direction, count) ->
      switch direction
        when 'up' then [-height * count, 0]
        when 'down' then [+height * count, 0]

    ranges = []
    for num in [1..count]
      selections.forEach (selection) =>
        translation = getTranslation(@direction, num)
        range = selection.getBufferRange().translate(translation)
        @complementSpacesToPoint(range.start)
        ranges.push @editor.setTextInBufferRange(range, selection.getText())
    sortRanges(ranges)
    first = ranges[0]
    last = _.last(ranges)
    range = if blockwiseSelection.headReversedStateIsInSync()
      new Range(first.start, last.end)
    else
      new Range(first.end, last.start).translate([0, -1], [0, +1])
    blockwiseSelection.setBufferRange(range)

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp
  direction: 'down'

class DuplicateSelectedTextRight extends DuplicateSelectedText
  direction: 'right'
  duplicateCharacterwise: (selection, count) ->
    newText = selection.getText().repeat(count)
    width = newText.length
    {start, end} = selection.getBufferRange()
    range = switch @direction
      when 'left'
        if @isOverwrite()
          [start.translate([0, -width]), start]
        else
          [start, start]
      when 'right'
        if @isOverwrite()
          [end, end.translate([0, +width])]
        else
          [end, end]
    @setTextInRangeAndSelect(range, newText, selection)

class DuplicateSelectedTextLeft extends DuplicateSelectedTextRight
  direction: 'left'

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft

  DuplicateSelectedTextDown, DuplicateSelectedTextUp
  DuplicateSelectedTextRight, DuplicateSelectedTextLeft
}
