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

    keymaps =
      'atom-text-editor.vim-mode-plus.visual-mode':
        'up': 'vim-mode-plus-user:move-selected-text-up'
        'down': 'vim-mode-plus-user:move-selected-text-down'
        'left': 'vim-mode-plus-user:move-selected-text-left'
        'right': 'vim-mode-plus-user:move-selected-text-right'

        'cmd-up': 'vim-mode-plus-user:duplicate-selected-text-up'
        'cmd-down': 'vim-mode-plus-user:duplicate-selected-text-down'
        'cmd-left': 'vim-mode-plus-user:duplicate-selected-text-left'
        'cmd-right': 'vim-mode-plus-user:duplicate-selected-text-right'
    keymapsPriority = 1
    atom.keymaps.add "test", keymaps, keymapsPriority

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
          ensureMove 'down', text: "line1\nline0\nline2\n" # down
          ensureMove 'down', text: "line1\nline2\nline0\n" # down
          ensureMove 'up', text: "line1\nline0\nline2\n" # up
          ensureMove 'up', text: "line0\nline1\nline2\n" # up
        it "[case-2] two line", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove 'down', text: "line2\nline0\nline1\n"
          ensureMove 'up', text: "line0\nline1\nline2\n"
        it "[case-3] two line, selection is reversed: keep reversed state", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: true)
          set cursor: [1, 0]
          ensureMove 'V k', text: "line0\nline1\nline2\n"
          ensureMove 'down', text: "line2\nline0\nline1\n"
          ensureMove 'up', text: "line0\nline1\nline2\n"
        it "extends final row when move down", ->
          ensureMove = getEnsureWithOptions(selectedText: "line2\n", selectionIsReversed: false)
          set cursor: [2, 0]
          ensureMove 'V', text: "line0\nline1\nline2\n"
          ensureMove 'down', text: "line0\nline1\n\nline2\n"
          ensureMove 'down', text: "line0\nline1\n\n\nline2\n"
        it "support count", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove '2 down', text: "line2\n\nline0\nline1\n"
          ensureMove '2 up', text: "line0\nline1\nline2\n\n"
          ensureMove '1 0 down', text: "line2\n\n\n\n\n\n\n\n\n\nline0\nline1\n"
          ensureMove '5 up', text: "line2\n\n\n\n\nline0\nline1\n\n\n\n\n\n"

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
          ensureMove 'down', text: "\nline0\nline2\n"
          ensureMove 'down', text: "\nline1\nline0\n"
          ensureMove 'up', text: "\nline0\nline2\n"
          ensureMove 'up', text: "line0\nline1\nline2\n"
        it "[case-2] two line", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove 'down', text: "\nline0\nline1\n"
          ensureMove 'up', text: "line0\nline1\nline2\n"
        it "[case-3] two line, selection is reversed: keep reversed state", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: true)
          set cursor: [1, 0]
          ensureMove 'V k', text: "line0\nline1\nline2\n"
          ensureMove 'down', text: "\nline0\nline1\n"
          ensureMove 'up', text: "line0\nline1\nline2\n"
        it "extends final row when move down", ->
          ensureMove = getEnsureWithOptions(selectedText: "line2\n", selectionIsReversed: false)
          set cursor: [2, 0]
          ensureMove 'V', text: "line0\nline1\nline2\n"
          ensureMove 'down', text: "line0\nline1\n\nline2\n"
          ensureMove 'down', text: "line0\nline1\n\n\nline2\n"
        it "support count", ->
          ensureMove = getEnsureWithOptions(selectedText: "line0\nline1\n", selectionIsReversed: false)
          ensureMove 'V j', text: "line0\nline1\nline2\n"
          ensureMove '2 down', text: "\n\nline0\nline1\n"
          ensureMove '2 down', text: "\n\nline2\n\nline0\nline1\n"
          ensureMove '1 0 down', text: "\n\nline2\n\n\n\n\n\n\n\n\n\n\n\nline0\nline1\n"
          ensureMove '5 up', text: "\n\nline2\n\n\n\n\n\n\nline0\nline1\n\n\n\n\n\n"

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
          ensureMove 'down',
            text: """
            oxx
            xoo
            YZZ
            ZYY\n
            """
          ensureMove 'down',
            text_: """
            oxx
            xZZ
            Yoo
            Z__
            _YY
            """
          ensureMove '2 down',
            text_: """
            oxx
            xZZ
            Y__
            Z__
            _oo
            ___
            _YY
            """
          ensureMove '4 up',
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
          ensureMove 'down',
            text_: """
            o__
            xoo
            Y__
            ZYY\n
            """
          ensureMove 'down',
            text_: """
            o__
            xxx
            Yoo
            ZZZ
            _YY
            """
          ensureMove '2 down',
            text_: """
            o__
            xxx
            Y__
            ZZZ
            _oo
            ___
            _YY
            """
          ensureMove '4 up',
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
          ensureMove 'right',
            text_: "__line0\n____line1\n____line2\nline3\n"
            selectedText_: "__line0\n____line1\n"
          ensureMove '2 right',
            text_: "______line0\n________line1\n____line2\nline3\n"
            selectedText_: "______line0\n________line1\n"
          ensureMove 'left',
            text_: "____line0\n______line1\n____line2\nline3\n"
            selectedText_: "____line0\n______line1\n"
          ensureMove '1 0 0 left',
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
          ensureMove 'right',
            text_: "__line0\n____line1\n____line2\nline3\n"
            selectedText_: "__line0\n____line1\n"
          ensureMove '2 right',
            text_: "______line0\n________line1\n____line2\nline3\n"
            selectedText_: "______line0\n________line1\n"
          ensureMove 'left',
            text_: "____line0\n______line1\n____line2\nline3\n"
            selectedText_: "____line0\n______line1\n"
          ensureMove '1 0 0 left',
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
          ensureMove 'right',
            text: """
            oxYZ@
            oZxY@
            oZxY@
            oxYZ@
            """
          ensureMove 'right',
            text: """
            oxYZ@
            oZ@xY
            oZ@xY
            oxYZ@
            """
          ensureMove 'right',
            text_: """
            oxYZ@
            oZ@_xY
            oZ@_xY
            oxYZ@
            """
          ensureMove '5 right',
            text_: """
            oxYZ@
            oZ@______xY
            oZ@______xY
            oxYZ@
            """
          ensureMove '3 left',
            text_: """
            oxYZ@
            oZ@___xY___
            oZ@___xY___
            oxYZ@
            """
          ensureMove '1 0 0 left',
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
          ensureMove 'right',
            text_: """
            oxYZ@
            o_xY@
            o_xY@
            oxYZ@
            """
          ensureMove 'right',
            text_: """
            oxYZ@
            o__xY
            o__xY
            oxYZ@
            """
          ensureMove 'right',
            text_: """
            oxYZ@
            o__ZxY
            o__ZxY
            oxYZ@
            """
          ensureMove '5 right',
            text_: """
            oxYZ@
            o__Z@____xY
            o__Z@____xY
            oxYZ@
            """
          ensureMove '3 left',
            text_: """
            oxYZ@
            o__Z@_xY___
            o__Z@_xY___
            oxYZ@
            """
          ensureMove '1 0 0 left',
            text_: """
            oxYZ@
            xY_Z@______
            xY_Z@______
            oxYZ@
            """

  describe "duplicate up/down", ->
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
          ensure 'cmd-down',
            selectedBufferRange: rowRange(1, 1)
            text: 'line0\nline0\nline1\nline2\n'

        it "duplicate 2 selected line", ->
          ensure 'V j',
            selectedBufferRange: rowRange(0, 1)
          ensure 'cmd-down',
            selectedBufferRange: rowRange(2, 3)
            text: "line0\nline1\nline0\nline1\nline2\n"
          ensure 'cmd-up',
            selectedBufferRange: rowRange(2, 3)
            text: "line0\nline1\nline0\nline1\nline0\nline1\nline2\n"
        it "suport count", ->
          ensure 'V',
            selectedBufferRange: rowRange(0, 0)
          ensure '2 cmd-down',
            selectedBufferRange: rowRange(1, 2)
            text: "line0\nline0\nline0\nline1\nline2\n"
          ensure '2 cmd-up',
            selectedBufferRange: rowRange(1, 4)
            text: "line0\nline0\nline0\nline0\nline0\nline0\nline0\nline1\nline2\n"
      describe "overwrite: true", ->
        beforeEach ->
          setOverwriteConfig(true)

        it "overrite lines down", ->
          ensure 'V',
            selectedBufferRange: rowRange(0, 0)
          ensure 'cmd-down',
            text: "line0\nline0\nline2\n"
          ensure 'cmd-down',
            text: "line0\nline0\nline0\n"
            selectedBufferRange: rowRange(2, 2)
          ensure '2 cmd-down',
            text: "line0\nline0\nline0\nline0\nline0\n"
            selectedBufferRange: rowRange(3, 4)

        it "overrite lines up", ->
          ensure 'j j V',
            selectedBufferRange: rowRange(2, 2)
          ensure '2 cmd-up',
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
          ensure '1 0 cmd-up',
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
          ensure 'cmd-up',
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
          ensure '2 cmd-up', # mode shift to vB
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
          ensure 'cmd-down',
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
          ensure '2 cmd-down',
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
          ensure 'cmd-down',
            mode: ['visual', 'characterwise']
            selectedTextOrdered: ['oo', 'YY']
            text: """
            oooo
            xoox
            YYYY
            ZYYZ\n
            """
          ensure '2 cmd-down',
            mode: ['visual', 'blockwise']
            selectedTextOrdered: ['oo', 'oo', 'YY', 'YY']
            text: """
            oooo
            xoox
            YooY
            ZooZ
             YY
             YY\n
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
          ensure 'cmd-up',
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
        it "duplicate charwise up", ->
          set
            textC: """
            o|ooo
            xxxx
            YYYY
            ZZZZ\n
            """
          ensure 'v l cmd-up',
            mode: ['visual', 'characterwise']

  describe "duplicate right/left", ->
    describe "linewise", ->
      textOriginal = null
      beforeEach ->
        textOriginal = """
          0 |_
          1 midle |_
          2 very long |_

          """
        set
          text: textOriginal
          cursor: [0, 0]

      describe "overwrite: false", ->
        it "duplicate linewise right", ->
          ensure 'V j j cmd-right',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "count support", ->
          ensure 'V j j 2 cmd-right',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_0 |_
            1 midle |_1 midle |_1 midle |_
            2 very long |_2 very long |_2 very long |_

            """

        it "duplicate linewise left(identical behavior to right)", ->
          ensure 'V j j cmd-left',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "duplicate linewise left with count(identical behavior to right)", ->
          ensure 'V j j 2 cmd-left',
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
          ensure 'V j j cmd-right',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_
            1 midle |_1 midle |_
            2 very long |_2 very long |_

            """
        it "duplicate linewise right(no behavior diff with overwrite=false)", ->
          ensure 'V j j 2 cmd-right',
            selectedBufferRange: rowRange(0, 2)
            text: """
            0 |_0 |_0 |_
            1 midle |_1 midle |_1 midle |_
            2 very long |_2 very long |_2 very long |_

            """

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
          ensureDuplicate 'cmd-right',
            text: """
            ooooo
            xxx
            YYYYY
            ZZZ\n
            """
          ensureDuplicate '2 cmd-right',
            selectedTextOrdered: ['oooo', 'YYYY']
            text: """
            ooooooooo
            xxx
            YYYYYYYYY
            ZZZ\n
            """
          ensureDuplicate 'down', # "move"
            selectedTextOrdered: ['oooo', 'YYYY']
            text_: """
            ooooo____
            xxx  oooo
            YYYYY____
            ZZZ__YYYY\n
            """
          ensureDuplicate 'cmd-left',
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
          ensureDuplicate '2 cmd-left',
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
          ensureDuplicate 'cmd-right',
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
          ensureDuplicate '2 cmd-right',
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
          ensureDuplicate 'down', # "move"
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
          ensureDuplicate 'cmd-left',
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

  describe "complex movement", ->
    describe "overwrite: true", ->
      [selectedTextOrdered, textOriginal] = []
      beforeEach ->
        setOverwriteConfig(true)
        set text: """
          01234567890123456789012
          90123456789012345678901
          890123+--------+4567890
          789012|ABCDEFGH|3456789
          678901|IJKLMNOP|2345678
          567890+--------+1234567
          45678901234567890123456
          01234567890123456789012
          """

        selectedTextOrdered = """
          +--------+
          |ABCDEFGH|
          |IJKLMNOP|
          +--------+
          """.split("\n")
        textOriginal = editor.getText()

      it "move block of text", ->
        set cursor: [2, 6]
        ensureMove = getEnsureWithOptions({mode: ['visual', 'blockwise'], selectedTextOrdered})
        ensureMove "ctrl-v 3 j 9 l", text: textOriginal
        ensureMove "down", text: """
          01234567890123456789012
          90123456789012345678901
          890123          4567890
          789012+--------+3456789
          678901|ABCDEFGH|2345678
          567890|IJKLMNOP|1234567
          456789+--------+0123456
          01234567890123456789012
          """
        ensureMove "4 right", text: """
          01234567890123456789012
          90123456789012345678901
          890123          4567890
          789012    +--------+789
          678901    |ABCDEFGH|678
          567890    |IJKLMNOP|567
          4567890123+--------+456
          01234567890123456789012
          """
        ensureMove "1 0 up", text: """
          0123456789+--------+012
          9012345678|ABCDEFGH|901
          890123    |IJKLMNOP|890
          789012    +--------+789
          678901          2345678
          567890          1234567
          45678901234567890123456
          01234567890123456789012
          """
        ensureMove "7 left", text: """
          012+--------+3456789012
          901|ABCDEFGH|2345678901
          890|IJKLMNOP|   4567890
          789+--------+   3456789
          678901          2345678
          567890          1234567
          45678901234567890123456
          01234567890123456789012
          """
        ensureMove "down", text: """
          01234567890123456789012
          901+--------+2345678901
          890|ABCDEFGH|   4567890
          789|IJKLMNOP|   3456789
          678+--------+   2345678
          567890          1234567
          45678901234567890123456
          01234567890123456789012
          """
        ensureMove "5 right", text: """
          01234567890123456789012
          90123456+--------+78901
          890123  |ABCDEFGH|67890
          789012  |IJKLMNOP|56789
          678901  +--------+45678
          567890          1234567
          45678901234567890123456
          01234567890123456789012
          """
        ensureMove "down", text: """
          01234567890123456789012
          90123456789012345678901
          890123  +--------+67890
          789012  |ABCDEFGH|56789
          678901  |IJKLMNOP|45678
          567890  +--------+34567
          45678901234567890123456
          01234567890123456789012
          """
        ensureMove "2 left", text: """
          01234567890123456789012
          90123456789012345678901
          890123+--------+4567890
          789012|ABCDEFGH|3456789
          678901|IJKLMNOP|2345678
          567890+--------+1234567
          45678901234567890123456
          01234567890123456789012
          """
        ensureMove "2 left 5 down", text: """
          01234567890123456789012
          90123456789012345678901
          890123          4567890
          789012          3456789
          678901          2345678
          567890          1234567
          45678901234567890123456
          0123+--------+456789012
              |ABCDEFGH|
              |IJKLMNOP|
              +--------+
          """

        ensure "escape u",
          mode: 'normal',
          text: textOriginal

      it "clear overwritten state and undo grouping on mode shift", ->
        set cursor: [2, 6]
        ensureMove = getEnsureWithOptions({mode: ['visual', 'blockwise'], selectedTextOrdered})
        ensureMove "ctrl-v 3 j 9 l",
          text: textOriginal

        ensureMove "down 2 right", text: """
          01234567890123456789012
          90123456789012345678901
          890123          4567890
          789012  +--------+56789
          678901  |ABCDEFGH|45678
          567890  |IJKLMNOP|34567
          45678901+--------+23456
          01234567890123456789012
          """
        textGrouped = editor.getText()

        ensure "escape", mode: 'normal'
        ensureMove "g v", text: textGrouped
        ensureMove "2 up", text: """
          01234567890123456789012
          90123456+--------+78901
          890123  |ABCDEFGH|67890
          789012  |IJKLMNOP|56789
          678901  +--------+45678
          567890            34567
          45678901          23456
          01234567890123456789012
          """
        ensure "escape", mode: 'normal'
        ensure "u", mode: 'normal', text: textGrouped
        ensure "u", mode: 'normal', text: textOriginal
