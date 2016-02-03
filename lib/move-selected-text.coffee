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
{CompositeDisposable} = require 'atom'
{inspect} = require 'util'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

{pointIsAtEndOfLine, sortRanges, getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
Base = requireFrom('vim-mode-plus', 'base')
BlockwiseSelect = Base.getClass('BlockwiseSelect')
TransformString = Base.getClass('Operator')

newState = ->
  selectedTexts: null
  checkpoint: null
  overwrittenBySelection: null

stateByEditor = new Map
disposableByEditor = new Map

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

  isOverwrite: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  isLinewise: ->
    switch @vimState.submode
      when 'linewise' then true
      when 'characterwise', 'blockwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

  isCharacterwise: ->
    not @isLinewise()

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
      selections.reverse() if @direction is 'up'
      @editor.transact =>
        @countTimes =>
          @mutateSelections(selections)

  mutateSelections: (selections) ->
    for selection in selections when @isMovable(selection)
      switch @direction
        when 'down' # auto insert new linew at last row
          endRow = selection.getBufferRange().end.row
          if endRow >= getVimLastBufferRow(@editor)
            eof = @editor.getEofBufferPosition()
            @editor.setTextInBufferRange([eof, eof], "\n")
        when 'right' # automatically append space at EOL
          if @isCharacterwise()
            eol = selection.getBufferRange().end
            if pointIsAtEndOfLine(@editor, eol)
              @editor.setTextInBufferRange([eol, eol], " ")

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

  complementSpacesToPoint: ({row, column}) ->
    eol = @editor.bufferRangeForBufferRow(row).end
    if (fillCount = column - eol.column) > 0
      @editor.setTextInBufferRange([eol, eol], ' '.repeat(fillCount))

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

# -------------------------
class MoveSelectedTextRight extends MoveSelectedText
  direction: 'right'
  flashTarget: false

  moveLinewise: (selection) ->
    # console.log @direction, "HELLO"
    switch @direction
      when 'right' then selection.indentSelectedRows()
      when 'left' then selection.outdentSelectedRows()

  moveCharacterwise: (selection) ->
    @rotateTextForSelection(selection)
    @editor.scrollToCursorPosition({center: true})

class MoveSelectedTextLeft extends MoveSelectedTextRight
  direction: 'left'

# -------------------------
class DuplicateSelectedText extends TransformString
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'

  execute: ->
    selections = @editor.getSelectionsOrderedByBufferPosition()
    topRow = selections[0].getBufferRange().start.row
    bottomRow = _.last(selections).getBufferRange().start.row
    selections.reverse() if @direction in ['down', 'up']

    isLinewise = @isLinewise()
    @editor.transact =>
      if isLinewise
        for selection in selections
          if @vimState.submode is 'linewise'
            @duplicateLinewise(selection)
          else
            swrap(selection).switchToLinewise =>
              @duplicateLinewise(selection)
      else
        switch @direction
          when 'right', 'left'
            for selection in selections
              @duplicateCharacterwise(selection)
          when 'up', 'down'
            lastSelection = @editor.getLastSelection()
            reversed = lastSelection.isReversed()
            # selection.setBufferRange(range, {reversed})
            height = selections.length
            totalHeight = height * @getCount()
            lackOfSelection = totalHeight - height
            ranges = []
            @countTimes =>
              for selection in selections
                ranges.push(@duplicateCharacterwise(selection, {topRow, bottomRow}))
                selection.destroy() unless selection.isLastSelection()
            ranges = sortRanges(ranges)
            range = [_.first(ranges).start, _.last(ranges).end.translate([totalHeight - 1, 0])]
            lastSelection.setBufferRange(range, {reversed})
            new BlockwiseSelect(@vimState).execute()
  isCharacterwise: ->
    not @isLinewise()

  duplicateLinewise: (selection) ->
    lineTexts = @duplicateText(selection, @getCount())
    reversed = selection.isReversed()
    newText = lineTexts.join("\n") + "\n"

    range = switch @direction
      when 'up', 'down'
        {start, end} = selection.getBufferRange()
        point = switch @direction
          when 'up' then start
          when 'down' then end
        @editor.setTextInBufferRange([point, point], newText)
      when 'left', 'right'
        selection.insertText(newText)
    selection.setBufferRange(range, {reversed})

  insertTextAtPoint: (point, text) ->
    @editor.setTextInBufferRange([point, point], text)

  duplicateCharacterwise: (selection, {topRow, bottomRow}={}) ->
    switch @direction
      when 'up', 'down'
        lineTexts = @duplicateText(selection, 1)
        spaces = ' '.repeat(selection.getBufferRange().start.column)
        point = switch @direction
          when 'up' then [topRow-1, Infinity]
          when 'down' then [bottomRow, Infinity]
        {end} = @insertTextAtPoint(point, "\n" + spaces)
        @insertTextAtPoint(end, lineTexts.join(""))
      when 'left', 'right'
        lineTexts = @duplicateText(selection, @getCount())
        {start, end} = selection.getBufferRange()
        point = switch @direction
          when 'left' then start
          when 'right' then end
        @insertTextAtPoint(point, lineTexts.join(""))

  isLinewise: ->
    switch @vimState.submode
      when 'linewise' then true
      when 'characterwise', 'blockwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

  duplicateText: (selection, count) ->
    if @isLinewise()
      rows = swrap(selection).lineTextForBufferRows()
      switch @direction
        when 'up', 'down' then _.flatten([1..count].map -> rows)
        when 'left', 'right' then rows.map (text) -> text.repeat(count+1)
    else
      text = selection.getText()
      switch @direction
        when 'up', 'down' then [1..count].map -> text
        when 'left', 'right' then [text.repeat(count)]

class DuplicateSelectedTextUp extends DuplicateSelectedText
  direction: 'up'

class DuplicateSelectedTextDown extends DuplicateSelectedText
  direction: 'down'

class DuplicateSelectedTextRight extends DuplicateSelectedText
  direction: 'right'

class DuplicateSelectedTextLeft extends DuplicateSelectedText
  direction: 'left'

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft

  DuplicateSelectedTextDown, DuplicateSelectedTextUp
  DuplicateSelectedTextRight, DuplicateSelectedTextLeft
}
