_ = require 'underscore-plus'
{
  requireFrom
  rotateArray
} = require './utils'
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

class MoveSelectedTextUp extends MoveSelectedTextBase
  direction: 'up'

  canMove: (selection) ->
    selection.getBufferRange().start.row > 0

  execute: ->
    for selection in @editor.getSelections()
      @countTimes @getCount(), =>
        if @canMove(selection)
          @moveLinewise(selection)

  moveLinewise: (selection) ->
    switch @direction
      when 'up'
        translationBefore = [[-1, 0], [0, 0]]
        translationAfter = [[0, 0], [-1, 0]]
        rotateDirection = 'forward'
      when 'down'
        translationBefore = [[0, 0], [1, 0]]
        translationAfter = [[1, 0], [0, 0]]
        rotateDirection = 'backward'

    mutateRange = selection.getBufferRange().translate(translationBefore...)
    @rotateRows(mutateRange, rotateDirection)
    selection.setBufferRange(mutateRange.translate(translationAfter...))

  rotateRows: (bufferRange, direction) ->
    text = @editor.getTextInBufferRange(bufferRange).replace(/\n$/, '')
    rows = text.split("\n")
    newText = rotateArray(rows, direction).join("\n") + "\n"
    @editor.setTextInBufferRange(bufferRange, newText)

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

  canMove: (selection) ->
    true

class MoveSelectedTextLeft extends MoveSelectedTextBase
  execute: ->
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
