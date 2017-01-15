{Disposable} = require 'atom'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

swrap = requireFrom('vim-mode-plus', 'selection-wrapper')

rotateArray = (list, direction) ->
  console.log direction
  list = list.slice()
  switch direction
    when 'forward'
      last = list.shift()
      [list..., last]
    when 'backward'
      console.log "THIS"
      first = list.pop()
      [first, list...]

getSelectedTexts = (editor) ->
  texts = (selection.getText() for selection in editor.getSelections())
  texts.join("\n")
insertTextAtPoint = (editor, point, text) ->
  editor.setTextInBufferRange([point, point], text)

setTextInRangeAndSelect = (range, text, selection) ->
  {editor} = selection
  selection.setBufferRange(editor.setTextInBufferRange(range, text))

insertSpacesToPoint = (editor, {row, column}) ->
  eol = editor.bufferRangeForBufferRow(row).end
  if (count = column - eol.column) > 0
    insertTextAtPoint(editor, eol, ' '.repeat(count))

extendLastBufferRowToRow = (editor, row) ->
  if (count = row - editor.getLastBufferRow()) > 0
    eof = editor.getEofBufferPosition()
    insertTextAtPoint(editor, eof, "\n".repeat(count))

# Return new EOF
ensureBufferEndWithNewLine = (editor) ->
  eof = editor.getEofBufferPosition()
  insertTextAtPoint(editor, eof, "\n") unless eof.column is 0
  editor.getEofBufferPosition()

shift = (list, num) ->
  list.splice(0, num)

pop = (list, num) ->
  list.splice(-num, num)

# Return function to restore
switchToLinewise = (selection) ->
  selection = swrap(selection)
  selection.saveProperties()
  selection.applyWise('linewise')
  new Disposable ->
    selection.normalize()
    selection.applyWise('characterwise')

opposite = (direction) ->
  switch direction
    when 'up' then 'down'
    when 'down' then 'up'
    when 'left' then 'right'
    when 'right' then 'left'

module.exports = {
  requireFrom
  rotateArray

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
