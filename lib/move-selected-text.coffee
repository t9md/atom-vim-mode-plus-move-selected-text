_ = require 'underscore-plus'
{CompositeDisposable} = require 'atom'
{inspect} = require 'util'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

Base = requireFrom('vim-mode-plus', 'base')
TransformString = Base.getClass('Operator')
{pointIsAtEndOfLine, getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')

CommandPrefix = 'vim-mode-plus-user'

newState = ->
  {
    selectedTexts: null
    checkpoint: null
    overwritten: null
  }

stateByEditor = new Map
disposableByEditor = new Map

# -------------------------
class MoveSelectedText extends TransformString
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'

  initialize: ->
    stateByEditor.set(@editor, newState()) unless stateByEditor.has(@editor)
    unless disposableByEditor.has(@editor)
      disposable = @vimState.modeManager.onDidDeactivateMode ({mode}) =>
        if mode is 'visual'
          stateByEditor.delete(@editor)

      disposableByEditor.set @editor, @editor.onDidDestroy =>
        stateByEditor.delete(@editor)
        disposable.dispose()

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

          for selection, i in selections
            @selectionIndex = i
            @selectionIndex = selections.length - (i + 1) if @direction is 'down'
            @extendMovingArea(selection)
            @mutate(selection) if @isMovable(selection)

  getInitialOverwrittenArea: ->
    selections = @editor.getSelections()
    if @isLinewise()
      selections.map (selection) ->
        _.multiplyString("\n", swrap(selection).getRowCount()-1)
    else
      selections.map (selection) ->
        _.multiplyString(' ', selection.getBufferRange().getExtent().column)

  withUndoJoin: (fn) ->
    state = stateByEditor.get(@editor)
    isSequential = state.selectedTexts is @getSelectedTexts()
    unless isSequential
      state.checkpoint = @editor.createCheckpoint()
      state.overwritten = null

    unless state.overwritten?
      state.overwritten = @getInitialOverwrittenArea()

    fn()

    state.selectedTexts = @getSelectedTexts()
    if isSequential
      @editor.groupChangesSinceCheckpoint(state.checkpoint)

  getOverwrittenText: (replacedText) ->
    state = stateByEditor.get(@editor)
    overwrittenArea = state.overwritten[@selectionIndex]
    replacedText = switch @direction
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

    state.overwritten[@selectionIndex] = overwrittenArea
    replacedText

  isLinewise: ->
    switch @vimState.submode
      when 'linewise'
        true
      when 'characterwise', 'blockwise'
        @editor.getSelections().some (selection) ->
          not swrap(selection).isSingleRow()

class MoveSelectedTextUp extends MoveSelectedText
  @commandPrefix: CommandPrefix
  direction: 'up'
  flashTarget: false

  mutate: (selection) ->
    if @isLinewise()
      if @vimState.submode is 'linewise'
        @moveLinewise(selection)
      else
        swrap(selection).switchToLinewise =>
          @moveLinewise(selection)
    else
      @moveCharacterwise(selection)

  extendMovingArea: (selection) ->
    if @direction is 'down'
      endRow = selection.getBufferRange().end.row
      if endRow >= getVimLastBufferRow(@editor)
        eof = @editor.getEofBufferPosition()
        @editor.setTextInBufferRange([eof, eof], "\n")

  isMovable: (selection) ->
    switch @direction
      when 'up' then selection.getBufferRange().start.row isnt 0
      when 'down' then true

  # Characterwise
  # -------------------------
  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()

    translation = switch @direction
      when 'up' then [[-1, 0], [-1, 0]]
      when 'down' then [[1, 0], [1, 0]]

    fromRange = selection.getBufferRange()
    toRange = fromRange.translate(translation...)
    @swapTextInRange(fromRange, toRange)
    selection.setBufferRange(toRange, {reversed})

  swapTextInRange: (fromRange, toRange) ->
    @complementSpacesToPoint(toRange.end)
    movingText = @editor.getTextInBufferRange(fromRange)
    replacedText = @editor.getTextInBufferRange(toRange)
    replacedText = @getOverwrittenText(replacedText) if @isOverwrite()
    @editor.setTextInBufferRange(fromRange, replacedText)
    @editor.setTextInBufferRange(toRange, movingText)

  complementSpacesToPoint: ({row, column}) ->
    eol = @editor.bufferRangeForBufferRow(row).end
    if (fillCount = column - eol.column) > 0
      spaces = _.multiplyString(' ', fillCount)
      @editor.setTextInBufferRange([eol, eol], spaces)

  # Linewise
  # -------------------------
  moveLinewise: (selection) ->
    reversed = selection.isReversed()

    # Pre mutate
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]

    swrap(selection).translate(translation)

    lineTexts = swrap(selection).lineTextForBufferRows()
    @rotateRows(lineTexts)
    newText = lineTexts.join("\n") + "\n"
    range = selection.insertText(newText)

    # Post mutate
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})
    @editor.scrollToCursorPosition({center: true})

  rotateRows: (lineTexts) ->
    switch @direction
      when 'up'
        replacedText = lineTexts.shift()
        replacedText = @getOverwrittenText(replacedText) if @isOverwrite()
        lineTexts.push(replacedText)
      when 'down'
        replacedText = lineTexts.pop()
        replacedText = @getOverwrittenText(replacedText) if @isOverwrite()
        lineTexts.unshift(replacedText)

class MoveSelectedTextDown extends MoveSelectedTextUp
  @extend()
  direction: 'down'

# -------------------------
class MoveSelectedTextRight extends MoveSelectedText
  @commandPrefix: CommandPrefix
  direction: 'right'
  flashTarget: false

  mutate: (selection) ->
    if @isLinewise()
      @moveLinewise(selection)
    else
      @moveCharacterwise(selection)

  moveLinewise: (selection) ->
    switch @direction
      when 'right' then selection.indentSelectedRows()
      when 'left' then selection.outdentSelectedRows()

  extendMovingArea: (selection) ->
    if not @isLinewise() and @direction is 'right'
      {start, end} = selection.getBufferRange()
      if pointIsAtEndOfLine(@editor, end)
        @editor.setTextInBufferRange([end, end], " ")

  isMovable: (selection) ->
    if @isLinewise()
      true
    else
      switch @direction
        when 'right' then true
        when 'left' then selection.getBufferRange().start.column isnt 0

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()

    translation = switch @direction
      when 'right' then [[0, 0], [0, +1]]
      when 'left' then [[0, -1], [0, 0]]

    swrap(selection).translate(translation)
    newText = @rotate(selection.getText())
    range = selection.insertText(newText)
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})

  rotate: (text) ->
    switch @direction
      when 'right'
        [moving..., replacedText] = text
        replacedText = @getOverwrittenText(replacedText) if @isOverwrite()
        replacedText + moving.join('')
      when 'left'
        [replacedText, moving...] = text
        replacedText = @getOverwrittenText(replacedText) if @isOverwrite()
        moving.join('') + replacedText

class MoveSelectedTextLeft extends MoveSelectedTextRight
  direction: 'left'

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft
}
