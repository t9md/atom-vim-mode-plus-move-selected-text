{CompositeDisposable, Disposable} = require 'atom'

OverwriteConfig = 'vim-mode-plus-move-selected-text.overwrite'
OverwriteClass = 'vim-mode-plus-move-selected-text-overwrite'

module.exports =
  config:
    overwrite:
      order: 0
      type: 'boolean'
      default: false

  activate: ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add new Disposable ->
      for editor in atom.workspace.getTextEditors()
        editor.element.classList.remove(OverwriteClass)

    @subscriptions.add atom.workspace.observeTextEditors (editor) ->
      editor.element.classList.toggle(OverwriteClass, atom.config.get(OverwriteConfig))

    @subscriptions.add atom.config.observe OverwriteConfig, (newValue) ->
      for editor in atom.workspace.getTextEditors()
        editor.element.classList.toggle(OverwriteClass, newValue)

    @subscriptions.add atom.commands.add 'atom-text-editor',
      'vim-mode-plus-user:move-selected-text-toggle-overwrite': ->
        atom.config.set(OverwriteConfig, not atom.config.get(OverwriteConfig))

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = null

  consumeVim: ({observeVimStates}) ->
    {commands, stateManager} = require("./move-selected-text")
    
    for name, klass of commands
      @subscriptions.add(klass.registerCommand())

    for name, klass of require("./duplicate-selected-text")
      @subscriptions.add(klass.registerCommand())

    observeVimStates (vimState) ->
      vimState.modeManager.onDidDeactivateMode ({mode}) ->
        if mode is 'visual'
          stateManager.delete(vimState.editor)
