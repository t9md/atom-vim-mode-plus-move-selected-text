[![Build Status](https://travis-ci.org/t9md/atom-vim-mode-plus-move-selected-text.svg?branch=master)](https://travis-ci.org/t9md/atom-vim-mode-plus-move-selected-text)

# vim-mode-plus-move-selected-text

Move selected text like object.  

This is operator plugin for [vim-mode-plus](https://atom.io/packages/vim-mode-plus).  
Require **latest** [vim-mode-plus](https://atom.io/packages/vim-mode-plus).

- Works only in visual mode.  
- Support all submode(`linewise`, `characterwise`, `blockwise`).
- Can revert consecutive movement by single undo.
- Can switch `overwrite` mode via `vim-mode-plus-user:toggle-overwrite` command.  
- Green cursor color indicate your are now in `overwrite` mode.

This package is feature migration from my [vim-textmanip](https://github.com/t9md/vim-textmanip) plugin for pure Vim.  

![](https://raw.githubusercontent.com/t9md/t9md/d44c35f193478c0ccf996d0b3085d276fe9ea4b9/img/vim-mode-plus/move-selected-text.gif)

## keymap example

No keymap by default.  
Set following keymap to in your `keymap.cson`.  

```coffeescipt
'atom-text-editor.vim-mode-plus.visual-mode':
  'ctrl-t': 'vim-mode-plus-user:move-selected-text-toggle-overwrite'

  'ctrl-k': 'vim-mode-plus-user:move-selected-text-up'
  'ctrl-j': 'vim-mode-plus-user:move-selected-text-down'
  'ctrl-h': 'vim-mode-plus-user:move-selected-text-left'
  'ctrl-l': 'vim-mode-plus-user:move-selected-text-right'

  'cmd-K': 'vim-mode-plus-user:duplicate-selected-text-up'
  'cmd-J': 'vim-mode-plus-user:duplicate-selected-text-down'
  'cmd-H': 'vim-mode-plus-user:duplicate-selected-text-left'
  'cmd-L': 'vim-mode-plus-user:duplicate-selected-text-right'
```
