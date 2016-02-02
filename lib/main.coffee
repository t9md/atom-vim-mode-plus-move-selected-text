{CompositeDisposable} = require 'atom'

OverwriteConfig = 'vim-mode-plus-move-selected-text.overwrite'
OverwriteClass = 'vim-mode-plus-move-selected-text-overwrite'

module.exports =
  config:
    overwrite:
      order: 0
      type: 'boolean'
      default: false

  eachEditorElement: (fn) ->
    atom.workspace.getTextEditors().forEach (editor) ->
      fn(atom.views.getView(editor))

  activate: ->
    @subscriptions = new CompositeDisposable

    @subscribe atom.config.observe OverwriteConfig, (newValue) =>
      @eachEditorElement (editorElement) ->
        editorElement.classList.toggle(OverwriteClass, newValue)

    @subscribe atom.commands.add 'atom-text-editor',
      'vim-mode-plus-user:toggle-overwrite': ->
        newValue = not atom.config.get(OverwriteConfig)
        atom.config.set(OverwriteConfig, newValue)

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = {}

    @eachEditorElement (editorElement) ->
      editorElement.classList.remove(OverwriteClass)

  subscribe: (args...) ->
    @subscriptions.add args...

  consumeVim: ->
    for name, klass of require("./move-selected-text")
      @subscribe klass.registerCommand()
