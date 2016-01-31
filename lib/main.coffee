{CompositeDisposable} = require 'atom'

getEditor = ->
  atom.workspace.getActiveTextEditor()

getView = (model) ->
  atom.views.getView(model)

MoveMethodConfig = 'vim-mode-plus-move-selected-text.moveMethod'
OverwriteClass = 'vim-mode-plus-move-selected-text-overwrite'

module.exports =
  config:
    moveMethod:
      type: 'string'
      default: 'insert'
      enum: ['insert', 'overwrite']

  eachEditorElement: (fn) ->
    atom.workspace.getTextEditors().forEach (editor) ->
      fn(getView(editor))

  activate: ->
    @subscriptions = new CompositeDisposable

    @subscribe atom.config.observe MoveMethodConfig, (newValue) =>
      @eachEditorElement (editorElement) ->
        editorElement.classList.remove(OverwriteClass)
        if newValue is 'overwrite'
          editorElement.classList.add(OverwriteClass)

    @subscribe atom.commands.add 'atom-text-editor',
      'vim-mode-plus-user:toggle-move-method': ->
        currentValue = atom.config.get(MoveMethodConfig)
        newValue = if currentValue is 'insert' then 'overwrite' else 'insert'
        atom.config.set(MoveMethodConfig, newValue)

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
