# vim-mode-plus-move-selected-text

Move selected text like object.  


This is operator plugin for [vim-mode-plus](https://atom.io/packages/vim-mode-plus).  
Require [vim-mode-plus](https://atom.io/packages/vim-mode-plus) v0.19.1 or later.  

- Works only in visual mode.  
- Support all submode(linewise, characterwise, blockwise).
- Can revert consecutive movement with single undo.
- Can switch `overwrite` mode via `vim-mode-plus-user:toggle-overwrite` command.  
- Green cursor color indicate your are now in `overwrite` mode.

This package is feature migration from my [vim-textmanip](https://github.com/t9md/vim-textmanip) plugin for pure Vim.  

![](https://raw.githubusercontent.com/t9md/t9md/842444a1482afe4bb789dd602c6be9ba40f71073/img/vim-mode-plus/move-selected-text.gif)

## TODO

- [ ] Write spec
- [ ] Work as screenPosition wise for characterwise move to support soft-wrapped buffer.
- [ ] Duplicate above/below with overwrite mode support
- [x] blockwise support
- [x] Support count
- [x] Concatenate undo history to revert continuous movement with one undo
- [x] Support overwrite movement

## keymap example

No keymap by default.  
Set following keymap to in your `keymap.cson`.  

```coffeescipt
'atom-text-editor.vim-mode-plus.visual-mode':
  'ctrl-k': 'vim-mode-plus-user:move-selected-text-up'
  'ctrl-j': 'vim-mode-plus-user:move-selected-text-down'
  'ctrl-l': 'vim-mode-plus-user:move-selected-text-right'
  'ctrl-h': 'vim-mode-plus-user:move-selected-text-left'
  'ctrl-t': 'vim-mode-plus-user:toggle-overwrite'
```
