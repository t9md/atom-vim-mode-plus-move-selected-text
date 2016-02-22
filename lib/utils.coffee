{Disposable} = require 'atom'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

{getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')
swrap = requireFrom('vim-mode-plus', 'selection-wrapper')

sortRanges = (ranges) ->
  ranges.sort((a, b) -> a.compare(b))

getSelectedTexts = (editor) ->
  texts = (selection.getText() for selection in editor.getSelections())
  texts.join("\n")

insertTextAtPoint = (editor, point, text) ->
  editor.setTextInBufferRange([point, point], text)

setTextInRangeAndSelect = (range, text, selection) ->
  {editor} = selection
  newRange = editor.setTextInBufferRange(range, text)
  selection.setBufferRange(newRange)

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
  swrap(selection).preserveCharacterwise()
  swrap(selection).expandOverLine(preserveGoalColumn: true)
  new Disposable ->
    swrap(selection).restoreCharacterwise()

module.exports = {
  sortRanges
  requireFrom
  getSelectedTexts
  insertTextAtPoint
  setTextInRangeAndSelect
  insertSpacesToPoint
  extendLastBufferRowToRow
  ensureBufferEndWithNewLine
  switchToLinewise
  shift
  pop
}
