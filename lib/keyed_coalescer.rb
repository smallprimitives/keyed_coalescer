# frozen_string_literal: true

module KeyedCoalescer
  class Group
    Flight = Struct.new(:ready, :state, :result)
    private_constant :Flight

    def initialize
      @mutex = Mutex.new
      @flights = {}
    end

    def call(key)
      raise ArgumentError, "a block is required" unless block_given?

      flight = @mutex.synchronize do
        if (existing = @flights[key])
          existing.ready.wait(@mutex) while existing.state == :pending
          raise "coalesced call did not complete" unless existing.state == :succeeded

          return existing.result
        end

        @flights[key] = Flight.new(ConditionVariable.new, :pending, nil)
      end

      state = :aborted
      begin
        result = yield
        state = :succeeded
        result
      ensure
        @mutex.synchronize do
          @flights.delete(key)
          flight.result = result
          flight.state = state
          flight.ready.broadcast
        end
      end
    end
  end
end
