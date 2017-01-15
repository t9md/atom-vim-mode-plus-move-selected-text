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
  newArray
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
    if @isOverwriteMode()
      unless @hasOverwrittenForSelection(selection)
        @setOverwrittenForSelection(selection, initializer())
      @getOverwrittenForSelection(selection)
    else
      []

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  canMove: (selection) ->
    if @direction is 'up'
      selection.getBufferRange().start.row > 0
    else
      true

  getSelections: ->
    selections = @editor.getSelectionsOrderedByBufferPosition()
    if @direction is 'down'
      selections.reverse()
    selections

  execute: ->
    wise = @getWise()
    selections = @editor.getSelections()
    selections.reverse() if @direction is 'up'

    @withGroupChanges =>
      if wise is 'linewise' and not @vimState.isMode('visual', 'linewise')
        linewiseDisposable = switchToLinewise(@editor)

      @countTimes @getCount(), =>
        for selection in @getSelections()
          switch wise
            when 'linewise'
              @moveLinewise(selection) if @canMove(selection, wise)
            when 'characterwise'
              @moveCharacterwise(selection) if @canMove(selection, wise)
            else
              @moveCharacterwise(selection) if @canMove(selection, wise)

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
      overwritten = @getOrInitOverwrittenForSelection(selection, -> " ".repeat(srcText.length))
      @setOverwrittenForSelection(selection, dstText)
      dstText = overwritten

    @editor.setTextInBufferRange(srcRange, dstText)
    @editor.setTextInBufferRange(dstRange, srcText)
    selection.setBufferRange(dstRange, {reversed})

  moveLinewise: (selection) ->
    reversed = selection.isReversed()
    translation = switch @direction
      when 'up' then [[-1, 0], [0, 0]]
      when 'down' then [[0, 0], [1, 0]]

    rangeToMutate = selection.getBufferRange().translate(translation...)
    extendLastBufferRowToRow(@editor, rangeToMutate.end.row)
    selection.setBufferRange(rangeToMutate)
    rangeToSelect = @rotateSelectedRows(selection).translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, {reversed})

  rotateSelectedRows: (selection) ->
    rows = selection.getText().replace(/\n$/, '').split("\n")

    overwritten = @getOrInitOverwrittenForSelection selection, ->
      new Array(rows.length - 1).fill('')

    rotateDirection = switch @direction
      when 'up' then 'forward'
      when 'down' then 'backward'

    overwritten = rotateArray([rows..., overwritten...], rotateDirection)
    rows = overwritten.splice(0, rows.length)
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    selection.insertText(rows.join("\n") + "\n")

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  direction: 'left'
  execute: ->
    wise = @getWise()

    @withGroupChanges =>
      @countTimes @getCount(), =>
        for selection in @editor.getSelections()
          switch wise
            when 'linewise'
              @moveLinewise(selection) if @canMove(selection, wise)
            when 'characterwise'
              @moveCharacterwise(selection) if @canMove(selection, wise)
            else
              console.log "NOT YET"

  moveCharacterwise: (selection) ->
    reversed = selection.isReversed()
    translation = switch @direction
      when 'right' then [[0, 0], [0, 1]]
      when 'left' then [[0, -1], [0, 0]]

    rangeToMutate = selection.getBufferRange().translate(translation...)
    insertSpacesToPoint(@editor, rangeToMutate.end)
    selection.setBufferRange(rangeToMutate)
    rangeToSelect = @rotateChars(selection).translate(translation.reverse()...)
    selection.setBufferRange(rangeToSelect, {reversed})

  rotateChars: (selection) ->
    chars = selection.getText().split('')

    overwritten = @getOrInitOverwrittenForSelection selection, ->
      new Array(chars.length - 1).fill(' ')

    rotateDirection = switch @direction
      when 'right' then 'backward'
      when 'left' then 'forward'

    overwritten = rotateArray([chars..., overwritten...], rotateDirection)
    chars = overwritten.splice(0, chars.length)
    @setOverwrittenForSelection(selection, overwritten) if overwritten.length
    selection.insertText(chars.join(""))

  moveLinewise: (selection) ->
    switch @direction
      when 'left'
        selection.outdentSelectedRows()
      when 'right'
        selection.indentSelectedRows()

  canMove: (selection, wise) ->
    switch @direction
      when 'left'
        if wise is 'characterwise'
          selection.getBufferRange().start.column > 0
        else
          true
      when 'right'
        true

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

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
