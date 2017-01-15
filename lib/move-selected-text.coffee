_ = require 'underscore-plus'
{
  requireFrom
} = require './utils'

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
class MoveSelectedTextDown extends MoveSelectedTextUp

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
