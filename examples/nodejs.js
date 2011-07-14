#!/usr/bin/env node

// You'd normally just require DOMJuice:
//var dj = require('domjuice');
// We do this instead to make things work from the current directory:
var dj = require('../');

// Run a simple template.
var output = dj.run(
    '<p content:="foobar"></p>',
    { foobar: 'test' }
);

// Should contain a span with the proper content.
if (output.el.firstChild.firstChild.nodeValue === 'test')
  console.log("It worked!");
