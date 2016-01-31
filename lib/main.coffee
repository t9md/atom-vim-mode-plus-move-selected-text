{CompositeDisposable} = require 'atom'

getEditor = ->
  atom.workspace.getActiveTextEditor()

getView = (model) ->
  atom.views.getView(model)

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
      fn(getView(editor))

  activate: ->
    @subscriptions = new CompositeDisposable

    @subscribe atom.config.observe OverwriteConfig, (newValue) =>
      @eachEditorElement (editorElement) ->
        editorElement.classList.remove(OverwriteClass)
        editorElement.classList.add(OverwriteClass) if newValue

    @subscribe atom.commands.add 'atom-text-editor',
      'vim-mode-plus-user:toggle-overwrite': ->
        atom.config.set(OverwriteConfig, not atom.config.get(OverwriteConfig))

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
