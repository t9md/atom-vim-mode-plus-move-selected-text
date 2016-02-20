requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/lib/#{path}"

{getVimLastBufferRow} = requireFrom('vim-mode-plus', 'utils')

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
  if (fillCount = column - eol.column) > 0
    insertTextAtPoint(editor, eol, ' '.repeat(fillCount))

extendLastBufferRowToRow = (editor, row) ->
  if row >= getVimLastBufferRow(editor)
    eof = editor.getEofBufferPosition()
    insertTextAtPoint(editor, eof, "\n")

shift = (list, num) ->
  list.splice(0, num)

pop = (list, num) ->
  list.splice(-num, num)

module.exports = {
  sortRanges
  requireFrom
  getSelectedTexts
  insertTextAtPoint
  setTextInRangeAndSelect
  insertSpacesToPoint
  extendLastBufferRowToRow
  shift
  pop
}
