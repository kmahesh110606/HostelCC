// Disposable SMTP capture for automated tests only. Never used by local/prod Compose.
import net from 'node:net';
import http from 'node:http';
import { randomUUID } from 'node:crypto';
const messages = [];
net.createServer(socket => {
  let buffer = '', data = false, body = [], recipients = [];
  socket.write('220 test-smtp ESMTP\r\n');
  socket.on('error', () => {});
  socket.on('data', chunk => {
    buffer += chunk.toString();
    let end;
    while ((end = buffer.indexOf('\r\n')) >= 0) {
      const line = buffer.slice(0, end); buffer = buffer.slice(end + 2);
      if (data) {
        if (line !== '.') { body.push(line.replace(/^\.\./, '.')); continue; }
        messages.unshift({ ID: randomUUID(), To: recipients.map(Address => ({ Address })), Text: body.join('\n') });
        messages.splice(100); data = false; body = []; recipients = [];
        socket.write('250 Stored\r\n');
      } else if (/^(EHLO|HELO)/i.test(line)) socket.write('250 test-smtp\r\n');
      else if (/^MAIL FROM:/i.test(line)) { recipients = []; socket.write('250 OK\r\n'); }
      else if (/^RCPT TO:/i.test(line)) { recipients.push(line.match(/<([^>]+)>/)?.[1] || ''); socket.write('250 OK\r\n'); }
      else if (/^DATA$/i.test(line)) { data = true; socket.write('354 End with dot\r\n'); }
      else if (/^QUIT$/i.test(line)) socket.end('221 Bye\r\n');
      else if (/^(RSET|NOOP)/i.test(line)) { body = []; recipients = []; socket.write('250 OK\r\n'); }
      else socket.write('502 Unsupported\r\n');
    }
  });
}).listen(1025, '0.0.0.0');
http.createServer((request, response) => {
  const value = request.url === '/messages' ? { messages } : messages.find(m => request.url === `/messages/${m.ID}`);
  response.writeHead(value ? 200 : 404, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify(value || { message: 'Not found' }));
}).listen(8025, '0.0.0.0');
