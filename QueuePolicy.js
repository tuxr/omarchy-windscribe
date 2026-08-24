.pragma library

var MAX_QUEUED_JOBS = 8

function indexByKey(queue, key) {
  if (!key) return -1
  for (var i = 0; i < queue.length; i++) {
    if (queue[i].key === key) return i
  }
  return -1
}

function lastIndexByPolicy(queue, policy) {
  for (var i = queue.length - 1; i >= 0; i--) {
    if (queue[i].policy === policy) return i
  }
  return -1
}

function evictionIndex(queue) {
  var index = lastIndexByPolicy(queue, "refresh")
  if (index !== -1) return index
  return lastIndexByPolicy(queue, "impulse")
}

function offer(queue, job) {
  var next = queue.slice(0)
  var existing = indexByKey(next, job.key)
  if (existing !== -1) {
    if (job.policy === "state") next[existing] = job
    return { accepted: true, coalesced: true, queue: next, dropped: null }
  }

  if (next.length < MAX_QUEUED_JOBS) {
    next.push(job)
    return { accepted: true, coalesced: false, queue: next, dropped: null }
  }

  if (job.policy !== "state") {
    return { accepted: false, coalesced: false, queue: next, dropped: job }
  }

  var victim = evictionIndex(next)
  if (victim === -1) {
    return { accepted: false, coalesced: false, queue: next, dropped: job }
  }
  var dropped = next[victim]
  next.splice(victim, 1)
  next.push(job)
  return { accepted: true, coalesced: false, queue: next, dropped: dropped }
}

function requeueFront(queue, job) {
  var next = queue.slice(0)
  var dropped = null
  if (next.length >= MAX_QUEUED_JOBS) {
    var victim = evictionIndex(next)
    if (victim === -1) {
      return { accepted: false, coalesced: false, queue: next, dropped: job }
    }
    dropped = next[victim]
    next.splice(victim, 1)
  }
  next.unshift(job)
  return { accepted: true, coalesced: false, queue: next, dropped: dropped }
}
