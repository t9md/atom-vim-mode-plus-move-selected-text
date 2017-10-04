function getSelectedTexts(editor) {
  return editor
    .getSelections()
    .map(selection => selection.getText())
    .join("\n")
}

class State {
  constructor(checkpoint) {
    this.checkpoint = checkpoint
    this.selectedTexts = null
    this.overwrittenBySelection = new Map()
  }
}

module.exports = class StateManager {
  constructor() {
    this.stateByEditor = new Map()
  }

  resetIfNecessary(editor) {
    if (!this.isSequentialExecution(editor)) {
      this.reset(editor)
    }
  }

  reset(editor) {
    this.stateByEditor.set(editor, new State(editor.createCheckpoint()))
  }

  isSequentialExecution(editor) {
    const state = this.stateByEditor.get(editor)
    return state && state.selectedTexts === getSelectedTexts(editor)
  }

  get(editor) {
    return this.stateByEditor.get(editor)
  }

  delete(editor) {
    this.stateByEditor.delete(editor)
  }

  update(editor) {
    this.stateByEditor.get(editor).selectedTexts = getSelectedTexts(editor)
  }

  groupChanges(editor) {
    const state = this.stateByEditor.get(editor)
    if (!state.checkpoint) {
      throw new Error("called groupChanges with this.checkpoint undefined")
    }

    editor.groupChangesSinceCheckpoint(state.checkpoint)
    this.update(editor)
  }

  setOverwrittenForSelection(selection, overwritten) {
    this.stateByEditor.get(selection.editor).overwrittenBySelection.set(selection, overwritten)
  }

  getOverwrittenForSelection(selection) {
    return this.stateByEditor.get(selection.editor).overwrittenBySelection.get(selection)
  }

  hasOverwrittenForSelection(selection) {
    return this.stateByEditor.get(selection.editor).overwrittenBySelection.has(selection)
  }
}
