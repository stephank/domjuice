#     DOMJuice Backbone.js glue, © 2011 Stéphan Kochen.
#     Made available under the MIT license.
#     http://stephank.github.com/domjuice


{Model, Collection} = Backbone

# FIXME: Monkey patch. Hoped I wouldn't have to do this.
# We need to know the indices of collection operations, but there's no
# reliable way to figure that out for `remove`.
Collection::_remove = (model, options={}) ->
  model = @getByCid(model) or @get(model)
  return unless model
  delete @_byId[model.id]
  delete @_byCid[model.cid]
  delete model.collection
  index = this.indexOf model
  @models.splice index, 1
  @length--
  model.trigger 'remove', model, this, options, index unless options.silent
  model.unbind 'all', @_boundOnModelEvent
  return model


DOMJuice.registerAdaptor
  check: (obj) ->
    obj instanceof Model or obj instanceof Collection

  getProperty: (obj, prop) ->
    if obj instanceof Collection
      throw new Error "No properties on a collection."

    obj.get prop

  bindProperty: (obj, prop, cb) ->
    if obj instanceof Collection
      throw new Error "No properties on a collection."

    event = "change:#{prop}"
    obj.bind event, handler = (_, val) ->
      cb val

    unbind: ->
      obj.unbind event, handler

  getSection: (obj, prop, iter) ->
    if obj instanceof Collection
      throw new Error "No properties on a collection."

    val = obj.get prop
    if typeof val is 'object' and a = getAdaptor val
      a.getSectionInner val, iter
    else if val
      iter val, 0

  bindSection: (prop, man) ->
    if obj instanceof Collection
      throw new Error "No properties on a collection."

    event = "change:#{prop}"
    innerListener = null
    obj.bind event, handler = (_, val) ->
      innerListener?.unbind()

      man.refresh (iter) ->
        if typeof val is 'object' and a = getAdaptor val
          a.getSectionInner val, iter
          innerListener = a.bindSectionInner val, man
        else if val
          iter val
          innerListener = null

    unbind: ->
      obj.unbind event, handler
      innerListener?.unbind()

  getSectionInner: (obj, iter) ->
    if obj instanceof Collection
      obj.each (item, i) ->
        iter item, i
    else
      iter obj, 0

  bindSectionInner: (obj, man) ->
    unless obj instanceof Collection
      man.add this, 0
      return

    obj.bind "add", addHandler = (model) ->
      # FIXME: Seriously, Backbone's `_add` already knows the index.
      # We shouldn't have to figure it out again here.
      idx = obj.indexOf model
      man.add model, idx

    obj.bind "remove", removeHandler = (_, _, _, idx) ->
      man.remove idx

    obj.bind "refresh", refreshHandler = ->
      man.refresh (iter) ->
        obj.each iter

    unbind: ->
      obj.unbind "add", addHandler
      obj.unbind "remove", removeHandler
      obj.unbind "refresh", refreshHandler
