_ = require 'underscore-plus'
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

  getEnsureWithOptions = (optionsBase) ->
    (keystroke, options) ->
      ensure(keystroke, _.defaults(_.clone(options), optionsBase))

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
    describe "linewise", ->
      describe "overwrite: false", ->
        beforeEach ->
          set textC: "|line0\nline1\nline2\n"

        it "[case-1] one line", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\n", selectionIsReversed: false)
          ensureMove 'V', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "line1\nline0\nline2\n" # down
          ensureMove 'ctrl-j', text: "line1\nline2\nline0\n" # down
          ensureMove 'ctrl-k', text: "line1\nline0\nline2\n" # up
          ensureMove 'ctrl-k', text: "line0\nline1\nline2\n" # up
        it "[case-2] two line", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "line2\nline0\nline1\n"
          ensureMove 'ctrl-k', text: "line0\nline1\nline2\n"
        it "[case-3] two line, selection is reversed: keep reversed state", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: true)
          set cursor: [1, 0]
          ensureMove 'V k', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "line2\nline0\nline1\n"
          ensureMove 'ctrl-k', text: "line0\nline1\nline2\n"
        it "extends final row when move down", ->
          ensureMove = getEnsureWithOptions(selectedText: "line2\n", selectionIsReversed: false)
          set cursor: [2, 0]
          ensureMove 'V', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "line0\nline1\n\nline2\n"
          ensureMove 'ctrl-j', text: "line0\nline1\n\n\nline2\n"
        it "support count", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove '2 ctrl-j', text: "line2\n\nline0\nline1\n"
          ensureMove '2 ctrl-k', text: "line0\nline1\nline2\n\n"
          ensureMove '1 0 ctrl-j', text: "line2\n\n\n\n\n\n\n\n\n\nline0\nline1\n"
          ensureMove '5 ctrl-k', text: "line2\n\n\n\n\nline0\nline1\n\n\n\n\n\n"

      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)
          set textC: """
          |line0
          line1
          line2\n
          """

        it "[case-1] one line", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\n", selectionIsReversed: false)
          ensureMove 'V', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "\nline0\nline2\n"
          ensureMove 'ctrl-j', text: "\nline1\nline0\n"
          ensureMove 'ctrl-k', text: "\nline0\nline2\n"
          ensureMove 'ctrl-k', text: "line0\nline1\nline2\n"
        it "[case-2] two line", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "\nline0\nline1\n"
          ensureMove 'ctrl-k', text: "line0\nline1\nline2\n"
        it "[case-3] two line, selection is reversed: keep reversed state", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: true)
          set cursor: [1, 0]
          ensureMove 'V k', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "\nline0\nline1\n"
          ensureMove 'ctrl-k', text: "line0\nline1\nline2\n"
        it "extends final row when move down", ->
          ensureMove = getEnsureWithOptions(selectedText: "line2\n", selectionIsReversed: false)
          set cursor: [2, 0]
          ensureMove 'V', text: "line0\nline1\nline2\n"
          ensureMove 'ctrl-j', text: "line0\nline1\n\nline2\n"
          ensureMove 'ctrl-j', text: "line0\nline1\n\n\nline2\n"
        it "support count", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove '2 ctrl-j', text: "\n\nline0\nline1\n"
          ensureMove '2 ctrl-j', text: "\n\nline2\n\nline0\nline1\n"
          ensureMove '1 0 ctrl-j', text: "\n\nline2\n\n\n\n\n\n\n\n\n\n\n\nline0\nline1\n"
          ensureMove '5 ctrl-k', text: "\n\nline2\n\n\n\n\n\n\nline0\nline1\n\n\n\n\n\n"

    describe "characterwise", ->
      describe "overwrite: false", ->
        beforeEach ->
          set
            textC: """
            o|oo
            xxx
            Y|YY
            ZZZ\n
            """

        it "move characterwise, support multiple selection", ->
          ensureMove = getEnsureWithOptions(mode: ['visual', 'characterwise'], selectedTextOrdered: ['oo', 'YY'])
          ensureMove 'v l',
            text: """
            ooo
            xxx
            YYY
            ZZZ\n
            """
          ensureMove 'ctrl-j',
            text: """
            oxx
            xoo
            YZZ
            ZYY\n
            """
          ensureMove 'ctrl-j',
            text_: """
            oxx
            xZZ
            Yoo
            Z__
            _YY
            """
          ensureMove '2 ctrl-j',
            text_: """
            oxx
            xZZ
            Y__
            Z__
            _oo
            ___
            _YY
            """
          ensureMove '4 ctrl-k',
            text_: """
            ooo
            xxx
            YYY
            ZZZ
            ___
            ___
            ___
            """

      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)
          set
            textC: """
            o|oo
            xxx
            Y|YY
            ZZZ\n
            """

        it "move characterwise, support multiple selection", ->
          ensureMove = getEnsureWithOptions(mode: ['visual', 'characterwise'], selectedTextOrdered: ['oo', 'YY'])
          ensureMove 'v l',
            text_: """
            ooo
            xxx
            YYY
            ZZZ\n
            """
          ensureMove 'ctrl-j',
            text_: """
            o__
            xoo
            Y__
            ZYY\n
            """
          ensureMove 'ctrl-j',
            text_: """
            o__
            xxx
            Yoo
            ZZZ
            _YY
            """
          ensureMove '2 ctrl-j',
            text_: """
            o__
            xxx
            Y__
            ZZZ
            _oo
            ___
            _YY
            """
          ensureMove '4 ctrl-k',
            text_: """
            ooo
            xxx
            YYY
            ZZZ
            ___
            ___
            ___
            """

  describe "move left/right", ->
    textData = null
    describe "linewise", ->
      beforeEach ->
        set
          text_: """
          line0
          __line1
          ____line2
          line3\n
          """
          cursor: [0, 0]

      describe "overwrite: false", ->
        it "indent/outdent, count support", ->
          ensureMove = getEnsureWithOptions(selectionIsReversed: false)
          ensureMove "V j",
            text_: "line0\n__line1\n____line2\nline3\n"
            selectedText_: "line0\n__line1\n"
          ensureMove 'ctrl-l',
            text_: "__line0\n____line1\n____line2\nline3\n"
            selectedText_: "__line0\n____line1\n"
          ensureMove '2 ctrl-l',
            text_: "______line0\n________line1\n____line2\nline3\n"
            selectedText_: "______line0\n________line1\n"
          ensureMove 'ctrl-h',
            text_: "____line0\n______line1\n____line2\nline3\n"
            selectedText_: "____line0\n______line1\n"
          ensureMove '1 0 0 ctrl-h',
            text_: "line0\nline1\n____line2\nline3\n"
            selectedText_: "line0\nline1\n"

      describe "overwrite: true", ->
        # No behavior-diff by overrite setting.
        # So test below is identical with "override: false"
        beforeEach ->
          setOverwriteConfig(true)

        it "indent/outdent, count support", ->
          ensureMove = getEnsureWithOptions(selectionIsReversed: false)
          ensureMove "V j",
            text_: "line0\n__line1\n____line2\nline3\n"
            selectedText_: "line0\n__line1\n"
          ensureMove 'ctrl-l',
            text_: "__line0\n____line1\n____line2\nline3\n"
            selectedText_: "__line0\n____line1\n"
          ensureMove '2 ctrl-l',
            text_: "______line0\n________line1\n____line2\nline3\n"
            selectedText_: "______line0\n________line1\n"
          ensureMove 'ctrl-h',
            text_: "____line0\n______line1\n____line2\nline3\n"
            selectedText_: "____line0\n______line1\n"
          ensureMove '1 0 0 ctrl-h',
            text_: "line0\nline1\n____line2\nline3\n"
            selectedText_: "line0\nline1\n"

    describe "characterwise", ->
      describe "overwrite: false", ->
        beforeEach ->
          set
            textC: """
            oxYZ@
            o|xYZ@
            o|xYZ@
            oxYZ@
            """
        it "move right/left count support", ->
          ensureMove = getEnsureWithOptions(mode: ['visual', 'characterwise'], selectedTextOrdered: ['xY', 'xY'])
          ensureMove 'v l',
            text: """
            oxYZ@
            oxYZ@
            oxYZ@
            oxYZ@
            """
          ensureMove 'ctrl-l',
            text: """
            oxYZ@
            oZxY@
            oZxY@
            oxYZ@
            """
          ensureMove 'ctrl-l',
            text: """
            oxYZ@
            oZ@xY
            oZ@xY
            oxYZ@
            """
          ensureMove 'ctrl-l',
            text_: """
            oxYZ@
            oZ@_xY
            oZ@_xY
            oxYZ@
            """
          ensureMove '5 ctrl-l',
            text_: """
            oxYZ@
            oZ@______xY
            oZ@______xY
            oxYZ@
            """
          ensureMove '3 ctrl-h',
            text_: """
            oxYZ@
            oZ@___xY___
            oZ@___xY___
            oxYZ@
            """
          ensureMove '1 0 0 ctrl-h',
            text_: """
            oxYZ@
            xYoZ@______
            xYoZ@______
            oxYZ@
            """

      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)
          set
            textC: """
            oxYZ@
            o|xYZ@
            o|xYZ@
            oxYZ@
            """
        it "move right/left count support", ->
          ensureMove = getEnsureWithOptions(mode: ['visual', 'characterwise'], selectedTextOrdered: ['xY', 'xY'])
          ensureMove 'v l',
            text: """
            oxYZ@
            oxYZ@
            oxYZ@
            oxYZ@
            """
          ensureMove 'ctrl-l',
            text_: """
            oxYZ@
            o_xY@
            o_xY@
            oxYZ@
            """
          ensureMove 'ctrl-l',
            text_: """
            oxYZ@
            o__xY
            o__xY
            oxYZ@
            """
          ensureMove 'ctrl-l',
            text_: """
            oxYZ@
            o__ZxY
            o__ZxY
            oxYZ@
            """
          ensureMove '5 ctrl-l',
            text_: """
            oxYZ@
            o__Z@____xY
            o__Z@____xY
            oxYZ@
            """
          ensureMove '3 ctrl-h',
            text_: """
            oxYZ@
            o__Z@_xY___
            o__Z@_xY___
            oxYZ@
            """
          ensureMove '1 0 0 ctrl-h',
            text_: """
            oxYZ@
            xY_Z@______
            xY_Z@______
            oxYZ@
            """

  xdescribe "duplicate up/down", ->
    beforeEach ->
      set
        textC: """
        |line0
        line1
        line2

        """

    describe "linewise", ->
      describe "overwrite: false", ->
        it "duplicate single line", ->
          ensure 'V',
            selectedBufferRange: rowRange(0, 0)
          ensure 'cmd-J',
            selectedBufferRange: rowRange(1, 1)
            text: 'line0\nline0\nline1\nline2\n'

        it "duplicate 2 selected line", ->
          ensure 'V j',
            selectedBufferRange: rowRange(0, 1)
          ensure 'cmd-J',
            selectedBufferRange: rowRange(2, 3)
            text: "line0\nline1\nline0\nline1\nline2\n"
          ensure 'cmd-K',
            selectedBufferRange: rowRange(2, 3)
            text: "line0\nline1\nline0\nline1\nline0\nline1\nline2\n"
        it "suport count", ->
          ensure 'V',
            selectedBufferRange: rowRange(0, 0)
          ensure '2 cmd-J',
            selectedBufferRange: rowRange(1, 2)
            text: "line0\nline0\nline0\nline1\nline2\n"
          ensure '2 cmd-K',
            selectedBufferRange: rowRange(1, 4)
            text: "line0\nline0\nline0\nline0\nline0\nline0\nline0\nline1\nline2\n"
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

        it "overrite lines down", ->
          ensure 'V',
            selectedBufferRange: rowRange(0, 0)
          ensure 'cmd-J',
            text: "line0\nline0\nline2\n"
          ensure 'cmd-J',
            text: "line0\nline0\nline0\n"
            selectedBufferRange: rowRange(2, 2)
          ensure '2 cmd-J',
            text: "line0\nline0\nline0\nline0\nline0\n"
            selectedBufferRange: rowRange(3, 4)

        it "overrite lines up", ->
          ensure 'j j V',
            selectedBufferRange: rowRange(2, 2)
          ensure '2 cmd-K',
            selectedBufferRange: rowRange(0, 1)
            text: "line2\nline2\nline2\n"
        it "adjust count when duplicate up to stop overwrite when no enough height is available", ->
          set
            textC: """
            0
            1
            2
            |3
            4\n
            """
          ensure 'V j',
            selectedBufferRange: rowRange(3, 4)
          ensure '1 0 cmd-K',
            selectedBufferRange: rowRange(1, 2)
            text: """
            0
            3
            4
            3
            4\n
            """

    describe "characterwise", ->
      describe "overwrite: false", ->
        beforeEach ->
          set
            textC: """
            o|ooo
            xxxx
            Y|YYY
            ZZZZ\n
            """
        it "duplicate charwise down", ->
          ensure 'v l',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text: """
            oooo
            xxxx
            YYYY
            ZZZZ\n
            """
          ensure 'cmd-K',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text_: """
            _oo
            oooo
            xxxx
            _YY
            YYYY
            ZZZZ\n
            """
            selectedBufferRange: [
              [[0, 1], [0, 3]]
              [[3, 1], [3, 3]]
            ]
          ensure '2 cmd-K',
            mode: ['visual', 'blockwise']
            selectedTextOrdered: ['oo', 'oo', 'YY', 'YY']
            text_: """
            _oo
            _oo
            _oo
            oooo
            xxxx
            _YY
            _YY
            _YY
            YYYY
            ZZZZ\n
            """
            selectedBufferRangeOrdered: [
              [[0, 1], [0, 3]]
              [[1, 1], [1, 3]]
              [[5, 1], [5, 3]]
              [[6, 1], [6, 3]]
            ]

        it "duplicate charwise down", ->
          ensure 'v l',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text_: """
            oooo
            xxxx
            YYYY
            ZZZZ\n
            """
          ensure 'cmd-J',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text_: """
            oooo
            _oo
            xxxx
            YYYY
            _YY
            ZZZZ\n
            """
            selectedBufferRangeOrdered: [
              [[1, 1], [1, 3]]
              [[4, 1], [4, 3]]
            ]
          ensure '2 cmd-J',
            mode: ['visual', 'blockwise']
            selectedTextOrdered: ['oo', 'oo', 'YY', 'YY']
            text_: """
            oooo
            _oo
            _oo
            _oo
            xxxx
            YYYY
            _YY
            _YY
            _YY
            ZZZZ\n
            """
            selectedBufferRangeOrdered: [
              [[2, 1], [2, 3]]
              [[3, 1], [3, 3]]
              [[7, 1], [7, 3]]
              [[8, 1], [8, 3]]
            ]

      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)
          set
            textC: """
            o|ooo
            xxxx
            Y|YYY
            ZZZZ\n
            """

        it "duplicate charwise down", ->
          ensure 'v l',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text: """
            oooo
            xxxx
            YYYY
            ZZZZ\n
            """
          ensure 'cmd-J',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text: """
            oooo
            xoox
            YYYY
            ZYYZ\n
            """
          ensure '2 cmd-J',
            mode: ['visual', 'blockwise']
            selectedTextOrdered: ['oo', 'oo', 'YY', 'YY']
            text: """
            oooo
            xoox
            YooY
            ZooZ
             YY
             YY
            """
        it "duplicate charwise up", ->
          set
            cursor: [
              [2, 1]
              [3, 1]
            ]
          ensure 'v l',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['YY', 'ZZ']
            text: """
            oooo
            xxxx
            YYYY
            ZZZZ\n
            """
          ensure 'cmd-K',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['YY', 'ZZ']
            text: """
            oooo
            xYYx
            YZZY
            ZZZZ\n
            """
            selectedBufferRangeOrdered: [
              [[1, 1], [1, 3]]
              [[2, 1], [2, 3]]
            ]
        xit "duplicate charwise up", ->
          set
            textC: """
            o|ooo
            xxxx
            YYYY
            ZZZZ\n
            """
          ensure 'v l cmd-K',
            mode: ['visual', 'characterwise']

  xdescribe "duplicate right/left", ->
    describe "linewise", ->
      originalText = null
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

        it "duplicate linewise left(identical behavior to right)", ->
          ensure 'V j j cmd-H',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "duplicate linewise left with count(identical behavior to right)", ->
          ensure 'V j j 2 cmd-H',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_0 |_
            1 midle |_1 midle |_1 midle |_
            2 very long |_2 very long |_2 very long |_

            """
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

        it "duplicate linewise right(no behavior diff with overwrite=false)", ->
          ensure 'V j j cmd-L',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "duplicate linewise right(no behavior diff with overwrite=false)", ->
          ensure 'V j j 2 cmd-L',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_0 |_
            1 midle |_1 midle |_1 midle |_
            2 very long |_2 very long |_2 very long |_

            """
        it "duplicate linewise left do nothing", ->
          ensure 'V j j cmd-H',
            selectedBufferRange: rowRange(0, 2)
            text: originalText
        it "duplicate linewise left with count do nothing", ->
          ensure 'V j j 2 cmd-H',
            selectedBufferRange: rowRange(0, 2)
            text: originalText

    describe "characterwise", ->
      describe "overwrite: false", ->
        beforeEach ->
          set
            textC: """
            o|oo
            xxx
            Y|YY
            ZZZ\n
            """
        it "duplicate charwise", ->
          ensureDuplicate = getEnsureWithOptions(mode: ['visual', 'characterwise'], selectedTextOrdered: ['oo', 'YY'])
          ensureDuplicate 'v l',
            text: """
            ooo
            xxx
            YYY
            ZZZ\n
            """
          ensureDuplicate 'cmd-L',
            text: """
            ooooo
            xxx
            YYYYY
            ZZZ\n
            """
          ensureDuplicate '2 cmd-L',
            selectedTextOrdered: ['oooo', 'YYYY']
            text: """
            ooooooooo
            xxx
            YYYYYYYYY
            ZZZ\n
            """
          ensureDuplicate 'ctrl-j', # "move"
            selectedTextOrdered: ['oooo', 'YYYY']
            text_: """
            ooooo____
            xxx  oooo
            YYYYY____
            ZZZ__YYYY\n
            """
          ensureDuplicate 'cmd-H',
            selectedTextOrdered: ['oooo', 'YYYY']
            selectedBufferRange: [
              [[1, 5], [1, 9]]
              [[3, 5], [3, 9]]
            ]
            text_: """
            ooooo____
            xxx__oooooooo
            YYYYY____
            ZZZ__YYYYYYYY\n
            """
          ensureDuplicate '2 cmd-H',
            selectedTextOrdered: ['oooooooo', 'YYYYYYYY']
            selectedBufferRange: [
              [[1, 5], [1, 13]]
              [[3, 5], [3, 13]]
            ]
            text_: """
            ooooo____
            xxx__oooooooooooooooo
            YYYYY____
            ZZZ__YYYYYYYYYYYYYYYY\n
            """

      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)
          set
            textC: """
            o|xYZ@
            oxYZ@
            o|xYZ@
            oxYZ@\n
            """

        it "duplicate charwise", ->
          ensureDuplicate = getEnsureWithOptions(mode: ['visual', 'characterwise'], selectedTextOrdered: ['xY', 'xY'])
          ensureDuplicate 'v l',
            text: """
            oxYZ@
            oxYZ@
            oxYZ@
            oxYZ@\n
            """
          ensureDuplicate 'cmd-L',
            text: """
            oxYxY
            oxYZ@
            oxYxY
            oxYZ@\n
            """
            selectedBufferRange: [
              [[0, 3], [0, 5]]
              [[2, 3], [2, 5]]
            ]
          ensureDuplicate '2 cmd-L',
            selectedTextOrdered: ['xYxY', 'xYxY']
            text: """
            oxYxYxYxY
            oxYZ@
            oxYxYxYxY
            oxYZ@\n
            """
            selectedBufferRange: [
              [[0, 5], [0, 9]]
              [[2, 5], [2, 9]]
            ]
          ensureDuplicate 'ctrl-j', # "move"
            selectedTextOrdered: ['xYxY', 'xYxY']
            text_: """
            oxYxY____
            oxYZ@xYxY
            oxYxY____
            oxYZ@xYxY\n
            """
            selectedBufferRange: [
              [[1, 5], [1, 9]]
              [[3, 5], [3, 9]]
            ]
          ensureDuplicate 'cmd-H',
            selectedTextOrdered: ['xYxY', 'xYxY']
            text_: """
            oxYxY____
            oxYxYxYxY
            oxYxY____
            oxYxYxYxY\n
            """
            selectedBufferRange: [
              [[1, 1], [1, 5]]
              [[3, 1], [3, 5]]
            ]
