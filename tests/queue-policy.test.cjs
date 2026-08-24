const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadPolicy() {
  const file = path.join(__dirname, "..", "QueuePolicy.js")
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
  const context = {}
  vm.createContext(context)
  vm.runInContext(source, context, { filename: file })
  return context
}

function job(id, policy, key = "") {
  return { args: [id], kind: id, key, policy }
}

test("coalesces duplicate refresh work", () => {
  const policy = loadPolicy()
  const first = policy.offer([], job("status-1", "refresh", "status"))
  const second = policy.offer(first.queue, job("status-2", "refresh", "status"))
  assert.equal(first.accepted, true)
  assert.equal(second.accepted, true)
  assert.equal(second.coalesced, true)
  assert.equal(second.queue.length, 1)
  assert.equal(second.queue[0].kind, "status-1")
})

test("connection and firewall setters are independently latest-wins", () => {
  const policy = loadPolicy()
  let queue = policy.offer([], job("connect-a", "state", "connection")).queue
  queue = policy.offer(queue, job("firewall-on", "state", "firewall")).queue
  queue = policy.offer(queue, job("disconnect", "state", "connection")).queue
  queue = policy.offer(queue, job("firewall-off", "state", "firewall")).queue
  assert.deepEqual(Array.from(queue, item => item.kind), ["disconnect", "firewall-off"])
})

test("accepted IP impulses remain FIFO and a flood stays bounded", () => {
  const policy = loadPolicy()
  let queue = []
  let rejected = 0
  for (let i = 0; i < 10000; i++) {
    const result = policy.offer(queue, job(`rotate-${i}`, "impulse"))
    queue = result.queue
    if (!result.accepted) rejected++
  }
  assert.equal(queue.length, 8)
  assert.deepEqual(Array.from(queue, item => item.kind), [
    "rotate-0", "rotate-1", "rotate-2", "rotate-3",
    "rotate-4", "rotate-5", "rotate-6", "rotate-7"
  ])
  assert.equal(rejected, 9992)
})

test("a full queue admits safety-relevant state by evicting refresh first", () => {
  const policy = loadPolicy()
  let queue = [job("status", "refresh", "status")]
  for (let i = 0; i < 7; i++) queue.push(job(`pin-${i}`, "impulse"))
  const result = policy.offer(queue, job("disconnect", "state", "connection"))
  assert.equal(result.accepted, true)
  assert.equal(result.queue.length, 8)
  assert.equal(result.queue.some(item => item.kind === "status"), false)
  assert.equal(result.queue.at(-1).kind, "disconnect")
})

test("a full impulse queue rejects state without evicting accepted work", () => {
  const policy = loadPolicy()
  const queue = []
  for (let i = 0; i < 8; i++) queue.push(job(`rotate-${i}`, "impulse"))
  const result = policy.offer(queue, job("disconnect", "state", "connection"))
  assert.equal(result.accepted, false)
  assert.equal(result.coalesced, false)
  assert.deepEqual(
    Array.from(result.queue, item => item.kind),
    Array.from(queue, item => item.kind)
  )
})

test("retry goes to the front without exceeding the cap", () => {
  const policy = loadPolicy()
  let queue = [job("status", "refresh", "status")]
  for (let i = 0; i < 7; i++) queue.push(job(`rotate-${i}`, "impulse"))
  const result = policy.requeueFront(queue, job("running-job", "state", "connection"))
  assert.equal(result.accepted, true)
  assert.equal(result.queue.length, 8)
  assert.equal(result.queue[0].kind, "running-job")
  assert.equal(result.queue.some(item => item.kind === "status"), false)
})

test("a keyed retry is superseded by newer queued work with the same key", () => {
  const policy = loadPolicy()
  const newer = job("disconnect", "state", "connection")
  const queue = [job("status", "refresh", "status"), newer]
  const result = policy.requeueFront(queue, job("connect-a", "state", "connection"))
  assert.equal(result.accepted, true)
  assert.equal(result.coalesced, true)
  assert.equal(result.dropped, null)
  assert.deepEqual(Array.from(result.queue, item => item.kind), ["status", "disconnect"])
})

test("policy exposes the fixed public queue bound", () => {
  const policy = loadPolicy()
  assert.equal(policy.MAX_QUEUED_JOBS, 8)
})

test("distinct read keys coalesce independently", () => {
  const policy = loadPolicy()
  let queue = []
  for (const key of ["which", "status", "locations", "fav", "static"])
    queue = policy.offer(queue, job(key, "refresh", key)).queue
  for (const key of ["which", "status", "locations", "fav", "static"])
    queue = policy.offer(queue, job(`${key}-duplicate`, "refresh", key)).queue
  assert.equal(queue.length, 5)
  assert.deepEqual(Array.from(queue, item => item.key), [
    "which", "status", "locations", "fav", "static"
  ])
})
