#     DOMJuice early prototype, © 2011 Stéphan Kochen.
#     Made available under the MIT license.
#     http://stephank.github.com/domjuice


# Initial Setup
# -------------

# Fetch this here for easy access, and in the rare case someone overrides the
# Node name. (Perhaps by accident.)
{ELEMENT_NODE} = Node

# Name of the attribute we set on elements to identify their clone after an
# entire tree of template nodes has been cloned with `cloneNode`.
cidAttr = 'data-domjuice-cid'

# Attribute names that are template operations match this short regular
# expression. (`section:=` and `content:=` are matched separately.)
colonAssignRe = /:$/


# DOM tree iterator which traverses nodes in document order.
#
# The callback receives the node, the index in the parent node, and
# the original index, which may differ if nodes were removed.
#
# The callback may return an optional string action to perform on the node:
#
#  - `'skip'`: do not traverse children of this node.
#  - `'remove'`: remove this node.
eachNode = (rootNode, callback) ->
  walker = (element) ->
    {childNodes} = element
    {length} = childNodes
    index = originalIndex = 0
    while childNode = childNodes[index++]
      originalIndex++

      switch callback childNode, index, originalIndex
        when 'skip'
          continue
        when 'remove'
          element.removeChild childNode
          index--; length--
          continue

      walker childNode
    return

  switch callback rootNode, 0, 0
    when 'skip'   then return
    when 'remove' then throw new Error "Cannot remove the top node"

  walker rootNode


# Template Operations
# -------------------

# Each of the following classes represent a template operation.
#
# When building a template, these are dynamically subclassed. The subclasses
# carry data on that specific template operation within the template.
#
# When instantiating a template, these subclasses are then instantiated with
# the actual element to update, and the section it belongs to.

#### Variable Property Watcher Common

# Base class used by `VarAttr` and `VarContent`, because they are both similar
# in watching a property with a variable value.
class BaseVarProp
  # Whether we will update after `initialFill`.
  willUpdate: null
  # Currently displaying the root or inner context value.
  innerValueSet: null

  # Bind to the root and inner context properties on instantiation.
  constructor: (@el, @s) ->
    @listeners =
      context: bindProperty @s.context, @propertyName, @contextSet
      root: bindProperty @s.root, @propertyName, @rootSet

  # Unbind both listeners on finalize.
  finalize: ->
    @listeners.context?.unbind()
    @listeners.root?.unbind()

  # Set the initial value of the attribute using `getProperty`.
  #
  # Without any listeners we can unset `willUpdate`. We can also unset it if
  # the inner context is truthy right now, and there's no inner context
  # listener to change it into something else.
  initialFill: ->
    val = getProperty @s.context, @propertyName
    if @innerValueSet = !!val
      @set val
      unless @willUpdate = @listeners.context?
        @listeners.root?.unbind()
        @listeners.root = null
    else
      @set getProperty @s.root, @propertyName
      @willUpdate = @listeners.context? or @listeners.root?

  # Update triggered by the inner context. If there's a value, just set it
  # without fussing. If the value is falsy, we need to show root's.
  contextSet: (value) =>
    if value
      @set value
      @innerValueSet = yes
    else if @innerValueSet
      @set getProperty @s.root, @propertyName
      @innerValueSet = no

  # Update triggered by the root context. Only set the value if we're not
  # currently displaying an inner contexts value.
  rootSet: (value) =>
    @set value unless @innerValueSet

  # Set helper which does the actual update based on a value.
  # Subclasses override this to set an attribute or an element's content.
  set: (value) ->

#### Variable Attribute Operation

# Manages an element attribute with a variable value.
class VarAttr extends BaseVarProp
  set: (value) ->
    @el.setAttribute @attrName, String value or ''

#### Variable Content Operation

# Manages an element with variable content.
class VarContent extends BaseVarProp
  set: (value) =>
    textNode = @el.ownerDocument.createTextNode String value or ''
    @el.innerHTML = ''
    @el.appendChild textNode

#### Section Operation

# The glue between parent and child sections. All sections, except the
# template toplevel, are managed by one of these.
#
# Methods of this class are used by context adaptors to update the instances
# of the section.
class SectionManager
  # Currently displaying the root or inner context value.
  innerValueSet: null

  # Bind to the root and inner context properties on instantiation.
  constructor: (@el, @s) ->
    @sections = []

    @listeners = {}
    @listeners.context = bindSection @s.context, @propertyName,
        add: @contextAdd, remove: @contextRemove, refresh: @contextRefresh
    @listeners.root = bindSection @s.root, @propertyName,
        add: @rootAdd, remove: @rootRemove, refresh: @rootRefresh

  # Unbind both listeners on finalize.
  finalize: ->
    @listeners.context?.unbind()
    @listeners.root?.unbind()

  # Create the initial sections using `getSection`.
  #
  # As with `BaseVarProp#initialFill`, if there are sections at this point,
  # and there is no inner context listener to change that, we can ditch the
  # root context listener.
  initialFill: ->
    getSection @s.context, @propertyName, @add
    if @innerValueSet = @sections.length isnt 0
      unless @listeners.context?
        @listeners.root?.unbind()
        @listeners.root = null
    else
      getSection @s.root, @propertyName, @add

  # Update triggered by the inner context. Override the root context if it
  # was current, otherwise just add as normal.
  contextAdd: (item, index) =>
    if @innerValueSet
      @add item, index
    else
      @innerValueSet = yes
      @refresh (iter) ->
        iter item

  # Update triggered by the root context. Add only if it is current.
  rootAdd: (item, index) =>
    @add item, index unless @innerValueSet

  # Helper to create a section for the given item at the given index. If the
  # item is an object, the section will descend into it as a subcontext.
  add: (item, index) =>
    section = new @sectionClass item, @s
    refNode = @el.childNodes[@containerIndex + index] or null
    @el.insertBefore section.el, refNode
    @adjustNeighbours +1
    @sections.splice index, 0, section

  # Update triggered by the inner context. Make the root context current if
  # this was the last item.
  contextRemove: (item, index) =>
    if @sections.length is 1
      @innerValueSet = no
      @refresh (iter) =>
        getSection @s.root, @propertyName, iter
    else
      @remove item, index

  # Update triggered by the root context. Remove only if it is current.
  rootRemove: (item, index) =>
    @remove item, index unless @innerValueSet

  # Helper to remove the section at the given index.
  remove: (index) ->
    [section] = @sections.splice index, 1
    section.finalize()
    @el.removeChild @el.childNodes[@containerIndex + index]
    @adjustNeighbours -1

  # Update triggered by the inner context. Make the root context current if
  # there are no items after the refresh.
  #
  # FIXME: Perhaps a more efficient way of doing this?
  contextRefresh: (block) =>
    @refresh block
    unless @innerValueSet = @sections.length isnt 0
      @refresh (iter) =>
        getSection @s.root, @propertyName, iter

  # Update triggered by the root context. Refresh only if it is current.
  rootRefresh: (block) =>
    @refresh block unless @innerValueSet

  # Helper to replace all sections in one shot. The parameter is a function
  # that takes an iterator function. The iterator function is then called
  # repeatedly by the caller for each new item.
  refresh: (block) ->
    for section in @sections
      section.finalize()
      @el.removeChild @el.childNodes[@containerIndex]
    adjustment = -@sections.length
    @sections = []

    refNode = @el.childNodes[@containerIndex] or null
    block (item) ->
      @sections.push section = new @sectionClass item, @s
      @el.insertBefore section.el, refNode
    adjustment += @sections.length

    @adjustNeighbours adjustment

  # Helper used to adjust the `containerIndex` of neighbours.
  adjustNeighbours: (adjustment) ->
    for op in @s.opsByCid[@cid] when op.containerOrder > @containerOrder
      op.containerIndex += adjustment
    return


# Context Adaptors
# ----------------

# Adaptors are used to access and listen for changes to properties on
# different types of objects and collections.
#
# Listening for changes works a bit differently form the `bind` methods in,
# say, Backbone.js or jQuery. The `bind` methods of adaptors should return
# a handle object or nothing. Handle objects are expected to have a `unbind`
# method taking no parameters.

# The following is the default adaptor for regular JavaScript `Object`s and
# `Array`s. It more or less doubles as the interface description.
DefaultAdaptor =
  # Check if this adaptor can handle the given object.
  check: (object) -> yes

  # Access or listen for changes to a property of an object. The value of the
  # property should be provided as-is. Truthy values will be stringified,
  # while falsy values will display as nothing.
  getProperty: (object, property) ->
    object[property]

  bindProperty: (object, property, handler) ->

  # Called by a `SectionManager` to access or listen for changes to a property
  # on an object. Regardless of the property value, the adaptor is responsible
  # for providing a collection-like view to the `SectionManager`.
  #
  # For actual collections, these methods provide access to its items. For
  # all other types, a view of a single item should be provided for truthy
  # values, or an empty view otherwise.
  getSection: (object, property, iterator) ->
    val = object[property]
    if typeof val is 'object' and a = getAdaptor val
      a.getSectionInner val, iterator
    else if val
      iterator val, 0

  bindSection: (object, property, manager) ->
    val = object[property]
    if typeof val is 'object' and a = getAdaptor val
      a.bindSectionInner val, manager

  # The above `*Section` methods may rely on another type of adaptor to handle
  # the property's value if it is an object. These methods are provided as
  # interface between the two adaptors.
  getSectionInner: (object, iterator) ->
    if object.length?
      iterator item, i for item, i in object
    else if object
      iterator object, 0

  bindSectionInner: (object, manager) ->

#### Adaptor Registry

# List of registered adaptors.
adaptors = [DefaultAdaptor]

# Retrieve the adaptor that can handle the given context object.
getAdaptor = (object) ->
  for adaptor in adaptors
    return adaptor if adaptor.check object

# Register a new type of adaptor.
registerAdaptor = (adaptor) ->
  adaptors.unshift adaptor

#### Adaptor Helpers

# These just wrap the `getAdaptor` dance.

getProperty = (object, property) ->
  getAdaptor(object).getProperty object, property

bindProperty = (object, property, handler) ->
  getAdaptor(object).bindProperty object, property, handler

getSection = (object, property, iterator) ->
  getAdaptor(object).getSection object, property, iterator

bindSection = (object, property, manager) ->
  getAdaptor(object).bindSection object, property, manager


# Section
# -------

# A section can be the toplevel of a template (the actual template class the
# user receives as the result of `DOMJuice(...)`), a template part that is
# displayed conditionally, or a template part instantiated several times for
# a collection.
class Section
  # Construct a section by giving it a context object. (The `parent` parameter
  # is for internal use only.)
  constructor: (@context={}, parent) ->
    # Set up the context for this section. If this is the toplevel, we expect
    # the user to give us an object. If it's an internal subsection, a
    # non-object indicates a simple conditional section, which means we just
    # continue in our parents context.
    unless typeof @context is 'object'
      throw new Error "Template context should be an object" unless parent
      @context = parent.context
    @root = parent?.root or @context

    # Deep clone the template nodes.
    @el = @template.cloneNode yes

    # Find elements that have been marked with a cid.
    ops = new Array @opsByCid.length
    eachNode @el, (node) =>
      return unless node.nodeType is ELEMENT_NODE
      return unless attribute = node.getAttributeNode cidAttr
      cid = parseInt attribute.nodeValue
      node.removeAttributeNode attribute

      # Instantiate all template operations for this node.
      klasses = @opsByCid[cid]
      ops[cid] = for klass in klasses
        new klass node, this

    # Perform the initial fill for this section. Remove operations which will
    # never update again, so they will be garbage collected.
    #
    # `SectionManager`s need access to their neighbours, so expose the
    # operations. Shadow `opsByCid`, because there's no need to access supers.
    #
    # FIXME: Do we want to try clean up `SectionManager`s here too?
    @opsByCid = for elementOps in ops then for op in elementOps
      op.initialFill()
      op if op.willUpdate or op instanceof SectionManager

  # DOMJuice templates require cleaning up, to clear back-references that are
  # kept by event listeners installed on context objects. Properly calling
  # `finalize` will ensure the template instance can be garbage collected.
  #
  # Note that this does **not** remove the elements from the DOM. It is
  # expected they will be replaced any way, otherwise remove them manually.
  finalize: ->
    for cid, elementOps of @opsByCid
      for op in elementOps
        op.finalize()
    return

# The workhorse that builds Section subclasses for templates or subsections.
buildSectionClass = (template) ->
  opsByCid = []
  section = class extends Section
    template: template
    opsByCid: opsByCid

  # The various operations we support are tagged to the element using
  # a `cid`. This is simply a unique ID that persists across `cloneNode`.
  # This helper tags an operation to an element.
  addOpToElement = (element, op) ->
    if attribute = element.getAttributeNode cidAttr
      cid = parseInt attribute.nodeValue
      opsByCid[cid].push op
    else
      cid = String opsByCid.length
      element.setAttribute cidAttr, cid
      opsByCid.push [op]
    op::cid = cid

  # Walk the tree, extract sections, collect operations.
  eachNode template, (node, index, originalIndex) ->
    return 'skip' unless node.nodeType is ELEMENT_NODE

    # Check for a `section:=` operation first. Other operations on the
    # sectioned element execute within the section context, and are
    # processed by a recursive `buildSectionClass`.
    if attribute = node.getAttributeNode 'section:'
      if node is template
        throw new Error "Template root element cannot be a section"
      {nodeValue} = attribute
      node.removeAttributeNode attribute

      addOpToElement node.parentNode, class extends SectionManager
        propertyName: nodeValue
        sectionClass: buildSectionClass(node)
        containerIndex: index
        containerOrder: originalIndex

      return 'remove'


    # Check for a `content:=` operation, and skip the contents of the element
    # if found. Content may be there as a design placeholder.
    if attribute = node.getAttributeNode 'content:'
      {nodeValue} = attribute
      node.removeAttributeNode attribute

      addOpToElement node, class extends VarContent
        propertyName: nodeValue

      action = 'skip'
 
    else
      action = null

    # All other `:=` operations set variable attributes on the element.
    {attributes} = node
    {length} = attributes
    index = 0
    while attribute = attributes[index++]
      {nodeName, nodeValue} = attribute
      continue unless colonAssignRe.test nodeName
      node.removeAttributeNode attribute
      index--; length--

      nodeName = nodeName.slice 0, -1
      addOpToElement node, class extends VarAttr
        attrName: nodeName
        propertyName: nodeValue

    return action

  # Return the new section.
  section


# API
# ---

# Construct a template from the given input.
# The input can be a string of markup, or a DOM `Element`.
#
# When passing in an `Element`, it will be detached from the document and
# any parent element. It shouldn't be referenced or used afterwards;
# ownership belongs to the template returned.
#
# The `document` parameter is optionally an explicit DOM `Document` to use
# when building a template from string markup.
DOMJuice = (template, document) ->
  if typeof template is 'string'
    unless document ?= DOMJuice.document ? window?.document
      throw new Error "Cannot find a DOM Document to work with"
    tmp = document.createElement 'div'
    tmp.innerHTML = template
    unless tmp.childNodes.length is 1
      throw new Error "Template should have exactly one root element"
    template = tmp.removeChild tmp.childNodes[0]

  else unless template.nodeType is ELEMENT_NODE
    throw new Error "Expected a DOM Element or string of HTML"

  else if parentNode = template.parentNode
    parentNode.removeChild template

  buildSectionClass template


# Export as global `DOMJuice` or a CommonJS module.
if module?.exports?
  module.exports = DOMJuice
else
  @DOMJuice = DOMJuice

# Export the adaptor API.
DOMJuice.getAdaptor = getAdaptor
DOMJuice.registerAdaptor = registerAdaptor
