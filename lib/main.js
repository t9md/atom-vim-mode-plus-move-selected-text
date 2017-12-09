const {CompositeDisposable, Disposable} = require("atom")

const OVERWRITE_CONFIG = "vim-mode-plus-move-selected-text.overwrite"
const OVERWRITE_CLASS = "vim-mode-plus-move-selected-text-overwrite"

module.exports = {
  config: {
    overwrite: {
      order: 0,
      type: "boolean",
      default: false,
    },
  },

  activate() {
    this.subscriptions = new CompositeDisposable(
      new Disposable(() => {
        for (const editor of atom.workspace.getTextEditors()) {
          editor.element.classList.remove(OVERWRITE_CLASS)
        }
      }),
      atom.workspace.observeTextEditors(editor => {
        editor.element.classList.toggle(OVERWRITE_CLASS, atom.config.get(OVERWRITE_CONFIG))
      }),
      atom.config.observe(OVERWRITE_CONFIG, newValue => {
        for (const editor of atom.workspace.getTextEditors()) {
          editor.element.classList.toggle(OVERWRITE_CLASS, newValue)
        }
      }),
      atom.commands.add("atom-text-editor", {
        "vim-mode-plus-user:move-selected-text-toggle-overwrite"() {
          atom.config.set(OVERWRITE_CONFIG, !atom.config.get(OVERWRITE_CONFIG))
        },
      })
    )
  },

  deactivate() {
    this.subscriptions.dispose()
  },

  consumeVim({getClass, observeVimStates}) {
    const {commands, stateManager} = require("./move-selected-text")(getClass)

    for (const command of Object.values(commands)) {
      this.subscriptions.add(command.registerCommand())
    }

    observeVimStates(vimState =>
      vimState.onDidDeactivateMode(({mode}) => mode === "visual" && stateManager.delete(vimState.editor))
    )
  },
}
