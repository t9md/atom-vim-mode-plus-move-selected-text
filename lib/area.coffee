{opposite} = require './utils'

class Area
  data: null
  linewise: false

  constructor: (text, @linewise=false, @overwrittenArea) ->
    if @linewise
      text = text.split("\n")
      text.pop()
      @data = text
    else
      @data = text

  isLinewise: ->
    @linewise

  getData: ->
    @data

  getTextByRotate: (direction) ->
    @rotate(direction)
    @getText()

  getText: ->
    if @isLinewise()
      @getData().join("\n") + "\n"
    else
      @getData()

  rotate: (direction) ->
    switch direction
      when 'up'
        text = @data.shift()
        text = @overwrittenArea.pushOut(text, opposite(direction)) if @overwrittenArea?
        @data.push(text)
      when 'down'
        text = @data.pop()
        text = @overwrittenArea.pushOut(text, opposite(direction)) if @overwrittenArea?
        @data.unshift(text)
      when 'right'
        [other..., text] = @data
        text = @overwrittenArea.pushOut(text, opposite(direction)) if @overwrittenArea?
        @data = [text, other...].join("")
      when 'left'
        [text, other...,] = @data
        text = @overwrittenArea.pushOut(text, opposite(direction)) if @overwrittenArea?
        @data = [other..., text].join("")

  pushOut: (value, direction) ->
    switch direction
      when 'up'
        @data.unshift(value)
        @data.pop()
      when 'down'
        @data.push(value)
        @data.shift()
      when 'left'
        data = @data[0]
        data = data.split('')
        data.push(value)
        pushedOut = data.shift()
        @data[0] = data.join("")
        pushedOut
      when 'right'
        data = @data[0]
        data = data.split('')
        data.unshift(value)
        pushedOut = data.pop()
        @data[0] = data.join("")
        pushedOut

module.exports = Area
