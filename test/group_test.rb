# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/keyed_coalescer"

class GroupTest < Minitest::Test
  WAIT_LIMIT = 5

  # Lookup calls hash under the group mutex. Once a follower reaches that
  # lookup, the leader cannot publish until the follower joins the flight.
  class ObservedKey
    def initialize(lookups)
      @lookups = lookups
    end

    def hash
      @lookups << Thread.current
      super
    end
  end

  def setup
    @group = KeyedCoalescer::Group.new
    @threads = []
  end

  def teardown
    @threads.select(&:alive?).each(&:kill)
    @threads.select(&:alive?).each { |thread| thread.join(WAIT_LIMIT) }
  end

  def test_overlapping_calls_share_the_exact_result
    [Object.new, nil, false].each do |expected|
      lookups = Queue.new
      key = ObservedKey.new(lookups)
      leader_started = Queue.new
      release_leader = Queue.new
      leader = start_thread do
        @group.call(key) do
          leader_started << :started
          release_leader.pop
          expected
        end
      end

      receive(leader_started)
      lookups.clear
      followers = Array.new(8) do
        follower = start_thread { @group.call(key) { raise "follower ran its block" } }
        assert_same follower, receive(lookups)
        follower
      end

      release_leader << :go
      assert_same expected, result_of(leader)
      followers.each { |follower| assert_same expected, result_of(follower) }
      assert_equal :fresh, @group.call(key) { :fresh }
    end
  end

  def test_different_keys_can_run_independently
    started = Queue.new
    release_first = Queue.new

    first = start_thread do
      @group.call(:first) do
        started << :first
        release_first.pop
        :first_result
      end
    end
    assert_equal :first, receive(started)

    second = start_thread { @group.call(:second) { :second_result } }
    assert_equal :second_result, result_of(second)
    assert_predicate first, :alive?

    release_first << :go
    assert_equal :first_result, result_of(first)
  end

  private

  def start_thread(&work)
    Thread.new do
      Thread.current.report_on_exception = false
      work.call
    end.tap { |thread| @threads << thread }
  end

  def receive(queue)
    queue.pop(timeout: WAIT_LIMIT).tap { |value| refute_nil value, "timed out waiting for a test signal" }
  end

  def result_of(thread)
    assert thread.join(WAIT_LIMIT), "worker did not finish"
    thread.value
  end
end
