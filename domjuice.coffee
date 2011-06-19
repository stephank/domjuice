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
  return


# Template Operations
# -------------------

# Each of the following classes represent a template operation.
#
# When building a template, these are dynamically subclassed. The subclasses
# carry data on that specific template operation within the template.
#
# When instantiating a template, these subclasses are then instantiated with
# the actual element to update, and the section that owns the instance.

# Manages an element attribute with a variable value.
class VarAttr
  constructor: (@element, @section) ->
    @section.context.listenProperty @propertyName, @update

  update: (value) =>
    @element.setAttribute @attrName, String value or ''

# Manages an element with variable content.
class VarContent
  constructor: (@element, @section) ->
    @section.context.listenProperty @propertyName, @update

  update: (value) =>
    @element.innerHTML = ''
    textNode = @element.ownerDocument.createTextNode String value or ''
    @element.appendChild textNode

# The glue between parent and child sections. All sections, except the
# template toplevel, are managed by one of these.
#
# Methods of this class are used by context adaptors to update the instances
# of the section.
class SectionManager
  constructor: (@element, @section) ->
    @section.context.listenSection @propertyName, this
    @sections = []

  # Create a new section for the given item at the given index . If the item
  # is an object, the section will descend into it as a subcontext.
  insert: (item, index) ->
    section = new @sectionClass item, @section
    refNode = @element.childNodes[@containerIndex + index] or null
    @element.insertBefore section.el, refNode
    @_adjustNeighbours +1
    @sections.splice index, 0, section
    return

  # Remove the section at the given index.
  remove: (index) ->
    [section] = @sections.splice index, 1
    section.finalize()
    @element.removeChild @element.childNodes[@containerIndex + index]
    @_adjustNeighbours -1
    return

  # Clear all instances of the section. Useful when the watched property
  # itself changes, for example from a collection to something else.
  clear: ->
    for section in @sections
      section.finalize()
      @element.removeChild @element.childNodes[@containerIndex]
    @_adjustNeighbours -@sections.length
    @sections = []
    return

  # Helper used to adjust the `containerIndex` of neighbours.
  _adjustNeighbours: (adjustment) ->
    for op in @section.opsByCid[@cid] when op.containerOrder > @containerOrder
      op.containerIndex += adjustment
    return


# Context Adaptors
# ----------------

# Adaptors are used to access and listen for changes to properties on
# different types of context objects and collections.

# Base class for a context adaptor.
#
# Except where specified, subclasses need not call super in method overrides.
class Adaptor
  # When instantiated, adaptors receive the section that owns the instance,
  # and the context object or collection. Subclasses must call super.
  constructor: (@owner, @context) ->
    @owner.adaptors.push this

  # Adaptors typically install event listeners on their context, which implies
  # a back-reference. The finalize method should clear these listeners, so
  # that the section may be garbage collected. Subclasses must call super.
  finalize: ->
    for adaptor, index in @owner.adaptors
      if adaptor is this
        @owner.adaptors.splice index, 1
        return
    return

  # Listen for changes to a property of the context. The value of the property
  # should be provided as-is. Truthy values will be stringified, while falsy
  # values will display as nothing.
  listenProperty: (property, handler) ->

  # Called by a `SectionManager` to listen for changes to a property on the
  # context. Regardless of the property value, the adaptor is responsible for
  # providing a collection-like view to the `SectionManager`.
  #
  # The `manager` parameter is the manager instance; use the `insert`,
  # `remove`, and `clear` methods to create and destroy sections as the
  # context updates.
  #
  # Typically, implementations listen only for changes on the actual property,
  # and if the property value is/becomes an object, create a new adaptor to
  # deal with it using `Adaptor.get` and `listenSectionInner`.
  #
  # For collections, the handlers are used to create sections for each item
  # in the collection. For all other types, the handlers should be used to
  # create a single section for truthy values, and none otherwise.
  listenSection: (property, manager) ->

  # Called when an adaptor is instantiated in service of the above
  # `listenSection` method on another adaptor.
  #
  # The context of the inner adaptor is the value of the property the section
  # is accessing. Following the above logic, this will always be an object.
  # If that object is a collection, this method should create a section for
  # each item in it. Otherwise, a single section should be created for just
  # the context.
  listenSectionInner: (manager) ->

  # Whether the adaptor is capable of noticing updates at all.
  #
  # If this is false, the adaptor and associated operations can be discarded
  # after the template instance has done its initial fill.
  willUpdate: false

  # Trigger all installed listeners for the current situation, to perform the
  # initial fill of the template instance.
  initialFill: ->

#### Adaptors Registry

# Each entry has a `klass` and `check`. If the check succeeds for a context
# object, the adaptor class is instantiated and used.
adaptorTypes = []

# Adapt the given context object, using the registry to find the right
# adaptor class, or falling back to the `DefaultAdaptor`.
Adaptor.get = (owner, context) ->
  for {klass, check} in adaptorTypes
    return new klass owner, context if check context
  return new DefaultAdaptor owner, context

# Register a new type of adaptor.
Adaptor.register = (klass, check) ->
  adaptorTypes.push {klass, check}

#### Default Adaptor

# Adaptor for regular JavaScript `Object`s and `Array`s.
class DefaultAdaptor extends Adaptor
  # Simply gather all listeners here, so we can trigger them in `initialFill`.
  # We can't really install any listeners on the context.
  constructor: (@context) ->
    super
    @properties = []
    @sections = []
    @inners = []

  listenProperty: (property, handler) ->
    @properties.push {property, handler}

  listenSection: (property, manager) ->
    @sections.push {property, manager}

  listenSectionInner: (manager) ->
    @inners.push manager

  # We have no way of noticing changes.
  willUpdate: false

  # The initial fill is all the `DefaultAdaptor` really does. We trigger
  # listeners once here, and create inner adaptors for sections.
  initialFill: ->
    for {property, handler} in @properties
      handler @context[property]

    for {property, manager} in @sections
      value = @context[property]
      if typeof value is 'object'
        adaptor = Adaptor.get @owner, value
        adaptor.listenSectionInner manager
        adaptor.initialFill()
      else if value
        manager.insert value, 0

    for manager in @inners
      if @context.length > 0
        manager.insert item, i for item, i in @context
      else
        manager.insert @context, 0

    return


# Section
# -------

# A section can be the toplevel of a template (the actual template class the
# user receives as the result of `DOMJuice(...)`), a template part that is
# displayed conditionally, or a template part instantiated several times for
# a collection.
class Section
  # Construct a section by giving it a context object. (The `parent` parameter
  # is for internal use only.)
  constructor: (context={}, parent) ->
    # Set up the context for this section. If this is the toplevel, we expect
    # the user to give us an object. If it's an internal subsection, a
    # non-object indicates a simple conditional section, which means we just
    # continue in our parents context.
    @adaptors = []
    if context instanceof Adaptor
      @context = context
    else if typeof context is 'object'
      @context = Adaptor.get this, context
    else
      throw new Error "Template context should be an object" unless parent
      @context = parent.context
    @rootNode = parent?.rootNode or this

    # Deep clone the template nodes.
    @el = @template.cloneNode true

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

    # SectionManagers need access to their neighbours, so expose `ops`.
    # Shadow `opsByCid`, because there's no need to access super's.
    @opsByCid = ops

    # Perform the initial fill of the entire template.
    # We also eliminate adaptors that won't update afterwards.
    for adaptor in @adaptors.slice()
      adaptor.initialFill()
      adaptor.finalize() unless adaptor.willUpdate

  # DOMJuice templates require cleaning up, to clear back-references that are
  # kept by event listeners installed on context objects. Properly calling
  # `finalize()` will ensure the template instance can be garbage collected.
  #
  # Note that this does **not** remove the elements from the DOM. It is
  # expected they will be replaced any way, or remove them manually.
  finalize: ->
    @adaptors[0].finalize() until @adaptors.length is 0
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
    return

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

# Users may want to extend `Adaptor` and access the registry.
DOMJuice.Adaptor = Adaptor
