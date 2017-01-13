{inspect} = require 'util'

requireFrom = (pack, path) ->
  packPath = atom.packages.resolvePackagePath(pack)
  require "#{packPath}/#{path}"

rowRange = (startRow, endRow) ->
  [[startRow, 0], [endRow + 1, 0]]

toggleOverwrite = (target) ->
  dispatch(target, 'vim-mode-plus-user:move-selected-text-toggle-overwrite')

getOverwriteConfig = ->
  atom.config.get('vim-mode-plus-move-selected-text.overwrite')

setOverwriteConfig = (value) ->
  atom.config.set('vim-mode-plus-move-selected-text.overwrite', value)

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

  ensureOverwriteClass = (target, bool) ->
    className = 'vim-mode-plus-move-selected-text-overwrite'
    expect(target.classList.contains(className)).toBe(bool)

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
    [vimState1, vimState2, vimState3, vimState4, allVimState] = []
    ensureOverwriteClassForVimStates = (vimStates, bool) ->
      for _vimState in vimStates
        ensureOverwriteClass(_vimState.editorElement, bool)

    ensureOverwriteClassInSyncForVimStates = (vimStates) ->
      ensureOverwriteClassForVimStates(vimStates, getOverwriteConfig())

    beforeEach ->
      getVimState "sample1", (state, vim) -> vimState1 = state
      getVimState "sample2", (state, vim) -> vimState2 = state

      runs ->
        allVimState = []
        allVimState.push(vimState1, vimState2)

    describe "basic behavior of 'move-selected-text-toggle-overwrite'", ->
      it "toggle command toggle 'overwrite' config value", ->
        expect(getOverwriteConfig()).toBe(false)
        toggleOverwrite(editorElement)
        expect(getOverwriteConfig()).toBe(true)

        toggleOverwrite(editorElement)
        expect(getOverwriteConfig()).toBe(false)

    describe "when overwrite config is toggled in false -> true -> false", ->
      it "add/remove overwrite css class to/from all editorElement including newly created editor", ->
        runs ->
          expect(getOverwriteConfig()).toBe(false)
          ensureOverwriteClassInSyncForVimStates(allVimState)

          toggleOverwrite(vimState1.editorElement)
          expect(getOverwriteConfig()).toBe(true)
          ensureOverwriteClassInSyncForVimStates(allVimState)

        getVimState "sample3", (state, vim) -> allVimState.push(state)

        runs ->
          expect(allVimState).toHaveLength(3)
          ensureOverwriteClassInSyncForVimStates(allVimState)

          toggleOverwrite(vimState1.editorElement)
          expect(getOverwriteConfig()).toBe(false)
          ensureOverwriteClassInSyncForVimStates(allVimState)

        getVimState "sample4", (state, vim) -> allVimState.push(state)

        runs ->
          expect(allVimState).toHaveLength(4)
          ensureOverwriteClassInSyncForVimStates(allVimState)
          toggleOverwrite(vimState1.editorElement)
          expect(getOverwriteConfig()).toBe(true)
          ensureOverwriteClassInSyncForVimStates(allVimState)

    describe "when deactivate", ->
      beforeEach ->
        getVimState "sample3", (state, vim) -> vimState3 = state

        runs ->
          allVimState.push(vimState3)

      it "remove overwrite css class from all editorElement", ->
        toggleOverwrite(vimState1.editorElement)
        expect(allVimState).toHaveLength(3)
        ensureOverwriteClassForVimStates(allVimState, true)
        atom.packages.deactivatePackage('vim-mode-plus-move-selected-text')
        ensureOverwriteClassForVimStates(allVimState, false)

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
      describe "overwrite: false", ->
        lines = (lines...) -> text.getLines(lines)
        getEnsurerForLinewiseMove = (textData, {selectedText, selectionIsReversed}) ->
          (keystroke, {rows, text}) ->
            if (not text?) and rows?
              text = textData.getLines(rows)
            ensure keystroke, {text, selectedText, selectionIsReversed}

        it "[case-1] one line", ->
          ensureLinewiseMove = getEnsurerForLinewiseMove textData,
            selectedText: "line0\n", selectionIsReversed: false
          ensureLinewiseMove 'V', rows: [0, 1, 2]
          ensureLinewiseMove 'ctrl-j', rows: [1, 0, 2]
          ensureLinewiseMove 'ctrl-j', rows: [1, 2, 0]
          ensureLinewiseMove 'ctrl-k', rows: [1, 0, 2]
          ensureLinewiseMove 'ctrl-k', rows: [0, 1, 2]
        it "[case-2] two line", ->
          ensureLinewiseMove = getEnsurerForLinewiseMove textData,
            selectedText: "line0\nline1\n", selectionIsReversed: false
          ensureLinewiseMove 'V j', rows: [0, 1, 2]
          ensureLinewiseMove 'ctrl-j', rows: [2, 0, 1]
          ensureLinewiseMove 'ctrl-k', rows: [0, 1, 2]
        it "[case-3] two line, selection is reversed: keep reversed state", ->
          ensureLinewiseMove = getEnsurerForLinewiseMove textData,
            selectedText: "line0\nline1\n", selectionIsReversed: true
          set cursor: [1, 0]
          ensureLinewiseMove 'V k', rows: [0, 1, 2]
          ensureLinewiseMove 'ctrl-j', rows: [2, 0, 1]
          ensureLinewiseMove 'ctrl-k', rows: [0, 1, 2]
        it "extends final row when move down", ->
          ensureLinewiseMove = getEnsurerForLinewiseMove textData,
            selectedText: "line2\n", selectionIsReversed: false
          set cursor: [2, 0]
          ensureLinewiseMove 'V', rows: [0, 1, 2]
          ensureLinewiseMove 'ctrl-j', text: [
            "line0"
            "line1"
            ""
            "line2"
            ""
          ].join("\n")
          ensureLinewiseMove 'ctrl-j', text: [
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
          ensureLinewiseMove 'V', rows: [0, 1, 2]
          ensureLinewiseMove '2 ctrl-j', rows: [1, 2, 0]
          ensureLinewiseMove '2 ctrl-k', rows: [0, 1, 2]
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

    describe "characterwise", ->
      describe "overwrite: false", ->
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
          ensure 'v l',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            selectedBufferRange: [
              [[0, 1], [0, 3]]
              [[2, 1], [2, 3]]
            ]
          ensure 'ctrl-j',
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
          ensure 'ctrl-j',
            selectedTextOrdered: ['oo', 'YY']
            text: """
            oxx
            xZZ
            Yoo
            Z__
             YY
            """.replace(/_/g, ' ')
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

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

      describe "overwrite: false", ->
        it "indent/outdent", ->
          selectedText = "line0\nline1\n"
          ensure "V j", {selectedText, selectionIsReversed: false}
          ensure 'ctrl-l',
            selectedText: "  line0\n  line1\n"
            selectionIsReversed: false

          ensure '2 ctrl-l',
            selectedText: "      line0\n      line1\n"
            selectionIsReversed: false

          ensure '2 ctrl-h',
            selectedText: "  line0\n  line1\n"
            selectionIsReversed: false

          ensure 'ctrl-h',
            selectedText: "line0\nline1\n"
            selectionIsReversed: false

        it "[case-2] indent/outdent", ->
          text = """
            line0
              line1
                line2
            line3

            """
          set {text}
          ensure "V 3 j", selectedText: text
          newText = """
            line0
            line1
            line2
            line3

            """
          ensure '1 0 ctrl-h', text: newText, selectedText: newText
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

    # TODO
    describe "characterwise", ->
      describe "overwrite: false", ->
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

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
      describe "overwrite: false", ->
        it "duplicate single line", ->
          ensure 'V', selectedText: 'line0\n'
          ensure 'cmd-J',
            selectedBufferRange: rowRange(1, 1)
            text: 'line0\nline0\nline1\nline2\n'
        it "duplicate 2 selected line", ->
          ensure 'V j', selectedText: 'line0\nline1\n'
          ensure 'cmd-J',
            selectedBufferRange: rowRange(2, 3)
            text: """
            line0
            line1
            line0
            line1
            line2

            """
          ensure 'cmd-K',
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
          ensure '2 cmd-J',
            selectedBufferRange: rowRange(1, 2)
            text: """
            line0
            line0
            line0
            line1
            line2

            """
          ensure '2 cmd-K',
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
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

        it "overrite lines down", ->
          ensure 'V', selectedBufferRange: rowRange(0, 0)
          ensure 'cmd-J',
            text: """
            line0
            line0
            line2

            """
          ensure 'cmd-J',
            text: """
            line0
            line0
            line0

            """
            selectedBufferRange: rowRange(2, 2)
          ensure '2 cmd-J',
            text: """
            line0
            line0
            line0
            line0
            line0

            """
            selectedBufferRange: rowRange(3, 4)

        it "overrite lines up", ->
          ensure 'j j V', selectedBufferRange: rowRange(2, 2)
          ensure '2 cmd-K',
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

          ensure 'V j', selectedBufferRange: rowRange(3, 4)
          ensure '1 0 cmd-K',
            selectedBufferRange: rowRange(1, 2)
            text: """
            0
            3
            4
            3
            4

            """

    # TODO
    describe "characterwise", ->
      describe "overwrite: false", ->
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

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

      describe "overwrite: false", ->
        it "duplicate linewise right", ->
          ensure 'V j j cmd-L',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "count support", ->
          ensure 'V j j 2 cmd-L',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_0 |_
            1 midle |_1 midle |_1 midle |_
            2 very long |_2 very long |_2 very long |_

            """

        it "???duplicate linewise left(identical behavior to right)", ->
          ensure 'V j j cmd-H',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

        it "duplicate linewise right(no behavior diff)", ->
          ensure 'V j j cmd-L',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "duplicate linewise left do nothing", ->
          ensure 'V j j cmd-H',
            selectedBufferRange: rowRange(0, 2)
            text: originalText

    # TODO
    describe "characterwise", ->
      describe "overwrite: false", ->
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)
