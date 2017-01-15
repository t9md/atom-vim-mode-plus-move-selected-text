{
  getSelectedTexts
} = require './utils'

class State
  selectedTexts: null
  checkpoint: null
  constructor: (@checkpoint) ->

class StateManager
  constructor: ->
    @stateByEditor = new Map

  resetIfNecessary: (editor) ->
    state = @stateByEditor.get(editor)
    unless (state? and state.selectedTexts is getSelectedTexts(editor))
      @stateByEditor.set(editor, new State(editor.createCheckpoint()))

  delete: (editor) ->
    @stateByEditor.delete(editor)

  update: (editor) ->
    @stateByEditor.get(editor).selectedTexts = getSelectedTexts(editor)

  groupChanges: (editor) ->
    state = @stateByEditor.get(editor)
    unless state.checkpoint?
      throw new Error("called GroupChanges with @checkpoint undefined")

    editor.groupChangesSinceCheckpoint(state.checkpoint)
    @update(editor)

module.exports = StateManager
