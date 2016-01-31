{CompositeDisposable} = require 'atom'

getEditor = ->
  atom.workspace.getActiveTextEditor()

getView = (model) ->
  atom.views.getView(model)

module.exports =
  config:
    moveMethod:
      type: 'string'
      default: 'insert'
      enum: ['insert', 'overwrite']

  activate: ->
    @subscriptions = new CompositeDisposable
    @subscribe atom.commands.add 'atom-text-editor',
      'vim-mode-plus-user:toggle-move-method': ->
        currentMethod = atom.config.get('vim-mode-plus-move-selected-text.moveMethod')
        newMethod = if currentMethod is 'insert' then 'overwrite' else 'insert'
        atom.config.set('vim-mode-plus-move-selected-text.moveMethod', newMethod)
        editorElement = getView(getEditor())
        if newMethod is 'insert'
          editorElement.classList.remove 'vim-mode-plus-move-selected-text-overwrite'
        else
          editorElement.classList.add 'vim-mode-plus-move-selected-text-overwrite'

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptions = {}
    cachedTags = null

  subscribe: (args...) ->
    @subscriptions.add args...

  consumeVim: ->
    for name, klass of require("./move-selected-text")
      @subscribe klass.registerCommand()
