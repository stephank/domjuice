#     DOMJuice Backbone.js glue, © 2011 Stéphan Kochen.
#     Made available under the MIT license.
#     http://stephank.github.com/domjuice


{Adaptor} = DOMJuice
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


class BackboneAdaptor extends Adaptor
  constructor: (@context) ->
    super
    @properties = []
    @sections = []
    @inners = []

  finalize: ->
    super

    for {property, handler} in @properties
      @context.unbind "change:#{property}", handler

    for {property, handler, adaptor} in @sections
      @context.unbind "change:#{property}", handler
      adaptor?.finalize()

    for {addHandler, removeHandler, refreshHandler} in @inners
      @context.unbind "add", addHandler
      @context.unbind "remove", removeHandler
      @context.unbind "refresh", refreshHandler

    return

  listenProperty: (property, handler) ->
    if @context instanceof Collection
      throw new Error "No properties on a collection."

    state = {property}

    state.handler = (model, val, options) -> handler val
    @context.bind "change:#{property}", state.handler

    @properties.push state

  listenSection: (property, manager) ->
    state = {property, adaptor: null}

    state.handler = (model, val, options) =>
      manager.clear()
      if state.adaptor
        state.adaptor.finalize()
        state.adaptor = null

      if typeof val is 'object'
        state.adaptor = Adaptor.get @owner, val
        state.adaptor.listenSectionInner manager
        adaptor.initialFill()
      else if val
        manager.insert val, 0
    @context.bind "change:#{property}", state.handler

    @sections.push state

  listenSectionInner: (manager) ->
    unless @context instanceof Collection
      manager.insert this, 0
      return

    state = {}

    state.addHandler = (model, collection, options) ->
      # FIXME: Seriouslly, Backbone's `_add` already knows the index.
      # We shouldn't have to figure it out again here.
      index = collection.indexOf model
      manager.insert model, index
    @context.bind "add", state.addHandler

    state.removeHandler = (model, collection, options, index) ->
      manager.remove index
    @context.bind "remove", state.removeHandler

    state.refreshHandler = (collection, options) ->
      manager.clear()
      collection.each (model, i) ->
        manager.insert model, i
    @context.bind "refresh", state.refreshHandler

    @inners.push state

  willUpdate: true

  initialFill: ->
    for {property, handler} in @properties
      handler @context, @context.get(property), {}

    for {property, handler} in @sections
      handler @context, @context.get(property), {}

    for {addHandler} in @inners
      @context.each (model) =>
        addHandler model, @context, {}

    return

Adaptor.register BackboneAdaptor, (obj) ->
  obj instanceof Model or obj instanceof Collection
