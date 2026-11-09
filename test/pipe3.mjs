// node pipe3.mjs <program> <args...>: runs the program with SMOKE_SECRET written to an
// extra pipe on fd 3, the way iCrew passes -auth_file pipe:3. smoke.sh uses it on Windows,
// where Git Bash cannot hand fd 3 to a native program but Node can.
import { spawn } from 'node:child_process'

const { SMOKE_SECRET: secret, ...env } = process.env
const [program, ...args] = process.argv.slice(2)
const child = spawn(program, args, { env, stdio: ['ignore', 'inherit', 'inherit', 'pipe'] })
child.stdio[3].end(`${secret}\n`)
child.on('exit', (code) => process.exit(code ?? 1))
