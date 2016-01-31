# vim-mode-plus-move-selected-text

This is operator plugin for [vim-mode-plus](https://atom.io/packages/vim-mode-plus).  

Move selected text like object.  
Works only in visual mode.  
Support all submode(linewise, characterwise, blockwise).
You can switch `overwrite` mode via `vim-mode-plus-user:toggle-move-method` command.  

This package is feature migration from my [vim-textmanip](https://github.com/t9md/vim-textmanip) plugin for pure Vim.  

![](https://raw.githubusercontent.com/t9md/t9md/1df78bf22bc94440cd47e381dc6c6c6ad1c2db33/img/vim-mode-plus/move-selected-text.gif)

## TODO

- [ ] Write spec
- [ ] Work as screenPosition wise for characterwise move.
- [ ] Performance improvement
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
