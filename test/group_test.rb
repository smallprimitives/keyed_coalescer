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
    [[Object.new, 99], [nil, 2], [false, 2]].each do |expected, follower_count|
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
      followers = Array.new(follower_count) do
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

  def test_leader_failure_reaches_followers_with_separate_errors
    original = RuntimeError.new("request failed")
    leader, release, key, lookups = hold_leader { raise original }
    followers = Array.new(2) { join_flight(key, lookups, KeyedCoalescer::SharedCallError) }

    release << :go
    assert_same original, assert_raises(RuntimeError) { result_of(leader) }
    first, second = followers.map { |follower| result_of(follower) }
    assert_same original, first.cause
    assert_same original, second.cause
    refute_same first, second
    assert_equal :fresh, @group.call(key) { :fresh }
  end

  def test_nonlocal_exit_wakes_followers_and_preserves_the_leader_exit
    leader, release, key, lookups = hold_leader(:aborted) { throw :aborted, :escaped }
    follower = join_flight(key, lookups, KeyedCoalescer::FlightAbortedError)

    release << :go
    assert_equal :escaped, result_of(leader)
    assert_instance_of KeyedCoalescer::FlightAbortedError, result_of(follower)
    assert_equal :fresh, @group.call(key) { :fresh }
  end

  def test_same_key_recursion_raises_and_different_key_recursion_succeeds
    recursive = start_thread do
      @group.call(:outer) { @group.call(:outer) { raise "recursive block ran" } }
    end
    assert_raises(KeyedCoalescer::RecursiveCallError) { result_of(recursive) }
    assert_equal :nested, @group.call(:outer) { @group.call(:inner) { :nested } }
  end

  def test_timed_out_followers_leave_the_leader_and_other_followers_running
    expected = Object.new
    leader, release, key, lookups = hold_leader { expected }
    untimed = join_flight(key, lookups)
    long_wait = join_flight(key, lookups, timeout: Float::MAX)

    [0, 0.01].each do |timeout|
      timed = join_flight(key, lookups, KeyedCoalescer::TimeoutError, timeout: timeout)
      assert_instance_of KeyedCoalescer::TimeoutError, result_of(timed)
      assert_predicate leader, :alive?
      assert_predicate untimed, :alive?
      assert_predicate long_wait, :alive?
    end

    release << :go
    [leader, untimed, long_wait].each { |thread| assert_same expected, result_of(thread) }
    assert_equal :fresh, @group.call(key, timeout: 0) { :fresh }
  end

  def test_invalid_timeouts_are_rejected_before_running_the_block
    [-1, Float::INFINITY, Float::NAN, "1", true, Complex(1, 2), 10**500].each do |timeout|
      assert_raises(ArgumentError) { @group.call(:key, timeout: timeout) { flunk "block ran" } }
    end
    assert_raises(ArgumentError) { @group.call(:key) }
    assert_equal :fresh, @group.call(:key, timeout: Rational(1, 2)) { :fresh }
  end

  private

  def hold_leader(catch_tag = nil, &finish)
    lookups = Queue.new
    key = ObservedKey.new(lookups)
    started = Queue.new
    release = Queue.new
    leader = start_thread do
      catch(catch_tag) do
        @group.call(key) do
          started << :started
          release.pop
          finish.call
        end
      end
    end
    receive(started)
    lookups.clear
    [leader, release, key, lookups]
  end

  def join_flight(key, lookups, expected_error = nil, timeout: nil)
    follower = start_thread do
      @group.call(key, timeout: timeout) { raise "follower ran its block" }
    rescue KeyedCoalescer::Error => error
      raise unless expected_error && error.is_a?(expected_error)

      error
    end
    assert_same follower, receive(lookups)
    follower
  end

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
