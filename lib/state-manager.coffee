{
  getSelectedTexts
} = require './utils'

class State
  selectedTexts: null
  checkpoint: null
  overwrittenBySelection: null
  editor: null

  constructor: (@editor) ->

  isSequential: ->
    @selectedTexts is getSelectedTexts(@editor)

  init: ->
    @checkpoint = @editor.createCheckpoint()
    @overwrittenBySelection = null

  updateSelectedTexts: ->
    @selectedTexts = getSelectedTexts(@editor)

  groupChanges: ->
    unless @checkpoint?
      throw new Error("called GroupChanges with @checkpoint undefined")
    @editor.groupChangesSinceCheckpoint(@checkpoint)

class StateManager
  constructor: ->
    @stateByEditor = new Map

  set: (editor) ->
    @stateByEditor.set(editor, new State(editor))

  get: (editor) ->
    @stateByEditor.get(editor)

  has: (editor) ->
    @stateByEditor.has(editor)

  remove: (editor) ->
    @stateByEditor.delete(editor)

module.exports = StateManager
