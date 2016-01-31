_ = require 'underscore-plus'
{CompositeDisposable} = require 'atom'
# {inspect} = require 'util' # debug purpose

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

Base = requireFrom('vim-mode-plus', 'base')
TransformString = Base.getClass('Operator')
{pointIsAtEndOfLine, getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')

CommandPrefix = 'vim-mode-plus-user'
stateByEditor = new Map
checkPointByEditor = new Map
disposableByEditor = new Map
overwrittenByEditor = new Map

# -------------------------
class MoveSelectedText extends TransformString
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'

  execute: ->
    @withUndoJoin =>
      selections = @editor.getSelectionsOrderedByBufferPosition()
      selections.reverse() if @direction is 'down'
      @initOverwrittenByEditor()
      @editor.transact =>
        @countTimes =>
          @_takenIndex = 0
          for selection in selections
            @mutate(selection) if @isMovable(selection)

  initOverwrittenByEditor: ->
    unless overwrittenByEditor.has(@editor)
      if @isLinewise()
        rowCount = swrap(@editor.getLastSelection()).getRowCount()
        overwrittenArea = [1..rowCount].map -> ''
      else
        width = @editor.getLastSelection().getBufferRange().getExtent().column
        overwrittenArea = @editor.getSelections().map (selection) ->
          _.multiplyString(' ', width)
      overwrittenByEditor.set(@editor, overwrittenArea)

  getSelectedTexts: ->
    @editor.getSelections().map((selection) -> selection.getText()).join('')

  getMoveMethod: ->
    @_moveMethod ?= atom.config.get('vim-mode-plus-move-selected-text.moveMethod')
    @_moveMethod

  withUndoJoin: (fn) ->
    unless disposableByEditor.has(@editor)
      disposable = @vimState.modeManager.onDidDeactivateMode ({mode}) ->
        if mode is 'visual'
          stateByEditor.delete(@editor)
          overwrittenByEditor.delete(@editor)

      disposableByEditor.set @editor, @editor.onDidDestroy =>
        checkPointByEditor.delete(@editor)
        stateByEditor.delete(@editor)
        disposableByEditor.delete(@editor)
        overwrittenByEditor.delete(@editor)
        disposable.dispose()

    isSequential = stateByEditor.get(@editor) is @getSelectedTexts()
    unless isSequential
      checkPointByEditor.set(@editor, @editor.createCheckpoint())
      overwrittenByEditor.delete(@editor)
    fn()

    stateByEditor.set(@editor, @getSelectedTexts())
    if isSequential and (checkpoint = checkPointByEditor.get(@editor))
      @editor.groupChangesSinceCheckpoint(checkpoint)

  getOverwrittenText: (replacedText) ->
    overwrittenArea = overwrittenByEditor.get(@editor)
    switch @direction
      when 'up'
        overwrittenArea.push(replacedText)
        overwrittenArea.shift()
      when 'down'
        overwrittenArea.unshift(replacedText)
        overwrittenArea.pop()
      when 'right'
        [other..., last] = overwrittenArea[@_takenIndex]
        overwrittenArea[@_takenIndex] = replacedText + other.join('')
        @_takenIndex++
        last
      when 'left'
        [first, other...] = overwrittenArea[@_takenIndex]
        overwrittenArea[@_takenIndex] = other.join('') + replacedText
        @_takenIndex++
        first

  isLinewise: ->
    switch @vimState.submode
      when 'linewise' then true
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

  isMovable: (selection) ->
    switch @direction
      when 'up'
        selection.getBufferRange().start.row isnt 0
      when 'down'
        # Extend last buffer line if selection end is last buffer row
        endRow = selection.getBufferRange().end.row
        if endRow >= getVimLastBufferRow(@editor)
          eof = @editor.getEofBufferPosition()
          @editor.setTextInBufferRange([eof, eof], "\n")
        true

  getRangeTranslationSpec: (wise) ->
    if wise is 'linewise'
      switch @direction
        when 'up' then [[-1, 0], [0, 0]]
        when 'down' then [[0, 0], [1, 0]]
    else if 'characterwis'
      switch @direction
        when 'up' then [[-1, 0], [-1, 0]]
        when 'down' then [[1, 0], [1, 0]]

  # Characterwise
  # -------------------------
  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    translation = @getRangeTranslationSpec('characterwise')
    fromRange = selection.getBufferRange()
    toRange = fromRange.translate(translation...)
    @swapTextInRange(fromRange, toRange)
    selection.setBufferRange(toRange, {reversed})

  swapTextInRange: (fromRange, toRange) ->
    @complementSpacesToPoint(toRange.end)
    movingText = @editor.getTextInBufferRange(fromRange)
    replacedText = @editor.getTextInBufferRange(toRange)

    if @getMoveMethod() is 'overwrite'
      replacedText = @getOverwrittenText(replacedText)

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
    translation = @getRangeTranslationSpec('linewise')
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
        if @getMoveMethod() is 'overwrite'
          replacedText = @getOverwrittenText(replacedText)
        lineTexts.push(replacedText)
      when 'down'
        replacedText = lineTexts.pop()
        if @getMoveMethod() is 'overwrite'
          replacedText = @getOverwrittenText(replacedText)
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

  isMovable: (selection) ->
    if @isLinewise()
      true
    else
      {start, end} = selection.getBufferRange()
      switch @direction
        when 'right'
          if pointIsAtEndOfLine(@editor, end)
            @editor.setTextInBufferRange([end, end], " ")
          true
        when 'left'
          start.column isnt 0

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    translation = @getRangeTranslationSpec()
    swrap(selection).translate(translation)
    newText = @rotate(selection.getText())
    range = selection.insertText(newText)
    range = range.translate(translation.reverse()...)
    selection.setBufferRange(range, {reversed})

  rotate: (text) ->
    switch @direction
      when 'right'
        [moving..., replacedText] = text
        if @getMoveMethod() is 'overwrite'
          replacedText = @getOverwrittenText(replacedText)
        replacedText + moving.join('')
      when 'left'
        [replacedText, moving...] = text
        if @getMoveMethod() is 'overwrite'
          replacedText = @getOverwrittenText(replacedText)
        moving.join('') + replacedText

  getRangeTranslationSpec: ->
    switch @direction
      when 'right' then [[0, 0], [0, +1]]
      when 'left' then [[0, -1], [0, 0]]

class MoveSelectedTextLeft extends MoveSelectedTextRight
  direction: 'left'

module.exports = {
  MoveSelectedTextDown, MoveSelectedTextUp
  MoveSelectedTextRight, MoveSelectedTextLeft
}
