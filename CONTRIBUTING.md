# Contributing

Open an issue or pull request to discuss a change. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

Use Ruby 3.4 or later and run the tests and package build from the repository root.

```sh
ruby -Ilib test/group_test.rb
gem build keyed_coalescer.gemspec --strict
```

Concurrency tests use queues to control when threads reach a particular point. Use bounded waits so a regression fails quickly.

Run `ruby benchmark/group.rb` to compare direct calls with coalesced calls under distinct, mixed, and duplicate keys. The report includes the number of executed blocks so timing comparisons account for the amount of work actually performed.
