_ = require 'underscore-plus'

{
  requireFrom
  rotateArray
  insertTextAtPoint
  ensureBufferEndWithNewLine
  getBufferRangeForRowRange
  extendLastBufferRowToRow
  switchToLinewise
  isMultiLineSelection
  insertSpacesToPoint
  rotateChars
  rotateRows
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
class MoveOrDuplicateSelectedText extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

  isOverwriteMode: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  execute: ->
    console.log "still not implemented #{@getName()}"

  getWise: ->
    {submode} = @vimState
    if submode is 'characterwise' and @editor.getSelections().some(isMultiLineSelection)
      'linewise'
    else
      submode

  withGroupChanges: (fn) ->
    stateManager.resetIfNecessary(@editor)
    @editor.transact(fn)
    stateManager.groupChanges(@editor)

class MoveSelectedText extends MoveOrDuplicateSelectedText
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

  getSelections: ->
    selections = @editor.getSelectionsOrderedByBufferPosition()
    if @direction is 'down'
      selections.reverse()
    selections

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  canMove: (selection) ->
    if @direction is 'up'
      selection.getBufferRange().start.row > 0
    else
      true

  execute: ->
    wise = @getWise()

    @withGroupChanges =>
      if wise is 'linewise' and not @vimState.isMode('visual', 'linewise')
        linewiseDisposable = switchToLinewise(@editor)

      @countTimes @getCount(), =>
        for selection in @getSelections() when @canMove(selection)
          if wise is 'linewise'
            @moveLinewise(selection)
          else
            @moveCharacterwise(selection)
      linewiseDisposable?.dispose()

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
    {newRange, overwritten} = rotateRows(selection, @direction, {overwritten})
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    rangeToSelect = newRange.translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, {reversed})

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  direction: 'left'
  execute: ->
    wise = @getWise()
    @withGroupChanges =>
      @countTimes @getCount(), =>
        for selection in @getSelections() when @canMove(selection, wise)
          if wise is 'linewise'
            @moveLinewise(selection)
          else
            @moveCharacterwise(selection)

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
    {newRange, overwritten} = rotateChars(selection, @direction, {overwritten})
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    rangeToSelect = newRange.translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, {reversed})

  moveLinewise: (selection) ->
    switch @direction
      when 'left'
        selection.outdentSelectedRows()
      when 'right'
        selection.indentSelectedRows()

  canMove: (selection, wise) ->
    switch wise
      when 'characterwise', 'blockwise'
        if @direction is 'left'
          selection.getBufferRange().start.column > 0
        else
          true
      else
        true

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

# Duplicate
# -------------------------
class DuplicateSelectedText extends MoveOrDuplicateSelectedText

class DuplicateSelectedTextUp extends DuplicateSelectedText
  direction: 'up'

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp
  direction: 'down'

class DuplicateSelectedTextLeft extends DuplicateSelectedText
  direction: 'left'
  execute: ->
    wise = @getWise()

    if wise is 'linewise' and not @vimState.isMode('visual', 'linewise')
      linewiseDisposable = switchToLinewise(@editor)

    # @countTimes @getCount(), =>
    for selection in @editor.getSelections()# when @canDuplicate(selection, wise)
      if wise is 'linewise'
        @duplicateLinewise(selection)
      else
        @duplicateCharacterwise(selection)

    linewiseDisposable?.dispose()

  # No behavior diff by isOverwriteMode() and direction('left' or 'right')
  duplicateLinewise: (selection) ->
    reversed = selection.isReversed()
    count = @getCount()
    [startRow, endRow ] = selection.getBufferRowRange()
    newText = [startRow..endRow]
      .map (row) => @editor.lineTextForBufferRow(row).repeat(count + 1)
      .join("\n") + "\n"
    newRange = selection.insertText(newText)
    selection.setBufferRange(newRange, {reversed})

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft
  direction: 'right'

commands = {
  MoveSelectedTextUp
  MoveSelectedTextDown
  MoveSelectedTextLeft
  MoveSelectedTextRight

  DuplicateSelectedTextUp
  DuplicateSelectedTextDown
  DuplicateSelectedTextLeft
  DuplicateSelectedTextRight
}

module.exports = {
  stateManager, commands
}
