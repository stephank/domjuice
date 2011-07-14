#!/usr/bin/env node

// You'd normally just require DOMJuice:
//var DOMJuice = require('domjuice');
// We do this instead to make things work from the current directory:
var DOMJuice = require('./');

// Use jsdom to get a DOM environment server-side.
var jsdom = require('jsdom');

// Create a DOM environment.
jsdom.env('<html></html>', function(errors, window) {
  // Error checking.
  if (errors != null && errors.length !== 0) {
      errors.forEach(function(error) {
          console.log(error.stack);
      });
      return;
  }

  // Build a simple template.
  var Template = DOMJuice('<p content:="foobar"></p>', window.document);
  // Instantiate it.
  var output = new Template({ foobar: 'test' });
  // Should contain a span with the proper content.
  if (output.el.firstChild.firstChild.nodeValue === 'test')
    console.log("It worked!");
});
