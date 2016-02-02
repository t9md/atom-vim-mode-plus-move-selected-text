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

{pointIsAtEndOfLine, getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
Base = requireFrom('vim-mode-plus', 'base')
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
      selections.reverse() if @direction is 'down'
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
          swrap(selection).getRows().map(-> '').join("\n")
        else
          _.multiplyString(' ', selection.getBufferRange().getExtent().column)
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
    overwrittenArea = overwrittenBySelection.get(selection)

    overwritten = switch @direction
      when 'up'
        [appearing, covered...] = overwrittenArea.split("\n")
        overwrittenArea = [covered..., disappearing].join("\n")
        appearing
      when 'down'
        [covered..., appearing] = overwrittenArea.split("\n")
        overwrittenArea = [disappearing, covered...].join("\n")
        appearing
      when 'left'
        [covered..., appearing] = overwrittenArea
        overwrittenArea = [disappearing, covered...].join("")
        appearing
      when 'right'
        [appearing, covered...] = overwrittenArea
        overwrittenArea = [covered..., disappearing].join("")
        appearing

    overwrittenBySelection.set(selection, overwrittenArea)
    overwritten

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

    rotated = @rotateText(text, selection)
    newText = if @isLinewise()
      rotated.join("\n") + "\n"
    else
      rotated.join('')

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
      spaces = _.multiplyString(' ', fillCount)
      @editor.setTextInBufferRange([eol, eol], spaces)

class MoveSelectedTextDown extends MoveSelectedTextUp
  @extend()
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

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft
}
