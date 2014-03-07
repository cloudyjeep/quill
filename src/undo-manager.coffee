_               = require('lodash')
ScribeKeyboard  = require('./keyboard')
ScribeRange     = require('./range')
Tandem          = require('tandem-core')


getLastChangeIndex = (delta) ->
  lastChangeIndex = index = offset = 0
  _.each(delta.ops, (op) ->
    # Insert
    if Tandem.InsertOp.isInsert(op)
      offset += op.getLength()
      lastChangeIndex = index + offset
    else if Tandem.RetainOp.isRetain(op)
      # Delete
      if op.start > index
        lastChangeIndex = index + offset
        offset -= (op.start - index)
      # Format
      if _.keys(op.attributes).length > 0
        lastChangeIndex = op.end + offset
      index = op.end
  )
  if delta.endLength < delta.startLength + offset
    lastChangeIndex = delta.endLength
  return lastChangeIndex

_change = (source, dest) ->
  if @stack[source].length > 0
    change = @stack[source].pop()
    @lastRecorded = 0
    _ignoreChanges.call(this, =>
      @editor.applyDelta(change[source], { source: 'user' })
      index = getLastChangeIndex(change[source])
      @editor.setSelection(new ScribeRange(@editor, index, index))
    )
    @stack[dest].push(change)

_ignoreChanges = (fn) ->
  oldIgnoringChanges = @ignoringChanges
  @ignoringChanges = true
  fn.call(this)
  @ignoringChanges = oldIgnoringChanges


class ScribeUndoManager
  constructor: (@editor, @options = {}) ->
    @lastRecorded = 0
    this.clear()
    this.initListeners()

  initListeners: ->
    @editor.keyboard.addHotkey(ScribeKeyboard.hotkeys.UNDO, =>
      this.undo()
      return false
    )
    @editor.keyboard.addHotkey(ScribeKeyboard.hotkeys.REDO, =>
      this.redo()
      return false
    )
    @ignoringChanges = false
    @editor.on(@editor.constructor.events.TEXT_CHANGE, (delta, origin) =>
      this.record(delta, @oldDelta) unless @ignoringChanges and origin == 'user'
      @oldDelta = @editor.getDelta()
    )

  clear: ->
    @stack =
      undo: []
      redo: []
    @oldDelta = @editor.getDelta()

  record: (changeDelta, oldDelta) ->
    return if changeDelta.isIdentity()
    @redoStack = []
    try
      undoDelta = oldDelta.invert(changeDelta)
      timestamp = new Date().getTime()
      if @lastRecorded + @options.undoDelay > timestamp and @stack.undo.length > 0
        change = @stack.undo.pop()
        if undoDelta.canCompose(change.undo) and change.redo.canCompose(changeDelta)
          undoDelta = undoDelta.compose(change.undo)
          changeDelta = change.redo.compose(changeDelta)
        else
          console.warn "Unable to compose change, clearing undo stack" if console?
          this.clear()
          @lastRecorded = timestamp
      else
        @lastRecorded = timestamp
      @stack.undo.push({
        redo: changeDelta
        undo: undoDelta
      })
      @stack.undo.unshift() if @stack.undo.length > @options.undoMaxStack
      return true
    catch ignored
      this.clear()
      return false

  redo: ->
    _change.call(this, 'redo', 'undo')

  ###
  transformExternal: (delta) ->
    return if delta.isIdentity()
    @stack['undo'] = _.map(@stack['undo'], (change) ->
      return {
        redo: delta.follows(change.redo, true)
        undo: change.undo.follows(delta, true)
      }
    )
  ###

  undo: ->
    _change.call(this, 'undo', 'redo')


module.exports = ScribeUndoManager
