{opposite} = require './utils'
{inspect} = require 'util'

class Area
  data: null
  linewise: false

  constructor: (text, @linewise=false, @overwrittenArea) ->
    if @linewise
      @data = text.replace(/\n$/, '').split("\n")
    else
      @data = [text]

  isLinewise: ->
    @linewise

  getData: ->
    @data

  getTextByRotate: (direction) ->
    @rotate(direction)
    @getText()

  getText: ->
    text = @getData().join("\n")
    if @isLinewise()
      text + "\n"
    else
      text

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
        [other..., text] = @data[0]
        text = @overwrittenArea.pushOut(text, opposite(direction)) if @overwrittenArea?
        @data[0] = [text, other...].join("")
      when 'left'
        [text, other...,] = @data[0]
        text = @overwrittenArea.pushOut(text, opposite(direction)) if @overwrittenArea?
        @data[0] = [other..., text].join("")

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
