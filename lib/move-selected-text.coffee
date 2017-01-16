_ = require 'underscore-plus'

{
  requireFrom
  insertTextAtPoint
  getBufferRangeForRowRange
  extendLastBufferRowToRow
  switchToLinewise
  isMultiLineSelection
  insertSpacesToPoint
  rotateChars
  rotateRows
  ensureBufferEndWithNewLine
} = require './utils'
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
{Range} = require 'atom'

{inspect} = require 'util'
p = (args...) -> console.log inspect(args...)
Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

StateManager = require './state-manager'
stateManager = new StateManager()
# Move
# -------------------------
class MoveSelectedText extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

  isOverwriteMode: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  getWise: ->
    {submode} = @vimState
    if submode is 'characterwise' and @editor.getSelections().some(isMultiLineSelection)
      'linewise'
    else
      submode

  getSelections: ->
    selections = @editor.getSelectionsOrderedByBufferPosition()
    if @direction is 'down'
      selections.reverse()
    selections

  hasOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.has(selection)

  getOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.get(selection)

  setOverwrittenForSelection: (selection, overwritten) ->
    stateManager.get(@editor).overwrittenBySelection.set(selection, overwritten)

  getOrInitOverwrittenForSelection: (selection, initializer) ->
    unless @hasOverwrittenForSelection(selection)
      @setOverwrittenForSelection(selection, initializer())
    @getOverwrittenForSelection(selection)

  canMove: (selection, wise) ->
    switch @direction
      when 'up'
        selection.getBufferRange().start.row > 0
      when 'down', 'right'
        true
      when 'left'
        if wise in ['characterwise', 'blockwise']
          selection.getBufferRange().start.column > 0
        else
          true

  withGroupChanges: (fn) ->
    stateManager.resetIfNecessary(@editor)
    @editor.transact(fn)
    stateManager.groupChanges(@editor)

  execute: ->
    wise = @getWise()

    @withGroupChanges =>
      if (@direction in ['up', 'down']) and (wise is 'linewise') and not @vimState.isMode('visual', 'linewise')
        linewiseDisposable = switchToLinewise(@editor)

      @countTimes @getCount(), =>
        for selection in @getSelections() when @canMove(selection, wise)
          if wise is 'linewise'
            @moveLinewise(selection)
          else
            @moveCharacterwise(selection)
      linewiseDisposable?.dispose()

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    srcRange = selection.getBufferRange()

    dstRange = switch @direction
      when 'up' then srcRange.translate([-1, 0])
      when 'down' then srcRange.translate([+1, 0])

    extendLastBufferRowToRow(@editor, dstRange.end.row)
    insertSpacesToPoint(@editor, dstRange.end)
    srcText = @editor.getTextInBufferRange(srcRange)
    dstText = @editor.getTextInBufferRange(dstRange)

    if @isOverwriteMode()
      overwritten = @getOrInitOverwrittenForSelection selection, ->
        new Array(srcText.length).fill(' ')
      @setOverwrittenForSelection(selection, dstText.split(''))
      dstText = overwritten.join('')

    @editor.setTextInBufferRange(srcRange, dstText)
    @editor.setTextInBufferRange(dstRange, srcText)
    selection.setBufferRange(dstRange, {reversed})

  moveLinewise: (selection) ->
    reversed = selection.isReversed()
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]

    range = selection.getBufferRange()
    rangeToMutate = range.translate(translation...)
    extendLastBufferRowToRow(@editor, rangeToMutate.end.row)

    overwritten = null
    if @isOverwriteMode()
      height = range.getRowCount() - 1
      overwritten = @getOrInitOverwrittenForSelection selection, ->
        new Array(height).fill('')

    selection.setBufferRange(rangeToMutate)
    rows = selection.getText().replace(/\n$/, '').split("\n")
    {rows, overwritten} = rotateRows(rows, @direction, {overwritten})
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    newText = rows.join("\n") + "\n"
    rangeToSelect = selection.insertText(newText).translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, {reversed})

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  direction: 'left'

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    translation = switch @direction
      when 'right' then [[0, 0], [0, 1]]
      when 'left' then [[0, -1], [0, 0]]

    rangeToMutate = selection.getBufferRange().translate(translation...)
    insertSpacesToPoint(@editor, rangeToMutate.end)

    overwritten = null
    if @isOverwriteMode()
      textLength = selection.getText().length
      overwritten = @getOrInitOverwrittenForSelection selection, ->
        new Array(textLength).fill(' ')

    selection.setBufferRange(rangeToMutate)
    chars = selection.getText().split('')
    {chars, overwritten} = rotateChars(chars, @direction, {overwritten})
    newText = chars.join("")
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    rangeToSelect = selection.insertText(newText).translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, {reversed})

  moveLinewise: (selection) ->
    switch @direction
      when 'left'
        selection.outdentSelectedRows()
      when 'right'
        selection.indentSelectedRows()

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

commands = {
  MoveSelectedTextUp
  MoveSelectedTextDown
  MoveSelectedTextLeft
  MoveSelectedTextRight
}

module.exports = {
  stateManager, commands
}
