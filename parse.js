const fs = require('fs');
let buffer = fs.readFileSync('test_machine.json');
let text = buffer[0] === 0xff && buffer[1] === 0xfe ? buffer.toString('utf16le') : buffer.toString('utf8');

const lines = text.split('\n');
let output = [];
for (const line of lines) {
  if (!line.trim()) continue;
  try {
    const obj = JSON.parse(line);
    if (obj.messageType === 'print' && obj.message) {
      output.push(obj.message);
    }
  } catch (e) {
  }
}
fs.writeFileSync('full_error_utf8.txt', output.join('\n\n'), 'utf8');
