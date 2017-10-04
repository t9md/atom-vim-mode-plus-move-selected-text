const {Disposable} = require("atom")

function insertTextAtPoint(editor, point, text) {
  return editor.setTextInBufferRange([point, point], text)
}

// Return new EOF
function ensureBufferEndWithNewLine(editor) {
  const eof = editor.getEofBufferPosition()
  if (eof.column !== 0) {
    insertTextAtPoint(editor, eof, "\n")
  }
  return editor.getEofBufferPosition()
}

function extendLastBufferRowToRow(editor, row) {
  const count = row - editor.getLastBufferRow()
  if (count > 0) {
    const eof = editor.getEofBufferPosition()
    insertTextAtPoint(editor, eof, "\n".repeat(count))
  }
}

function isMultiLineSelection(selection) {
  const {start, end} = selection.getBufferRange()
  return start.row !== end.row
}

function insertSpacesToPoint(editor, {row, column}) {
  const eol = editor.bufferRangeForBufferRow(row).end
  const count = column - eol.column
  if (count > 0) {
    return insertTextAtPoint(editor, eol, " ".repeat(count))
  }
}

function rotateChars(chars, direction, {overwritten = []} = {}) {
  // e.g.
  // Assume situation where moving `pple` perfectly cover existing `lemon`
  //  overwritten =   |1|2|3|4| <- this is hidden by chars `apple`
  //  Text =        |Z|A|B|C|D|E|
  //  Moving =        |A|B|C|D|   <- now moving |ABCD|(visually selected)
  //  Chars(R) =      |A|B|C|D|E| <- Chars when moving 'Right' selected one char right
  //  Chars(L) =    |Z|A|B|C|D|  <- Chars when moving 'Left', selected one char left
  //
  // - overwritten.length = 4
  // - chars.length = 5(thus always 1 length longer than overwritten)
  //
  switch (direction) {
    case "right":
    case "down":
      // Move right-most(last in array) char to left-most(first in array)
      //  - From: overwritten = 1234, chars = ABCDE
      //  - To:   overwritten = 234E, chars = 1ABCD ('E' was hidden, '1' appeared)
      overwritten.push(chars.pop()) // overwritten = 1234E, chars = ABCD
      chars.unshift(overwritten.shift()) // overwritten = 234E, chars = 1ABCD
      break
    case "left":
    case "up":
      // Move left-most(first in array) char to right-most(last in array)
      //  - From: overwritten = 1234, chars = ZABCD
      //  - To:   overwritten = Z123, chars = ABCD4 ('Z' was hidden, '4' appeared)
      overwritten.unshift(chars.shift()) // overwritten = Z1234, chars = ABCD
      chars.push(overwritten.pop()) // overwritten = Z123, chars = ABCD4
      break
  }
  return {chars, overwritten}
}

// Completely identical with rotateChars function except variable name.
// But I put here for explicitness(I frequently confused when I revisit code).
function rotateRows(rows, direction, {overwritten} = {}) {
  const result = rotateChars(rows, direction, {overwritten})
  return {rows: result.chars, overwritten: result.overwritten}
}

// e.g.
//  repeatArray([1, 2, 3], 3) => [ 1, 2, 3, 1, 2, 3, 1, 2, 3 ]
function repeatArray(array, amount) {
  const newArray = []
  while (amount-- > 0) newArray.push(...array)
  return newArray
}

function setBufferRangesForBlockwiseSelection(blockwiseSelection, ranges) {
  const head = blockwiseSelection.getHeadSelection()
  const wasReversed = blockwiseSelection.isReversed()
  blockwiseSelection.setSelectedBufferRanges(ranges, {reversed: head.isReversed()})
  if (wasReversed) {
    blockwiseSelection.reverse()
  }
}

// Return mutated range
function replaceRange(editor, range, fn) {
  const text = editor.getTextInBufferRange(range)
  return editor.setTextInBufferRange(range, fn(text))
}

function rowCountForSelection(selection) {
  const [startRow, endRow] = selection.getBufferRowRange()
  return endRow - startRow + 1
}

module.exports = {
  isMultiLineSelection,
  rotateChars,
  rotateRows,
  insertTextAtPoint,
  insertSpacesToPoint,
  extendLastBufferRowToRow,
  ensureBufferEndWithNewLine,
  repeatArray,
  setBufferRangesForBlockwiseSelection,
  replaceRange,
  rowCountForSelection,
}
