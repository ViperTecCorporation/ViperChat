# MutexApplicationJob serves as a base class for jobs that require distributed locking mechanisms.
# It abstracts the locking logic using Redis and ensures that a block of code can be executed with
# mutual exclusion.
#
# The primary mechanism provided is the `with_lock` method, which accepts a key format and associated
# arguments. This method attempts to acquire a lock using the generated key, and if successful, it
# executes the provided block of code. If the lock cannot be acquired, it raises a LockAcquisitionError.
#
# To use this class, inherit from MutexApplicationJob and make use of the `with_lock` method in the
# `perform` method of the derived job class.
#
# Also see, retry mechanism here: https://edgeapi.rubyonrails.org/classes/ActiveJob/Exceptions/ClassMethods.html#method-i-retry_on
#
class MutexApplicationJob < ApplicationJob
  class LockAcquisitionError < StandardError; end

  def self.retry_on_lock_conflict(wait:, attempts:, on_exhaustion: :raise)
    retry_on LockAcquisitionError, wait: wait, attempts: attempts do |job, error|
      raise error if on_exhaustion == :raise

      job.public_send(on_exhaustion, *job.arguments)
    end
  end

  # Release only our own lease, including exceptions and non-local returns.
  def with_lock(lock_key, timeout = Redis::LockManager::LOCK_TIMEOUT)
    lock_manager = Redis::LockManager.new

    acquired = lock_manager.lock(lock_key, timeout)
    handle_failed_lock_acquisition(lock_key) unless acquired
    log_attempt(lock_key, executions)
    yield
    true
  ensure
    lock_manager.unlock(lock_key) if acquired
  end

  private

  def log_attempt(lock_key, executions)
    Rails.logger.info "[#{self.class.name}] Acquired lock for: #{lock_key} on attempt #{executions}"
  end

  def handle_failed_lock_acquisition(lock_key)
    Rails.logger.warn "[#{self.class.name}] Failed to acquire lock on attempt #{executions}: #{lock_key}"
    raise LockAcquisitionError, "Failed to acquire lock for key: #{lock_key}"
  end
end
