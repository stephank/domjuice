#     DOMJuice early prototype, © 2011 Stéphan Kochen.
#     Made available under the MIT license.
#     http://stephank.github.com/domjuice


# Initial Setup
# -------------

# Alias this for clarity.
ELEMENT_NODE = 1

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


# Context Adaptors
# ----------------

# Adaptors are used to access and listen for changes to properties on
# different types of objects and collections.
#
# Listening for changes works a bit differently from the `bind` methods in,
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
  # the property's value if it is an object. These methods are provided as an
  # interface between the two adaptors.
  getSectionInner: (object, iterator) ->
    if object.length?
      iterator item, i for item, i in object
    else if object
      iterator object, 0

  bindSectionInner: (object, manager) ->

#### Registry

# List of registered adaptors.
adaptors = [DefaultAdaptor]

# Retrieve the adaptor that can handle the given context object.
getAdaptor = (object) ->
  for adaptor in adaptors
    return adaptor if adaptor.check object

# Register a new type of adaptor.
registerAdaptor = (adaptor) ->
  adaptors.unshift adaptor

#### Helpers

# These just wrap the `getAdaptor` dance.

getProperty = (object, property) ->
  getAdaptor(object).getProperty object, property

bindProperty = (object, property, handler) ->
  getAdaptor(object).bindProperty object, property, handler

getSection = (object, property, iterator) ->
  getAdaptor(object).getSection object, property, iterator

bindSection = (object, property, manager) ->
  getAdaptor(object).bindSection object, property, manager


# Animators
# ---------

# Animators are classes that perform animations when DOMJuice changes
# contents. What animation to perform is either determined by the global
# `DOMJuice.defaultAnimation` or per operation using the `fx:=` attribute.

# The following is an animator that does nothing. It is the default and more
# or less doubles as the interface description. There's no need to inherit
# from this class.
class NoAnimation
  # Transition in the given elements, which are already in the DOM.
  # `options.content` is set if this is a content operation.
  # `options.refresh` is set if this is a complete section refresh.
  add: (elements, options) ->

  # Transition out the given elements. Similar to `add`, but with a callback
  # that should be called when the animation finishes, after which the
  # elements will be removed from the DOM. Animators should be prepared to
  # deal with a `remove` interrupting an `add` animation.
  remove: (elements, options, callback) ->
    callback()

#### Registry

# Map of registered animators by name.
animations =
  'none': NoAnimation

# Register a new type of animation.
registerAnimation = (name, animator) ->
  animations[name] = animator


# Template Operations
# -------------------

# Each of the following classes represent a template operation.
#
# When building a template, these are dynamically subclassed. The subclasses
# carry data on that specific template operation within the template.
#
# When instantiating a template, these subclasses are then instantiated with
# the actual element to update, and the section it belongs to.

#### Property Watcher Common

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
      @initialSet val
      unless @willUpdate = @listeners.context?
        @listeners.root?.unbind()
        @listeners.root = null
    else
      @initialSet getProperty @s.root, @propertyName
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

  # Set helpers which do the actual fill and update based on a value.
  # Subclasses override these to set an attribute or an element's content.
  set: (value) ->
  initialSet: (value) ->

#### Variable Attribute

# Manages an element attribute with a variable value.
class VarAttr extends BaseVarProp
  set: (value) ->
    @el.setAttribute @attrName, String value or ''

  initialSet: (value) ->
    @set value

#### Variable Content

# Manages an element with variable content.
class VarContent extends BaseVarProp
  constructor: ->
    super
    @anim = new @animatorKlass

  # Helper used to create a span element, for animation, and a text node.
  createNode: (value) ->
    doc = @el.ownerDocument
    spanNode = doc.createElement 'span'
    textNode = doc.createTextNode String value or ''
    spanNode.appendChild textNode
    spanNode

  # Transition out the current span, create a new one, and transition that in.
  # When rapidly refreshing content, be careful not to double remove elements.
  set: (value) =>
    old = for child in @el.childNodes when not child.ghost
      child.ghost = yes
      child
    @anim.remove old, content: yes, =>
      @el.removeChild child for child in old
      return

    node = @createNode value
    @el.appendChild node
    @anim.add [node], content: yes

  # The initial set is not animated, and thus a lot simpler.
  initialSet: (value) ->
    @el.innerHTML = ''
    @el.appendChild @createNode value

#### Partial Content

# Invokes a partial and sets the element content to it. Partials need not be
# DOMJuice templates, they can just as well be anything else that exposes an
# attribute `el` with the DOM `Element`. Other than that, DOMJuice only looks
# for the optional `finalize` method.
class PartialContent
  constructor: (@el, @s) ->
    klass = DOMJuice.partials[@partialName]
    @partial = new klass @s.context

  finalize: ->
    @partial.finalize?()

  initialFill: ->
    @el.innerHTML = ''
    @el.appendChild @partial.el

#### Section Common

# The glue between parent and child sections. All sections, except the
# template toplevel, are managed by one of these. This is the base class for
# regular and negated sections containing common functionality.
class BaseSectionManager
  # Currently displaying the root or inner context value.
  innerValueSet: null

  # Bind to the root and inner context properties on instantiation.
  constructor: (@el, @s) ->
    @anim = new @animatorKlass

    @listeners = {}
    @listeners.context = bindSection @s.context, @propertyName,
        add: @contextAdd, remove: @contextRemove, refresh: @contextRefresh
    @listeners.root = bindSection @s.root, @propertyName,
        add: @rootAdd, remove: @rootRemove, refresh: @rootRefresh

  # Unbind both listeners on finalize.
  finalize: ->
    @listeners.context?.unbind()
    @listeners.root?.unbind()

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

  # Update triggered by the inner context. Make the root context current if
  # this was the last item.
  contextRemove: (item, index) =>
    if @numItems() is 1
      @innerValueSet = no
      @refresh (iter) =>
        getSection @s.root, @propertyName, iter
    else
      @remove item, index

  # Update triggered by the root context. Remove only if it is current.
  rootRemove: (item, index) =>
    @remove item, index unless @innerValueSet

  # Update triggered by the inner context. Make the root context current if
  # there are no items after the refresh.
  #
  # FIXME: Perhaps a more efficient way of doing this?
  contextRefresh: (block) =>
    @refresh block
    unless @innerValueSet = @numItems() isnt 0
      @refresh (iter) =>
        getSection @s.root, @propertyName, iter

  # Update triggered by the root context. Refresh only if it is current.
  rootRefresh: (block) =>
    @refresh block unless @innerValueSet

  # Helper used to adjust the `containerIndex` of neighbours.
  adjustNeighbours: (adjustment) ->
    return if adjustment is 0
    for op in @s.opsByCid[@cid] when op instanceof BaseSectionManager
      op.containerIndex += adjustment if op.containerOrder > @containerOrder
    return

  # Subclasses should implement these.
  initialFill: ->
  numItems: ->
  add: (item, index) ->
  remove: (index) ->
  refresh: (block) ->

#### Regular Section

# The regular section creates one section for  a truthy value, or multiple
# sections for collections.
class SectionManager extends BaseSectionManager
  constructor: ->
    @sections = []
    super

  # Helper to get the number of items we know of.
  numItems: -> @sections.length

  # Create the initial sections using `getSection`.
  #
  # As with `BaseVarProp#initialFill`, if there are sections at this point,
  # and there is no inner context listener to change that, we can ditch the
  # root context listener.
  initialFill: ->
    refNode = @el.childNodes[@containerIndex] or null
    initialAppend = (item) =>
      @sections.push section = new @sectionClass item, @s
      @el.insertBefore section.el, refNode

    getSection @s.context, @propertyName, initialAppend
    if @innerValueSet = @sections.length isnt 0
      unless @listeners.context?
        @listeners.root?.unbind()
        @listeners.root = null
    else
      getSection @s.root, @propertyName, initialAppend

    @adjustNeighbours @sections.length

  # Helper to create a section for the given item at the given index. If the
  # item is an object, the section will descend into it as a subcontext.
  add: (item, index) ->
    section = new @sectionClass item, @s
    @sections.splice index, 0, section

    refNode = @el.childNodes[@containerIndex] or null
    until index is 0
      refNode = refNode.nextSibling while refNode.ghost
      refNode = refNode.nextSibling or null
      index--

    @el.insertBefore section.el, refNode
    @anim.add [section.el], {}
    @adjustNeighbours +1

  # Helper to remove the section at the given index.
  remove: (index) ->
    [section] = @sections.splice index, 1
    section.finalize()

    section.el.ghost = yes
    @anim.remove [section.el], {}, =>
      @el.removeChild section.el
      @adjustNeighbours -1

  # Helper to replace all sections in one shot. The parameter is a function
  # that takes an iterator function. The iterator function is then called
  # repeatedly by the caller for each new item.
  refresh: (block) ->
    old = for section in @sections
      section.finalize()
      section.el
    @anim.remove old, refresh: yes, =>
      @el.removeChild child for child in old
      @adjustNeighbours -old.length

    refNode = @el.childNodes[@containerIndex] or null
    @sections = []; added = []
    block (item) =>
      @sections.push section = new @sectionClass item, @s
      @el.insertBefore section.el, refNode
      added.push section.el
    @adjustNeighbours added.length
    @anim.add added, refresh: yes

#### Negated Section

# Similar to a regular `SectionManager`, but draws a single section in the
# parent context only if the property is falsy.
class NegatedSectionManager extends BaseSectionManager
  # The number of items we counted the property has.
  countedItems: 0
  # The currently displaying section or `null`.
  currentSection: null

  # The negated section needs only a count to get along.
  numItems: -> @countedItems

  # Check both the inner and root context, and if they're both falsy, create
  # a section right away, without animation.
  initialFill: ->
    count = (item) => @countedItems++

    getSection @s.context, @propertyName, count
    if @innerValueSet = @countedItems isnt 0
      unless @listeners.context?
        @listeners.root?.unbind()
        @listeners.root = null
    else
      getSection @s.root, @propertyName, count

      if @countedItems is 0
        @currentSection = section = new @sectionClass null, @s
        refNode = @el.childNodes[@containerIndex] or null
        @el.insertBefore section.el, refNode
        @adjustNeighbours +1

  # Helper called when an item is added. We simply remove the existing
  # section if this was the first item to be added.
  add: (item, index) ->
    if @countedItems++ is 0
      section = @currentSection
      @currentSection = null

      section.finalize()
      @anim.remove [section.el], {}, =>
        @el.removeChild section.el
        @adjustNeighbours -1

  # Helper called when an item is removed. If this was the last item, the
  # property is now falsy, so create a section.
  remove: (index) ->
    if @countedItems-- is 1
      @currentSection = section = new @sectionClass null, @s
      refNode = @el.childNodes[@containerIndex] or null
      @el.insertBefore section.el, refNode
      @anim.add [section.el], {}
      @adjustNeighbours +1

  # Helper called when the property is refreshed. Count the number of new
  # items, and either remove the existing or create one.
  refresh: (block) ->
    @countedSections = 0
    block (item) => @countedItems++

    if @countedItems isnt 0
      if section = @currentSection
        @currentSection = null
        section.finalize()
        @anim.remove [section.el], refresh: yes, =>
          @el.removeChild section.el
          @adjustNeighbours -1

    else
      unless @currentSection
        @currentSection = section = new @sectionClass null, @s
        refNode = @el.childNodes[@containerIndex] or null
        @el.insertBefore section.el, refNode
        @anim.add [section], refresh: yes
        @adjustNeighbours +1


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
    # FIXME: Do we want to try clean up non-`BaseVarProp`s here too?
    @opsByCid = for elementOps in ops then for op in elementOps
      op.initialFill()
      continue if op instanceof BaseVarProp and not op.willUpdate
      op

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

  # Get the HTML for the current state of the DOM.
  html: -> @el.outerHTML

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

    # Determine the animation for the next operation.
    animation = DOMJuice.defaultAnimation
    if attribute = node.getAttributeNode 'fx:'
      animation = attribute.nodeValue
      node.removeAttributeNode attribute
    if typeof animation is 'string'
      unless tmp = animations[animation]
        throw new Error "Cannot find animator named '#{animation}'"
      animation = tmp

    # Check for a `section:=` operation first. Other operations on the
    # sectioned element execute within the section context, and are
    # processed by a recursive `buildSectionClass`.
    if attribute = node.getAttributeNode 'section:'
      if node is template
        throw new Error "Template root element cannot be a section"
      {nodeValue} = attribute
      node.removeAttributeNode attribute

      if nodeValue.charAt(0) is '!'
        addOpToElement node.parentNode, class extends NegatedSectionManager
          propertyName: nodeValue.slice(1)
          sectionClass: buildSectionClass(node)
          containerIndex: index
          containerOrder: originalIndex
          animatorKlass: animation
      else
        addOpToElement node.parentNode, class extends SectionManager
          propertyName: nodeValue
          sectionClass: buildSectionClass(node)
          containerIndex: index
          containerOrder: originalIndex
          animatorKlass: animation

      return 'remove'

    # Check for a `content:=` operation, and skip the contents of the element
    # if found. Content may be there as a design placeholder.
    if attribute = node.getAttributeNode 'content:'
      {nodeValue} = attribute
      node.removeAttributeNode attribute

      if nodeValue.charAt(0) is '@'
        addOpToElement node, class extends PartialContent
          partialName: nodeValue.slice(1)
      else
        addOpToElement node, class extends VarContent
          propertyName: nodeValue
          animatorKlass: animation

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
    tmp.innerHTML = template.replace /(^\s+|\s+$)/g, ''
    unless tmp.childNodes.length is 1
      throw new Error "Template should have exactly one root element"
    template = tmp.removeChild tmp.childNodes[0]

  else unless template.nodeType is ELEMENT_NODE
    throw new Error "Expected a DOM Element or string of HTML"

  else if parentNode = template.parentNode
    parentNode.removeChild template

  buildSectionClass template


# Short-hand for creating and instantiating a template.
DOMJuice.run = (template, context) ->
  unless template instanceof Section
    template = DOMJuice template
  new template context


# Short-hand for running a template, then getting the HTML.
DOMJuice.html = (template, context) ->
  output = DOMJuice.run template, context
  retval = output.html()
  output.finalize()
  retval


# Export as global `DOMJuice` or a CommonJS module.
if module?.exports?
  module.exports = DOMJuice
else
  @DOMJuice = DOMJuice

# Export the adaptor API.
DOMJuice.getAdaptor = getAdaptor
DOMJuice.registerAdaptor = registerAdaptor

# Export the animation API.
DOMJuice.registerAnimation = registerAnimation
DOMJuice.defaultAnimation = 'none'

# The user may override this with a map of partials by name.
DOMJuice.partials = {}
