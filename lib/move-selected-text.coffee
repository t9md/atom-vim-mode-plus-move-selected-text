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
    unless stateManager.isSequentialExecution(@editor)
      stateManager.reset(@editor)
    @editor.transact(fn)
    stateManager.groupChanges(@editor)

class MoveSelectedText extends MoveOrDuplicateSelectedText
  hasOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.has(selection)

  getOverwrittenForSelection: (selection) ->
    stateManager.get(@editor).overwrittenBySelection.get(selection)

  setOverwrittenForSelection: (selection, overwritten) ->
    stateManager.get(@editor).overwrittenBySelection.set(selection, overwritten)

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
        disposable = switchToLinewise(@editor)

      @editor.transact =>
        for selection in @editor.getSelections()
          @countTimes @getCount(), =>
            if wise is 'linewise'
              @moveLinewise(selection) if @canMove(selection)
            else
              console.log "NOT YET"

      disposable?.dispose()

  moveLinewise: (selection) ->
    reversed = selection.isReversed()

    if @direction is 'up'
      rangeToMutate = selection.getBufferRange().translate([-1, 0], [0, 0])
      selection.setBufferRange(rangeToMutate)
      rangeToSelect = @rotateSelectedRows(selection).translate([0, 0], [-1, 0])
      selection.setBufferRange(rangeToSelect, {reversed})

    else if @direction is 'down'
      rangeToMutate = selection.getBufferRange().translate([0, 0], [1, 0])
      extendLastBufferRowToRow(@editor, rangeToMutate.end.row)
      selection.setBufferRange(rangeToMutate)
      rangeToSelect = @rotateSelectedRows(selection).translate([1, 0], [0, 0])
      selection.setBufferRange(rangeToSelect, {reversed})

  rotateSelectedRows: (selection) ->
    if @isOverwriteMode()
      unless @hasOverwrittenForSelection(selection)
        [startRow, endRow] = selection.getBufferRowRange()
        @setOverwrittenForSelection(selection, new Array(endRow - startRow).fill(''))
      overwritten = @getOverwrittenForSelection(selection)
    else
      overwritten = []

    selectedText = selection.getText()
    rows = selectedText.replace(/\n$/, '').split("\n")
    rotateDirection =
      switch @direction
        when 'up' then 'forward'
        when 'down' then 'backward'
    overwritten = rotateArray([rows..., overwritten...], rotateDirection)
    newRows = overwritten.splice(0, rows.length)
    if overwritten.length
      @setOverwrittenForSelection(selection, overwritten)
    selection.insertText(newRows.join("\n") + "\n")

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  execute: ->
    wise = @getWise()

    @withGroupChanges =>
      for selection in @editor.getSelections()
        @countTimes @getCount(), =>
          if wise is 'linewise'
            @moveLinewise(selection)
          else
            console.log 'not yet implemented'

  moveLinewise: (selection) ->
    selection.outdentSelectedRows()

class MoveSelectedTextRight extends MoveSelectedTextLeft
  moveLinewise: (selection) ->
    selection.indentSelectedRows()

# Duplicate
# -------------------------
class DuplicateSelectedText extends MoveOrDuplicateSelectedText

class DuplicateSelectedTextUp extends DuplicateSelectedText

class DuplicateSelectedTextDown extends DuplicateSelectedTextUp

class DuplicateSelectedTextLeft extends DuplicateSelectedText

class DuplicateSelectedTextRight extends DuplicateSelectedTextLeft

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
