require 'test_helper'

module SuckerPunch
  class QueueTest < Minitest::Test
    def setup
      @queue = "fake"
    end

    def teardown
      SuckerPunch::Queue.clear
    end

    def test_queue_is_created_if_it_doesnt_exist
      SuckerPunch::Queue::QUEUES.clear
      assert SuckerPunch::Queue::QUEUES.empty?
      queue = SuckerPunch::Queue.find_or_create(@queue)
      assert queue.pool.is_a?(Concurrent::ThreadPoolExecutor)
    end

    def test_queue_is_created_with_2_workers
      queue = SuckerPunch::Queue.find_or_create(@queue)
      assert_equal 2, queue.pool.max_length
      assert_equal 2, queue.pool.min_length
    end

    def test_queue_num_workers_can_be_set
      queue = SuckerPunch::Queue.find_or_create(@queue, 4)
      assert_equal 4, queue.pool.max_length
      assert_equal 4, queue.pool.min_length
    end

    def test_same_queue_is_returned_on_subsequent_queries
      SuckerPunch::Queue::QUEUES.clear
      queue = SuckerPunch::Queue.find_or_create(@queue)
      assert_equal queue, SuckerPunch::Queue.find_or_create(@queue)
    end

    def test_clear_removes_queues_and_stats
      SuckerPunch::Queue.find_or_create(@queue)
      SuckerPunch::Counter::Busy.new(@queue).increment
      SuckerPunch::Counter::Processed.new(@queue).increment
      SuckerPunch::Counter::Failed.new(@queue).increment

      SuckerPunch::Queue.clear

      assert SuckerPunch::Counter::Busy.new(@queue).value == 0
      assert SuckerPunch::Counter::Processed.new(@queue).value == 0
      assert SuckerPunch::Counter::Failed.new(@queue).value == 0
    end

    def test_returns_queue_stats
      latch = Concurrent::CountDownLatch.new

      # run a job to setup workers
      2.times { FakeNilJob.perform_async }

      queue = SuckerPunch::Queue.find_or_create(FakeNilJob.to_s)
      queue.pool.post { latch.count_down }
      latch.wait(0.1)

      all_stats = SuckerPunch::Queue.all
      stats = all_stats[FakeNilJob.to_s]
      assert stats["workers"]["total"] > 0
      assert stats["workers"]["busy"] == 0
      assert stats["workers"]["idle"] > 0
      assert stats["jobs"]["processed"] > 0
      assert stats["jobs"]["failed"] == 0
      assert stats["jobs"]["enqueued"] == 0
    end

    private

    class FakeNilJob
      include SuckerPunch::Job
      def perform
        nil
      end
    end
  end
end
