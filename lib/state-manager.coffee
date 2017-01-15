{
  getSelectedTexts
} = require './utils'

class State
  selectedTexts: null
  checkpoint: null
  constructor: (@checkpoint) ->
    @overwrittenBySelection = new Map()

class StateManager
  constructor: ->
    @stateByEditor = new Map

  resetIfNecessary: (editor) ->
    @reset(editor) unless @isSequentialExecution(editor)

  reset: (editor) ->
    @stateByEditor.set(editor, new State(editor.createCheckpoint()))

  isSequentialExecution: (editor) ->
    state = @stateByEditor.get(editor)
    state? and state.selectedTexts is getSelectedTexts(editor)

  get: (editor) ->
    @stateByEditor.get(editor)

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

  setOverwrittenForSelection: (selection, overwritten) ->
    @stateByEditor.get(selection.editor).overwrittenBySelection.set(selection, overwritten)

  getOverwrittenForSelection: (selection) ->
    @stateByEditor.get(selection.editor).overwrittenBySelection.get(selection)

  hasOverwrittenForSelection: (selection) ->
    @stateByEditor.get(selection.editor).overwrittenBySelection.has(selection)

module.exports = StateManager
