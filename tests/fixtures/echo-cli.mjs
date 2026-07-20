#!/usr/bin/env node
// Stand-in for reminders-cli: echoes the argv it actually received so tests can
// assert that arguments survive the boundary uninterpreted.
console.log(JSON.stringify({ success: true, data: { argv: process.argv.slice(2) } }));
