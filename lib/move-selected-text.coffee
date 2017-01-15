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
  execute: ->
    console.log "still not implemented #{@getName()}"


class MoveSelectedTextUp extends MoveSelectedTextBase
class MoveSelectedTextDown extends MoveSelectedTextUp

class MoveSelectedTextLeft extends MoveSelectedTextBase
class MoveSelectedTextRight extends MoveSelectedTextLeft

# Duplicate
# -------------------------
class DuplicateSelectedTextBase extends Operator
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false
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
