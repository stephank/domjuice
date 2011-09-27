module.exports = exports = require './domjuice'

# The default document server-side is a JSDom document.
{jsdom} = require 'jsdom'
exports.document = jsdom()

# Enable Backbone.js support.
require './domjuice-backbone'
