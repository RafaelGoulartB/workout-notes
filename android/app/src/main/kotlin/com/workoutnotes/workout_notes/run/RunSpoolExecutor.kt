package com.workoutnotes.workout_notes.run

import android.util.Log
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Single sequential worker for every run-spool disk operation (appends,
 * checkpoints, reads, deletes), so GPS callbacks and channel calls on the main
 * thread never wait on file I/O and operations keep the order they were queued.
 *
 * One process-wide instance ([shared]) is used by the tracking service and the
 * bridge, so a read queued after a write always observes it.
 */
class RunSpoolExecutor(
    private val onError: (Throwable) -> Unit = { error ->
        try {
            Log.w("RunSpoolExecutor", "Run spool task failed", error)
        } catch (_: Throwable) {
            // android.util.Log is unavailable in plain JVM unit tests.
        }
    },
) {
    @Volatile private var worker: Thread? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "run-spool-io").also {
            it.isDaemon = true
            worker = it
        }
    }

    /** Fire and forget: runs after everything queued before it. Failures are logged, never thrown. */
    fun execute(task: () -> Unit) {
        try {
            executor.execute {
                try {
                    task()
                } catch (error: Throwable) {
                    onError(error)
                }
            }
        } catch (error: Throwable) {
            // Rejected only after shutdown; nothing sensible to do for a spool write.
            onError(error)
        }
    }

    /**
     * Runs [task] on the worker (after all queued writes) and waits for its
     * result. Exceptions from [task] propagate to the caller. Use only where the
     * caller genuinely needs the value synchronously; prefer [submit].
     */
    fun <T> call(task: () -> T): T {
        if (Thread.currentThread() === worker) return task()
        try {
            return executor.submit(Callable { task() }).get()
        } catch (error: ExecutionException) {
            throw error.cause ?: error
        }
    }

    /**
     * Runs [task] on the worker and hands the outcome to [deliver] (from the
     * worker thread; callers post to the main thread themselves).
     */
    fun <T> submit(task: () -> T, deliver: (Result<T>) -> Unit) {
        execute {
            val outcome = try {
                Result.success(task())
            } catch (error: Throwable) {
                Result.failure(error)
            }
            deliver(outcome)
        }
    }

    /**
     * Blocks until everything queued so far has finished (or [timeoutMillis]
     * elapses). Returns true when the queue drained.
     */
    fun flush(timeoutMillis: Long = DEFAULT_FLUSH_TIMEOUT_MS): Boolean {
        if (Thread.currentThread() === worker) return true
        return try {
            executor.submit(Runnable {}).get(timeoutMillis, TimeUnit.MILLISECONDS)
            true
        } catch (_: TimeoutException) {
            false
        } catch (_: Throwable) {
            false
        }
    }

    companion object {
        const val DEFAULT_FLUSH_TIMEOUT_MS = 3_000L

        val shared: RunSpoolExecutor by lazy { RunSpoolExecutor() }
    }
}
