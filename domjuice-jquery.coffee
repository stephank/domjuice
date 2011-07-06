#     DOMJuice jQuery animators, © 2011 Stéphan Kochen.
#     Made available under the MIT license.
#     http://stephank.github.com/domjuice


# Straight-forward fade animation.
DOMJuice.registerAnimation 'fade', class Fade
  add: (elements, options) ->
    $(elements).fadeIn()

  remove: (elements, options, callback) ->
    $(elements).fadeOut callback


# Sequential fade animation.
DOMJuice.registerAnimation 'seq-fade', class SequentialFade
  constructor: ->
    @q = $ {}

  add: (elements, options) ->
    $elements = $ elements
    $elements.hide()
    @q.queue (next) ->
      $elements.fadeIn next

  remove: (elements, options, callback) ->
    @q.queue (next) ->
      $(elements).fadeOut ->
        callback()
        next()


# Straight-forward slide animation.
DOMJuice.registerAnimation 'slide', class Slide
  add: (elements, options) ->
    $(elements).slideDown()

  remove: (elements, options, callback) ->
    $(elements).slideUp callback


# Sequential slide animation.
DOMJuice.registerAnimation 'seq-slide', class SequentialSlide
  constructor: ->
    @q = $ {}

  add: (elements, options) ->
    $elements = $ elements
    $elements.hide()
    @q.queue (next) ->
      $elements.slideDown next

  remove: (elements, options, callback) ->
    @q.queue (next) ->
      $(elements).slideUp ->
        callback()
        next()
