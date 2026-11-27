# Changelog

## 0.1.0

- Add `KeyedCoalescer::Group#call` to share one execution and its exact result among overlapping calls for the same key.
- Give followers explicit errors when the leader raises or exits early. Reject same-key recursion and support follower-only timeouts.
- Support Ruby 3.4 and later with zero third-party runtime dependencies.
