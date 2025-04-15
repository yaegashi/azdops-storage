#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

function flattenYamlOutput(obj, prefix = '') {
  for (const key of Object.keys(obj)) {
    const newKey = prefix ? `${prefix}__${key}` : key;
    if (typeof obj[key] === 'object' && obj[key] !== null) {
      flattenYamlOutput(obj[key], newKey);
    } else {
      const newVal = String(obj[key])
      console.log(`${newKey}=${newVal}`);
    }
  }
}

function loadYamlInput(inputPath, result) {
  if (fs.statSync(inputPath).isDirectory()) {
    const entries = fs.readdirSync(inputPath);
    entries.forEach(entry => {
      const fullPath = path.join(inputPath, entry);
      loadYamlInput(fullPath, result);
    });
  } else if (inputPath.endsWith('.yml') && !inputPath.endsWith('.example.yml')) {
    const content = yaml.load(fs.readFileSync(inputPath, 'utf8'));
    Object.assign(result, content);
  }
}

if (require.main === module) {
  const inputs = process.argv.slice(2);
  if (inputs.length === 0) {
    console.error('Usage: node load_yaml.js <path1> <path2> ...');
    process.exit(1);
  }

  const output = {};
  inputs.forEach(inputPath => {
    loadYamlInput(inputPath, output);
  });

  flattenYamlOutput(output);
}
