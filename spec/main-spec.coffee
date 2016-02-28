{inspect} = require 'util'
p = (args...) -> console.log inspect(args...)

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/#{path}"

rowRange = (startRow, endRow) ->
  [[startRow, 0], [endRow + 1, 0]]

toggleOverwrite = (target) ->
  dispatch(target, 'vim-mode-plus-user:toggle-overwrite')

{getVimState, TextData, dispatch} = requireFrom 'vim-mode-plus', 'spec/spec-helper'

# Should cover
# Move(auto-extend EOF, cout support)
#  linewise ^,v,<,>
#  charwise ^,v,<,>

# Duplicate(auto-extend EOF, cout support)
#  linewise ^,v,<,>
#  charwise ^,v,<,>
# toggle-overwrite command
#  change css selector
#  change config value change css since observed

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

  describe "overwrite config", ->
    [vimState1, vimState2, vimState3] = []
    overwriteConfig = 'vim-mode-plus-move-selected-text.overwrite'
    overwriteClass = 'vim-mode-plus-move-selected-text-overwrite'

    beforeEach ->
      getVimState "sample1", (state, vim) -> vimState1 = state
      getVimState "sample2", (state, vim) -> vimState2 = state

    it "toggle command toggle overwrite config value", ->
      expect(atom.config.get(overwriteConfig)).toBe(false)

      dispatch(editorElement, 'vim-mode-plus-user:toggle-overwrite')
      expect(atom.config.get(overwriteConfig)).toBe(true)

      dispatch(editorElement, 'vim-mode-plus-user:toggle-overwrite')
      expect(atom.config.get(overwriteConfig)).toBe(false)

    describe "when overwrite config is toggled in false -> true -> false", ->
      it "add/remove overwrite css class to/from all editorElement including newly created editor", ->
        runs ->
          expect(atom.config.get(overwriteConfig)).toBe(false)
          for {editorElement: el} in [vimState1, vimState2]
            expect(el.classList.contains(overwriteClass)).toBe(false)

          toggleOverwrite(vimState1.editorElement)
          expect(atom.config.get(overwriteConfig)).toBe(true)
          for {editorElement: el} in [vimState1, vimState2]
            expect(el.classList.contains(overwriteClass)).toBe(true)

        getVimState "sample3", (state, vim) ->
          vimState3 = state
          el = state.editorElement
          expect(el.classList.contains(overwriteClass)).toBe(true)

        runs ->
          toggleOverwrite(vimState1.editorElement)
          expect(atom.config.get(overwriteConfig)).toBe(false)
          for {editorElement: el} in [vimState1, vimState2, vimState3]
            expect(el.classList.contains(overwriteClass)).toBe(false)

        waitsForPromise ->
          atom.packages.activatePackage('vim-mode-plus-move-selected-text')

    describe "deactivate", ->
      beforeEach ->
        getVimState "sample3", (state, vim) -> vimState3 = state

      it "remove overwrite css class from all editorElement", ->
        toggleOverwrite(vimState1.editorElement)
        els = (state.editorElement for state in [vimState1, vimState2, vimState3])
        els.push(editorElement)

        for el in els
          expect(el.classList.contains(overwriteClass)).toBe(true)

        atom.packages.deactivatePackage('vim-mode-plus-move-selected-text')
        for el in els
          expect(el.classList.contains(overwriteClass)).toBe(false)

  describe "move up/down", ->
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

    describe "characterwise", ->
      beforeEach ->
        set
          text: """
          ooo
          xxx
          YYY
          ZZZ

          """
          cursor: [[0, 1], [2, 1]]
      it "move characterwise, support multiple selection", ->
        ensure 'vl',
          mode: ['visual', 'characterwise']
          selectedTextOrdered: ['oo', 'YY']
          selectedBufferRange: [
            [[0, 1], [0, 3]]
            [[2, 1], [2, 3]]
          ]
        ensure {ctrl: 'j'},
          selectedTextOrdered: ['oo', 'YY']
          selectedBufferRange: [
            [[1, 1], [1, 3]]
            [[3, 1], [3, 3]]
          ]
          text: """
          oxx
          xoo
          YZZ
          ZYY

          """
        ensure {ctrl: 'j'},
          selectedTextOrdered: ['oo', 'YY']
          text: """
          oxx
          xZZ
          Yoo
          Z__
           YY
          """.replace(/_/g, ' ')


  describe "move left/right", ->
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

  describe "duplicate up/down", ->
    beforeEach ->
      set
        text: """
        line0
        line1
        line2

        """
        cursor: [0, 0]

    describe "linewise", ->
      it "duplicate single line", ->
        ensure 'V', selectedText: 'line0\n'
        ensure {cmd: 'J'},
          selectedBufferRange: rowRange(1, 1)
          text: 'line0\nline0\nline1\nline2\n'
      it "duplicate 2 selected line", ->
        ensure 'Vj', selectedText: 'line0\nline1\n'
        ensure {cmd: 'J'},
          selectedBufferRange: rowRange(2, 3)
          text: """
          line0
          line1
          line0
          line1
          line2

          """
        ensure {cmd: 'K'},
          selectedBufferRange: rowRange(2, 3)
          text: """
          line0
          line1
          line0
          line1
          line0
          line1
          line2

          """
      it "suport count", ->
        ensure 'V', selectedText: 'line0\n'
        ensure ['2', {cmd: 'J'}],
          selectedBufferRange: rowRange(1, 2)
          text: """
          line0
          line0
          line0
          line1
          line2

          """
        ensure ['2', {cmd: 'K'}],
          selectedBufferRange: rowRange(1, 4)
          text: """
          line0
          line0
          line0
          line0
          line0
          line0
          line0
          line1
          line2

          """

      describe "overwrite config is true", ->
        beforeEach ->
          toggleOverwrite(editorElement)
        it "overrite lines down", ->
          ensure 'V', selectedBufferRange: rowRange(0, 0)
          ensure {cmd: 'J'},
            text: """
            line0
            line0
            line2

            """
          ensure {cmd: 'J'},
            text: """
            line0
            line0
            line0

            """
            selectedBufferRange: rowRange(2, 2)
          ensure ["2", {cmd: 'J'}],
            text: """
            line0
            line0
            line0
            line0
            line0

            """
            selectedBufferRange: rowRange(3, 4)

        it "overrite lines up", ->
          ensure 'jjV', selectedBufferRange: rowRange(2, 2)
          ensure ["2", {cmd: 'K'}],
            selectedBufferRange: rowRange(0, 1)
            text: """
            line2
            line2
            line2

            """
        it "adjust count when duplicate up to stop overwrite when no enough height is available", ->
          set
            text: """
            0
            1
            2
            3
            4

            """
            cursor: [3, 0]

          ensure 'Vj', selectedBufferRange: rowRange(3, 4)
          ensure ["10", {cmd: 'K'}],
            selectedBufferRange: rowRange(1, 2)
            text: """
            0
            3
            4
            3
            4

            """

  describe "duplicate right/left", ->
    originalText = null
    describe "linewise", ->
      beforeEach ->
        originalText = """
        0 |_
        1 midle |_
        2 very long |_

        """
        set
          text: originalText
          cursor: [0, 0]

      it "duplicate linewise right", ->
        keystroke 'Vjj'
        ensure {cmd: 'L'},
          selectedBufferRange: rowRange(0, 2)
          text: """
          0 |_0 |_
          1 midle |_1 midle |_
          2 very long |_2 very long |_

          """
      it "count support", ->
        keystroke 'Vjj'
        ensure ['2', {cmd: 'L'}],
          selectedBufferRange: rowRange(0, 2)
          text: """
          0 |_0 |_0 |_
          1 midle |_1 midle |_1 midle |_
          2 very long |_2 very long |_2 very long |_

          """
      describe "overwrite config is true", ->
        beforeEach ->
          toggleOverwrite(editorElement)

        it "duplicate linewise right(no behavior diff)", ->
          keystroke 'Vjj'
          ensure {cmd: 'L'},
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "duplicate linewise left do nothing", ->
          keystroke 'Vjj'
          ensure {cmd: 'H'},
            selectedBufferRange: rowRange(0, 2)
            text: originalText

      it "duplicate linewise left(identical behavior to right)", ->
        keystroke 'Vjj'
        ensure {cmd: 'H'},
          selectedBufferRange: rowRange(0, 2)
          text: """
          0 |_0 |_
          1 midle |_1 midle |_
          2 very long |_2 very long |_

          """
