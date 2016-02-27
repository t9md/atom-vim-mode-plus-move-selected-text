{inspect} = require 'util'
p = (args...) -> console.log inspect(args...)

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/#{path}"

{getVimState, TextData} = requireFrom 'vim-mode-plus', 'spec/spec-helper'

describe "vim-mode-plus-move-selected-text", ->
  [set, ensure, keystroke, editor, editorElement, vimState] = []

  beforeEach ->
    getVimState (state, vim) ->
      vimState = state
      {editor, editorElement} = state
      {set, ensure, keystroke} = vim

    atom.keymaps.add "test",
      'atom-text-editor.vim-mode-plus.visual-mode':
        'ctrl-t': 'vim-mode-plus-user:toggle-overwrite'
        'ctrl-k': 'vim-mode-plus-user:move-selected-text-up'
        'ctrl-j': 'vim-mode-plus-user:move-selected-text-down'
        'ctrl-h': 'vim-mode-plus-user:move-selected-text-left'
        'ctrl-l': 'vim-mode-plus-user:move-selected-text-right'

        'cmd-K': 'vim-mode-plus-user:duplicate-selected-text-up'
        'cmd-J': 'vim-mode-plus-user:duplicate-selected-text-down'
        'cmd-H': 'vim-mode-plus-user:duplicate-selected-text-left'
        'cmd-L': 'vim-mode-plus-user:duplicate-selected-text-right'

    waitsForPromise ->
      atom.packages.activatePackage('vim-mode-plus-move-selected-text')

  describe "move-selected-text-up/down", ->
    textData = null
    beforeEach ->
      textData = new TextData """
        line0
        line1
        line2

        """
      set
        text: textData.getRaw()
        cursor: [0, 0]

    describe "linewise", ->
      lines = (lines...) -> text.getLines(lines)
      getEnsurerForLinewiseMove = (textData, {selectedText, selectionIsReversed}) ->
        (keystroke, {rows, text}) ->
          if (not text?) and rows?
            text = textData.getLines(rows)
          ensure keystroke, {text, selectedText, selectionIsReversed}

      it "[case-1] one line", ->
        ensureLinewiseMove = getEnsurerForLinewiseMove textData,
          selectedText: "line0\n", selectionIsReversed: false
        ensureLinewiseMove 'V',         rows: [0, 1, 2]
        ensureLinewiseMove {ctrl: 'j'}, rows: [1, 0, 2]
        ensureLinewiseMove {ctrl: 'j'}, rows: [1, 2, 0]
        ensureLinewiseMove {ctrl: 'k'}, rows: [1, 0, 2]
        ensureLinewiseMove {ctrl: 'k'}, rows: [0, 1, 2]
      it "[case-2] two line", ->
        ensureLinewiseMove = getEnsurerForLinewiseMove textData,
          selectedText: "line0\nline1\n", selectionIsReversed: false
        ensureLinewiseMove 'Vj',        rows: [0, 1, 2]
        ensureLinewiseMove {ctrl: 'j'}, rows: [2, 0, 1]
        ensureLinewiseMove {ctrl: 'k'}, rows: [0, 1, 2]
      it "[case-3] two line, selection is reversed: keep reversed state", ->
        ensureLinewiseMove = getEnsurerForLinewiseMove textData,
          selectedText: "line0\nline1\n", selectionIsReversed: true
        set cursor: [1, 0]
        ensureLinewiseMove 'Vk',        rows: [0, 1, 2]
        ensureLinewiseMove {ctrl: 'j'}, rows: [2, 0, 1]
        ensureLinewiseMove {ctrl: 'k'}, rows: [0, 1, 2]
      it "extends final row when move down", ->
        ensureLinewiseMove = getEnsurerForLinewiseMove textData,
          selectedText: "line2\n", selectionIsReversed: false
        set cursor: [2, 0]
        ensureLinewiseMove 'V', rows: [0, 1, 2]
        ensureLinewiseMove {ctrl: 'j'}, text: [
          "line0"
          "line1"
          ""
          "line2"
          ""
        ].join("\n")
        ensureLinewiseMove {ctrl: 'j'}, text: [
          "line0"
          "line1"
          ""
          ""
          "line2"
          ""
        ].join("\n")
      it "support count", ->
        ensureLinewiseMove = getEnsurerForLinewiseMove textData,
          selectedText: "line0\n", selectionIsReversed: false
        ensureLinewiseMove 'V',         rows: [0, 1, 2]
        ensureLinewiseMove ["2", {ctrl: 'j'}], rows: [1, 2, 0]
        ensureLinewiseMove ["2", {ctrl: 'k'}], rows: [0, 1, 2]
  describe "move-selected-text-left/right", ->
    textData = null
    describe "linewise", ->
      beforeEach ->
        textData = new TextData """
          line0
          line1
          line2

          """
        set
          text: textData.getRaw()
          cursor: [0, 0]

      it "indent/outdent", ->
        selectedText = "line0\nline1\n"
        selectionIsReversed = false
        ensure "Vj", {selectedText, selectionIsReversed}
        ensure {ctrl: 'l'}, {
          selectedText: "  line0\n  line1\n"
          selectionIsReversed
        }
        ensure ["2", {ctrl: 'l'}], {
          selectedText: "      line0\n      line1\n"
          selectionIsReversed
        }
        ensure ["2", {ctrl: 'h'}], {
          selectedText: "  line0\n  line1\n"
          selectionIsReversed
        }
        ensure {ctrl: 'h'}, {
          selectedText: "line0\nline1\n"
          selectionIsReversed
        }
      it "[case-2] indent/outdent", ->
        text = """
          line0
            line1
              line2
          line3

          """
        set {text}
        ensure "V3j", selectedText: text
        newText = """
          line0
          line1
          line2
          line3

          """
        ensure ['10', {ctrl: 'h'}], {text: newText, selectedText: newText}
