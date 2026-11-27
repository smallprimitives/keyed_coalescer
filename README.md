# Keyed Coalescer

Share one execution and its result among overlapping Ruby calls with the same key.

```ruby
require "keyed_coalescer"

requests = KeyedCoalescer::Group.new
user = requests.call("user:42") { api.fetch_user(42) }
```

The first call for a key runs its block. Overlapping calls on the same group and key
share the result object. Calls with other keys can run independently. Once the first
call finishes, a later call can start new work for that key.

Requires Ruby 3.4 or later. The gem has zero third-party runtime dependencies.

## Failures and timeouts

- If the first call raises, it receives its original exception. Waiting callers
  each receive a `KeyedCoalescer::SharedCallError` whose `cause` is that exception.
  If the block exits early without raising, such as with `throw`, waiting callers
  receive `KeyedCoalescer::FlightAbortedError`. Subsequent callers can try again.
- Pass `timeout:` in seconds to limit how long a caller waits for existing work.
  The value must be a finite nonnegative real number or `nil` for no limit.
  Expiration raises `KeyedCoalescer::TimeoutError` for that caller. It leaves
  the running block and other callers alone. Zero permits no waiting. A caller
  that runs its own block has no execution deadline. If a result or failure has
  been published when the waiter checks the deadline, the published outcome wins.
- A thread already running work for a key receives
  `KeyedCoalescer::RecursiveCallError` if it calls that key again on the same group.
  Callers are responsible for avoiding cycles across keys or threads.

Use stable keys with nonblocking `hash` and `eql?` methods. Callers that mutate
a shared result must coordinate those changes. The group is designed for threads
in one Ruby process. Fiber schedulers, Ractors, and abrupt thread or process
termination are outside its supported contract.
