# frozen_string_literal: true

require_relative "../lib/keyed_coalescer"

THREADS = 8
CALLS_PER_THREAD = Integer(ENV.fetch("CALLS_PER_THREAD", "1000"), 10)
raise ArgumentError, "CALLS_PER_THREAD must be positive" unless CALLS_PER_THREAD.positive?

def measure(label, key_for, coalesced:, work:)
  group = KeyedCoalescer::Group.new if coalesced
  ready = Queue.new
  start = Queue.new
  workers = Array.new(THREADS) do |index|
    Thread.new do
      executed = 0
      key = key_for.call(index)
      call = lambda do
        executed += 1
        work.call
      end
      ready << true
      start.pop
      CALLS_PER_THREAD.times { group ? group.call(key, &call) : call.call }
      executed
    end
  end

  THREADS.times { ready.pop }
  GC.start
  allocations_before = GC.stat(:total_allocated_objects)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  THREADS.times { start << true }
  executions = workers.sum(&:value)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  allocations = GC.stat(:total_allocated_objects) - allocations_before

  puts format("%-32s %8.3f s  %8d blocks  %8d allocations", label, elapsed, executions, allocations)
end

puts "#{RUBY_DESCRIPTION} | #{THREADS} threads × #{CALLS_PER_THREAD} calls"
workloads = {
  "distinct" => ->(index) { index },
  "mixed" => ->(index) { index.even? ? :shared : index },
  "duplicate" => ->(_index) { :shared }
}
{
  "cheap" => -> { nil },
  "yielding" => -> { Thread.pass }
}.each do |work_label, work|
  workloads.each do |key_label, key_for|
    measure("#{work_label} #{key_label} direct", key_for, coalesced: false, work: work)
    measure("#{work_label} #{key_label} coalesced", key_for, coalesced: true, work: work)
  end
end
