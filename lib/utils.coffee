# Used
# -------------------------
{Disposable} = require 'atom'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

swrap = requireFrom('vim-mode-plus', 'selection-wrapper')

insertTextAtPoint = (editor, point, text) ->
  editor.setTextInBufferRange([point, point], text)

# Return new EOF
ensureBufferEndWithNewLine = (editor) ->
  eof = editor.getEofBufferPosition()
  unless eof.column is 0
    insertTextAtPoint(editor, eof, "\n")
  editor.getEofBufferPosition()

extendLastBufferRowToRow = (editor, row) ->
  if (count = row - editor.getLastBufferRow()) > 0
    eof = editor.getEofBufferPosition()
    insertTextAtPoint(editor, eof, "\n".repeat(count))

isMultiLineSelection = (selection) ->
  {start, end} = selection.getBufferRange()
  start.row isnt end.row

insertSpacesToPoint = (editor, {row, column}) ->
  eol = editor.bufferRangeForBufferRow(row).end
  if (count = column - eol.column) > 0
    insertTextAtPoint(editor, eol, ' '.repeat(count))

rotateChars = (chars, direction, {overwritten}={}) ->
  # e.g.
  # Assume situation where moving `pple` perfectly cover existing `lemon`
  #  overwritten =   |1|2|3|4| <- this is hidden by chars `apple`
  #  Text =        |Z|A|B|C|D|E|
  #  Moving =        |A|B|C|D|   <- now moving |ABCD|(visually selected)
  #  Chars(R) =      |A|B|C|D|E| <- Chars when moving 'Right' selected one char right
  #  Chars(L) =    |Z|A|B|C|D|  <- Chars when moving 'Left', selected one char left
  #
  # - overwritten.length = 4
  # - chars.length = 5(thus always 1 length longer than overwritten)
  #
  overwritten ?= []
  switch direction
    when 'right', 'down'
      # Move right-most(last in array) char to left-most(first in array)
      #  - From: overwritten = 1234, chars = ABCDE
      #  - To:   overwritten = 234E, chars = 1ABCD ('E' was hidden, '1' appeared)
      overwritten.push(chars.pop()) # overwritten = 1234E, chars = ABCD
      chars.unshift(overwritten.shift()) # overwritten = 234E, chars = 1ABCD
    when 'left', 'up'
      # Move left-most(first in array) char to right-most(last in array)
      #  - From: overwritten = 1234, chars = ZABCD
      #  - To:   overwritten = Z123, chars = ABCD4 ('Z' was hidden, '4' appeared)
      overwritten.unshift(chars.shift()) # overwritten = Z1234, chars = ABCD
      chars.push(overwritten.pop()) # overwritten = Z123, chars = ABCD4
  {chars, overwritten}

# Completely identical with rotateChars function except variable name.
# But I put here for explicitness(I frequently confused when I revisit code).
rotateRows = (rows, direction, {overwritten}={}) ->
  {chars, overwritten} = rotateChars(rows, direction, {overwritten})
  {rows: chars, overwritten}

extendLastBufferRowToRow = (editor, row) ->
  if (count = row - editor.getLastBufferRow()) > 0
    eof = editor.getEofBufferPosition()
    insertTextAtPoint(editor, eof, "\n".repeat(count))

# Return function to restore
switchToLinewise = (editor) ->
  swrap.saveProperties(editor)
  swrap.applyWise(editor, 'linewise')
  new Disposable ->
    swrap.normalize(editor)
    swrap.applyWise(editor, 'characterwise')

# e.g.
#  repeatArray([1, 2, 3], 3) => [ 1, 2, 3, 1, 2, 3, 1, 2, 3 ]
repeatArray = (array, amount) ->
  [1..amount]
    .map -> array
    .reduce (a, b) -> a.concat(b)

setBufferRangesForBlockwiseSelection = (blockwiseSelection, ranges) ->
  head = blockwiseSelection.getHeadSelection()
  wasReversed = blockwiseSelection.isReversed()
  blockwiseSelection.setSelectedBufferRanges(ranges, {reversed: head.isReversed()})
  blockwiseSelection.reverse() if wasReversed

insertBlankRowAtPoint = (editor, point, count) ->
  insertTextAtPoint(editor, point, "\n".repeat(count))

# Update selected bufferRange to range returned by callback
setBufferRangeForSelectionBy = (selection, fn) ->
  reversed = selection.isReversed()
  newRange = fn()
  if newRange?
    selection.setBufferRange(newRange, {reversed})

# Return mutated range
replaceBufferRangeBy = (editor, range, fn) ->
  oldText = editor.getTextInBufferRange(range)
  editor.setTextInBufferRange(range, fn(oldText))

replaceRangeAndSelect = (selection, range, {translation}={}, fn) ->
  setBufferRangeForSelectionBy selection, ->
    newRange = replaceBufferRangeBy(selection.editor, range, fn)
    if translation?
      newRange.translate(translation...)
    else
      newRange

baseMixin =
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

includeBaseMixin = (klass) ->
  for key, value of baseMixin
    klass::[key] = value

module.exports = {
  requireFrom
  isMultiLineSelection
  rotateChars
  rotateRows
  insertTextAtPoint
  insertSpacesToPoint
  extendLastBufferRowToRow
  ensureBufferEndWithNewLine
  switchToLinewise
  repeatArray
  setBufferRangesForBlockwiseSelection
  insertBlankRowAtPoint
  includeBaseMixin
  replaceBufferRangeBy
  setBufferRangeForSelectionBy
  replaceRangeAndSelect
}
