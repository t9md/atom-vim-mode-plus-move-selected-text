# Used
# -------------------------
{Disposable} = require 'atom'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

swrap = requireFrom('vim-mode-plus', 'selection-wrapper')

rotateArray = (list, direction) ->
  list = list.slice()
  switch direction
    when 'forward'
      last = list.shift()
      [list..., last]
    when 'backward'
      first = list.pop()
      [first, list...]

insertTextAtPoint = (editor, point, text) ->
  editor.setTextInBufferRange([point, point], text)

getBufferRangeForRowRange = (editor, rowRange) ->
  [startRange, endRange] = rowRange.map (row) ->
    editor.bufferRangeForBufferRow(row, includeNewline: true)
  startRange.union(endRange)

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

rotateRows = (selection, direction, {overwritten}={}) ->
  overwritten ?= []
  rows = selection.getText().replace(/\n$/, '').split("\n")
  switch direction
    when 'up'
      overwritten = rotateArray([rows..., overwritten...], 'forward')
    when 'down'
      overwritten = rotateArray([rows..., overwritten...], 'backward')
  rows = overwritten.splice(0, rows.length)
  newRange = selection.insertText(rows.join("\n") + "\n")
  {newRange, overwritten}

rotateChars = (selection, direction, {overwritten}={}) ->
  chars = selection.getText().split('')
  switch direction
    when 'right'
      [other..., char] = chars
      if overwritten?
        chars = [overwritten.shift(), other...]
        overwritten.push(char)
      else
        chars = [char, other...]
        overwritten = []
    when 'left'
      [char, other...,] = chars
      if overwritten?
        chars = [other..., overwritten.pop()]
        overwritten.unshift(char)
      else
        chars = [other..., char]
        overwritten = []

  newRange = selection.insertText(chars.join(""))
  {newRange, overwritten}

# Unused
# -------------------------
getSelectedTexts = (editor) ->
  texts = (selection.getText() for selection in editor.getSelections())
  texts.join("\n")

setTextInRangeAndSelect = (range, text, selection) ->
  {editor} = selection
  selection.setBufferRange(editor.setTextInBufferRange(range, text))

extendLastBufferRowToRow = (editor, row) ->
  if (count = row - editor.getLastBufferRow()) > 0
    eof = editor.getEofBufferPosition()
    insertTextAtPoint(editor, eof, "\n".repeat(count))

shift = (list, num) ->
  list.splice(0, num)

pop = (list, num) ->
  list.splice(-num, num)

# Return function to restore
switchToLinewise = (editor) ->
  swrap.saveProperties(editor)
  swrap.applyWise(editor, 'linewise')
  new Disposable ->
    swrap.normalize(editor)
    swrap.applyWise(editor, 'characterwise')

opposite = (direction) ->
  switch direction
    when 'up' then 'down'
    when 'down' then 'up'
    when 'left' then 'right'
    when 'right' then 'left'

module.exports = {
  requireFrom
  rotateArray
  getBufferRangeForRowRange
  isMultiLineSelection
  rotateChars
  rotateRows

  getSelectedTexts
  insertTextAtPoint
  setTextInRangeAndSelect
  insertSpacesToPoint
  extendLastBufferRowToRow
  ensureBufferEndWithNewLine
  switchToLinewise
  shift
  pop
  opposite
}
