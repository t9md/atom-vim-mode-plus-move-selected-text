_ = require 'underscore-plus'

{
  requireFrom
  switchToLinewise
  isMultiLineSelection
  ensureBufferEndWithNewLine
} = require './utils'
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')
{Range} = require 'atom'

{inspect} = require 'util'
p = (args...) -> console.log inspect(args...)
Base = requireFrom('vim-mode-plus', 'base')
Operator = Base.getClass('Operator')

# Duplicate
# -------------------------
class DuplicateSelectedText extends Operator
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


class DuplicateSelectedTextUp extends DuplicateSelectedText
  direction: 'up'
  execute: ->
    wise = @getWise()

    if wise is 'linewise' and not @vimState.isMode('visual', 'linewise')
      linewiseDisposable = switchToLinewise(@editor)

    for selection in @getSelections()
      if wise is 'linewise'
        @duplicateLinewise(selection)
      else
        @duplicateCharacterwise(selection)

    linewiseDisposable?.dispose()

  duplicateLinewise: (selection) ->
    reversed = selection.isReversed()
    count = @getCount()
    [startRow, endRow ] = selection.getBufferRowRange()
    rows = [startRow..endRow].map (row) => @editor.lineTextForBufferRow(row)
    height = rows.length * count
    newText = (rows.join("\n") + "\n").repeat(count)

    {start, end} = selection.getBufferRange()
    if @direction is 'down' and end.isEqual(@editor.getEofBufferPosition())
      end = ensureBufferEndWithNewLine(@editor)

    if @isOverwriteMode()
      rangeToMutate = switch @direction
        when 'up' then [start.translate([-height, 0]), start]
        when 'down' then [end, end.translate([+height, 0])]
    else
      rangeToMutate = switch @direction
        when 'up' then [start, start]
        when 'down' then [end, end]

    newRange = @editor.setTextInBufferRange(rangeToMutate, newText)
    selection.setBufferRange(newRange, {reversed})

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

module.exports = {
  DuplicateSelectedTextUp
  DuplicateSelectedTextDown
  DuplicateSelectedTextLeft
  DuplicateSelectedTextRight
}
