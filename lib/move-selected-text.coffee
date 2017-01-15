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
} = require './utils'
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
{Range} = require 'atom'

{inspect} = require 'util'
p = (args...) -> console.log inspect(args...)
Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

# Move
# -------------------------
class MoveSelectedTextBase extends Operator
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

  withLinewise: (selection, fn) ->
    unless @vimState.submode is 'linewise'
      disposable = switchToLinewise(selection)
    fn(selection)
    disposable?.dispose()

class MoveSelectedTextUp extends MoveSelectedTextBase
  direction: 'up'

  canMove: (selection) ->
    selection.getBufferRange().start.row > 0

  execute: ->
    if @getWise() is 'linewise' and not @vimState.isMode('visual', 'linewise')
      disposable = switchToLinewise(@editor)

    @editor.transact =>
      for selection in @editor.getSelections()
        @countTimes @getCount(), =>
          if @canMove(selection)
            @moveLinewise(selection)

    disposable?.dispose()

  moveLinewise: (selection) ->
    [startRow, endRow] = selection.getBufferRowRange()
    startRow -= 1
    @rotateRowRange([startRow, endRow])
    endRow -= 1
    rangeToSelect = getBufferRangeForRowRange(@editor, [startRow, endRow])
    selection.setBufferRange(rangeToSelect)

  rotateRowRange: (rowRange) ->
    bufferRange = getBufferRangeForRowRange(@editor, rowRange)
    text = @editor.getTextInBufferRange(bufferRange).replace(/\n$/, '')
    rows = text.split("\n")
    switch @direction
      when 'up'
        newRows = rotateArray(rows, 'forward')
      when 'down'
        newRows = rotateArray(rows, 'backward')
    @editor.setTextInBufferRange(bufferRange, newRows.join("\n") + "\n")

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

  canMove: (selection) ->
    true

  moveLinewise: (selection) ->
    [startRow, endRow] = selection.getBufferRowRange()
    endRow += 1
    extendLastBufferRowToRow(@editor, endRow + 1)
    @rotateRowRange([startRow, endRow])
    startRow += 1
    rangeToSelect = getBufferRangeForRowRange(@editor, [startRow, endRow])
    selection.setBufferRange(rangeToSelect)

class MoveSelectedTextLeft extends MoveSelectedTextBase
  execute: ->
    @editor.transact =>
      for selection in @editor.getSelections()
        @countTimes @getCount(), =>
          @moveLinewise(selection)

  moveLinewise: (selection) ->
    selection.outdentSelectedRows()

class MoveSelectedTextRight extends MoveSelectedTextLeft
  moveLinewise: (selection) ->
    selection.indentSelectedRows()

# Duplicate
# -------------------------
class DuplicateSelectedTextBase extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false
  isOverwriteMode: ->
    atom.config.get('vim-mode-plus-move-selected-text.overwrite')

  execute: ->
    console.log "still not implemented #{@getName()}"

class DuplicateSelectedTextUp extends DuplicateSelectedTextBase
class DuplicateSelectedTextDown extends DuplicateSelectedTextUp

class DuplicateSelectedTextLeft extends DuplicateSelectedTextBase
class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft

module.exports = {
  MoveSelectedTextUp, MoveSelectedTextDown
  MoveSelectedTextLeft, MoveSelectedTextRight

  DuplicateSelectedTextUp, DuplicateSelectedTextDown
  DuplicateSelectedTextLeft, DuplicateSelectedTextRight
}
