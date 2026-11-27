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
