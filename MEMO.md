## Move

Two wise. correspoinding submode of visual-mode is below
 - Linewise: linewise, characterwise(in case some selection is multi-row)
 - Characterwise: characterwise(in case all selection is single-row), blockwise

Four direction
  ['up', 'down', 'right', 'left']

Movability
 up
   - Linewise: can't move upward if row is 0
   - Characterwise: can't move upward if top selection is at row 0
 down
   - Linewise: always movable since last row is automatically extended.
   - Characterwise: always movable since last row is automatically extended.
 right
   - Linewise: always movable since EOL is automatically extended.
   - Characterwise: always movable since EOL is automatically extended.
 left
   - Linewise: always true since indent/outdent command can handle it.
   - Characterwise: can't move if start of selection is at column 0

Moving method
 up
   - Linewise: rotate linewise
   - Characterwise: swap single-row selection with upper block
 down
   - Linewise: rotate linewise
   - Characterwise: swap single-row selection with lower block
 right
   - Linewise: indent line
   - Characterwise: rotate charater in single-row selection.
 left
   - Linewise: outdent line
   - Characterwise: rotate charater in single-row selection.

## Duplicate
