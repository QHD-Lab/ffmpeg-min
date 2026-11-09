// node rtsp401.mjs <port> <record file> <count>: an RTSP server on 127.0.0.1 that answers
// every request with 401 Basic, so ffmpeg retries with its credential. Each Authorization
// value it receives is appended to <record file>. Exits after <count> of them, or 30 s.
import { createServer } from 'node:net'
import { appendFileSync } from 'node:fs'

const [port, record, count] = process.argv.slice(2)
let seen = 0
const server = createServer((sock) => {
  let buf = Buffer.alloc(0)
  sock.on('error', () => {})
  sock.on('data', (data) => {
    buf = Buffer.concat([buf, data])
    for (;;) {
      const end = buf.indexOf('\r\n\r\n')
      if (end < 0) return
      const head = buf.subarray(0, end).toString()
      const body = Number(/^Content-Length:\s*(\d+)/im.exec(head)?.[1] ?? 0)
      if (buf.length < end + 4 + body) return
      buf = buf.subarray(end + 4 + body)
      const cseq = /^CSeq:\s*(\d+)/im.exec(head)?.[1] ?? '0'
      sock.write(`RTSP/1.0 401 Unauthorized\r\nCSeq: ${cseq}\r\nWWW-Authenticate: Basic realm="smoke"\r\n\r\n`)
      const auth = /^Authorization:\s*(.*)$/im.exec(head)?.[1]
      if (auth) {
        appendFileSync(record, `${auth}\n`)
        if (++seen >= Number(count)) server.close()
      }
    }
  })
})
server.listen(Number(port), '127.0.0.1')
setTimeout(() => process.exit(0), 30000).unref()
