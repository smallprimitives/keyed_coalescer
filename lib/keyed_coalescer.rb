# frozen_string_literal: true

module KeyedCoalescer
  class Error < StandardError; end
  class SharedCallError < Error; end
  class FlightAbortedError < Error; end
  class RecursiveCallError < Error; end
  class TimeoutError < Error; end

  class Group
    Flight = Struct.new(:leader, :ready, :state, :value)
    MAX_WAIT_INTERVAL = 86_400
    private_constant :Flight, :MAX_WAIT_INTERVAL

    def initialize
      @mutex = Mutex.new
      @flights = {}
    end

    def call(key, timeout: nil)
      raise ArgumentError, "a block is required" unless block_given?

      timeout = timeout_seconds(timeout)
      flight, leader = @mutex.synchronize do
        if (existing = @flights[key])
          if existing.leader.equal?(Thread.current)
            raise RecursiveCallError, "the current thread is already executing a call for this key"
          end

          wait_for(existing, timeout)
          [existing, false]
        else
          [@flights[key] = Flight.new(Thread.current, ConditionVariable.new, :pending, nil), true]
        end
      end

      return shared_outcome(flight) unless leader

      run(key, flight) { yield }
    end

    private

    def run(key, flight)
      state = :aborted
      begin
        value = yield
        state = :succeeded
        value
      rescue Exception => error
        state = :failed
        value = error
        raise
      ensure
        @mutex.synchronize do
          @flights.delete(key)
          flight.value = value
          flight.state = state
          flight.ready.broadcast
        end
      end
    end

    def wait_for(flight, timeout)
      deadline = monotonic_time + timeout if timeout
      while flight.state == :pending
        if deadline
          remaining = deadline - monotonic_time
          raise TimeoutError, "timed out waiting for the shared call" if remaining <= 0

          # Ruby's native wait rejects seconds outside the platform's time range.
          interval = [remaining, MAX_WAIT_INTERVAL].min
        end
        flight.ready.wait(@mutex, interval)
      end
    end

    def shared_outcome(flight)
      case flight.state
      when :succeeded
        flight.value
      when :failed
        raise SharedCallError, "the shared call raised an exception", cause: flight.value
      when :aborted
        raise FlightAbortedError, "the shared call exited before returning a result", cause: nil
      end
    end

    def timeout_seconds(timeout)
      return if timeout.nil?

      if timeout.is_a?(Numeric) && timeout.real? && timeout.between?(0, Float::MAX)
        seconds = timeout.to_f
        return seconds if seconds.finite?
      end
      raise ArgumentError, "timeout must be nil or a finite nonnegative real number of seconds"
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
