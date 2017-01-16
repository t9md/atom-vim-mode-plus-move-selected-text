{
  requireFrom
  extendLastBufferRowToRow
  switchToLinewise
  isMultiLineSelection
  insertSpacesToPoint
  rotateChars
  rotateRows
  includeBaseMixin
  replaceBufferRangeBy
} = require './utils'

Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

StateManager = require './state-manager'
stateManager = new StateManager()

class MoveSelectedText extends Operator
  includeBaseMixin(this)
  @commandScope: 'atom-text-editor.vim-mode-plus.visual-mode'
  @commandPrefix: 'vim-mode-plus-user'
  flashTarget: false

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

  moveSelections: (fn) ->
    wise = @getWise()
    @countTimes @getCount(), =>
      for selection in @getSelections() when @canMove(selection, wise)
        fn(selection)

  execute: ->
    @withGroupChanges =>
      if @getWise() is 'linewise'
        linewiseDisposable = switchToLinewise(@editor) unless @vimState.isMode('visual', 'linewise')
        @moveSelections(@moveLinewise.bind(this))
        linewiseDisposable?.dispose()
      else
        @moveSelections(@moveCharacterwise.bind(this))

class MoveSelectedTextUp extends MoveSelectedText
  direction: 'up'

  moveCharacterwise: (selection) ->
    # Swap srcRange with dstRange(the characterwise block one line above of current block)
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

    translation.reverse()
    newRange = replaceBufferRangeBy @editor, rangeToMutate, (text) =>
      rows = text.replace(/\n$/, '').split("\n")
      {rows, overwritten} = rotateRows(rows, @direction, {overwritten})
      @setOverwrittenForSelection(selection, overwritten) if overwritten.length
      rows.join("\n") + "\n"

    selection.setBufferRange(newRange.translate(translation...), reversed: selection.isReversed())

class MoveSelectedTextDown extends MoveSelectedTextUp
  direction: 'down'

class MoveSelectedTextLeft extends MoveSelectedText
  direction: 'left'

  moveCharacterwise: (selection) ->
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

    translation.reverse()
    newRange = replaceBufferRangeBy @editor, rangeToMutate, (text) =>
      {chars, overwritten} = rotateChars(text.split(''), @direction, {overwritten})
      @setOverwrittenForSelection(selection, overwritten) if overwritten.length
      chars.join('')
    selection.setBufferRange(newRange.translate(translation...), reversed: selection.isReversed())

  moveLinewise: (selection) ->
    switch @direction
      when 'left'
        selection.outdentSelectedRows()
      when 'right'
        selection.indentSelectedRows()

class MoveSelectedTextRight extends MoveSelectedTextLeft
  direction: 'right'

module.exports = {
  stateManager: stateManager
  commands: {
    MoveSelectedTextUp
    MoveSelectedTextDown
    MoveSelectedTextLeft
    MoveSelectedTextRight
  }
}
