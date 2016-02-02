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

  execute: ->
    @withUndoJoin =>
      selections = @editor.getSelectionsOrderedByBufferPosition()
      topSelection = selections[0]
      selections.reverse() if @direction is 'down'
      @editor.transact =>
        @countTimes =>
          return if (not @isLinewise()) and (not @isMovable(topSelection))
          for selection in selections
            @mutate(selection) if @isMovable(selection)

  getOverwrittenBySelection: ->
    overwrittenBySelection = new Map
    selections = @editor.getSelections()
    if @isLinewise()
      selections.forEach (selection) ->
        overwrittenBySelection.set selection,
          swrap(selection).getRows().map(-> '').join("\n")
    else
      selections.forEach (selection) ->
        overwrittenBySelection.set selection,
          _.multiplyString(' ', selection.getBufferRange().getExtent().column)
    overwrittenBySelection

  withUndoJoin: (fn) ->
    state = stateByEditor.get(@editor)
    isSequential = state.selectedTexts is @getSelectedTexts()
    unless isSequential
      state.checkpoint = @editor.createCheckpoint()
      state.overwrittenBySelection = null

    unless state.overwrittenBySelection?
      state.overwrittenBySelection = @getOverwrittenBySelection()

    fn()

    state.selectedTexts = @getSelectedTexts()
    if isSequential
      @editor.groupChangesSinceCheckpoint(state.checkpoint)

  getOverwrittenForSelection: (selection, replacedText) ->
    {overwrittenBySelection} = stateByEditor.get(@editor)
    overwrittenArea = overwrittenBySelection.get(selection)

    overwritten = switch @direction
      when 'up'
        [overwritten, rest...] = overwrittenArea.split("\n")
        overwrittenArea = [rest..., replacedText].join("\n")
        overwritten
      when 'down'
        [rest..., overwritten] = overwrittenArea.split("\n")
        overwrittenArea = [replacedText, rest...].join("\n")
        overwritten
      when 'right'
        [overwritten, rest...] = overwrittenArea
        overwrittenArea = [rest..., replacedText].join("")
        overwritten
      when 'left'
        [rest..., overwritten] = overwrittenArea
        overwrittenArea = [replacedText, rest...].join("")
        overwritten

    overwrittenBySelection.set(selection, overwrittenArea)
    overwritten

  isLinewise: ->
    switch @vimState.submode
      when 'linewise'
        true
      when 'characterwise', 'blockwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

  isMovable: (selection) ->
    switch @direction
      when 'down', 'right'
        true
      when 'up'
        selection.getBufferRange().start.row isnt 0
      when 'left'
        if @isLinewise()
          true
        else
          selection.getBufferRange().start.column isnt 0

  rotateTexts: (selection) ->
    reversed = selection.isReversed()
    # Pre mutate
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]
      when 'right' then [[0, 0], [0, +1]]
      when 'left' then [[0, -1], [0, 0]]

    range = selection.getBufferRange().translate(translation...)
    selection.setBufferRange(range)

    newText = switch @direction
      when 'up', 'down' # rotate row
        text = swrap(selection).lineTextForBufferRows()
        @rotateText(text, selection).join("\n") + "\n"
      when 'right', 'left' # rotate column
        text = selection.getText()
        @rotateText(text, selection).join('')

    range = selection.insertText(newText)
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})

  rotateText: (text, selection) ->
    switch @direction
      when 'up', 'left'
        [overwritten, rest...] = text
        overwritten = @getOverwrittenForSelection(selection, overwritten) if @isOverwrite()
        [rest..., overwritten]
      when 'down', 'right'
        [rest..., overwritten] = text
        overwritten = @getOverwrittenForSelection(selection, overwritten) if @isOverwrite()
        [overwritten, rest...]

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'
  flashTarget: false

  mutate: (selection) ->
    if @direction is 'down'
      endRow = selection.getBufferRange().end.row
      if endRow >= getVimLastBufferRow(@editor)
        eof = @editor.getEofBufferPosition()
        @editor.setTextInBufferRange([eof, eof], "\n")

    if @isLinewise()
      if @vimState.submode is 'linewise'
        @rotateTexts(selection)
      else
        swrap(selection).switchToLinewise => @rotateTexts(selection)
      @editor.scrollToCursorPosition({center: true})
    else
      @moveCharacterwise(selection)

  # Characterwise
  # -------------------------
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

  mutate: (selection) ->
    if @isLinewise()
      switch @direction
        when 'right' then selection.indentSelectedRows()
        when 'left' then selection.outdentSelectedRows()
    else
      if @direction is 'right'
        # complement space if EOL
        point = selection.getBufferRange().end
        if pointIsAtEndOfLine(@editor, point)
          @editor.setTextInBufferRange([point, point], " ")

      @rotateTexts(selection)
      @editor.scrollToCursorPosition({center: true})

class MoveSelectedTextLeft extends MoveSelectedTextRight
  direction: 'left'

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft
}
