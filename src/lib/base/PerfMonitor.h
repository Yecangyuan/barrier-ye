/*
 * barrier -- mouse and keyboard sharing utility
 * Performance monitoring utilities
 */

#pragma once

#include <chrono>
#include <string>
#include <map>
#include <mutex>
#include <atomic>

//! Simple performance timer for measuring operation latency
class PerfTimer {
public:
    explicit PerfTimer(const char* name);
    ~PerfTimer();

    void stop();

private:
    const char* m_name;
    std::chrono::high_resolution_clock::time_point m_start;
    bool m_stopped;
};

//! Performance monitor for tracking various metrics
class PerfMonitor {
public:
    static PerfMonitor& instance();

    // Record a latency sample (in microseconds)
    void recordLatency(const char* operation, int64_t us);

    // Record an event count
    void recordCount(const char* metric);

    // Get average latency for an operation
    double getAverageLatency(const char* operation);

    // Get total count for a metric
    uint64_t getCount(const char* metric);

    // Print statistics to log
    void printStats();

    // Reset all statistics
    void reset();

private:
    PerfMonitor() = default;

    struct LatencyStats {
        std::atomic<uint64_t> count{0};
        std::atomic<uint64_t> total{0};
        std::atomic<uint64_t> min{UINT64_MAX};
        std::atomic<uint64_t> max{0};
    };

    std::mutex m_mutex;
    std::map<std::string, LatencyStats> m_latencies;
    std::map<std::string, std::atomic<uint64_t>> m_counts;
};

// Macros for easy instrumentation
#define PERF_TIMER(name) PerfTimer _perf_timer(name)
#define PERF_RECORD_LATENCY(op, us) PerfMonitor::instance().recordLatency(op, us)
#define PERF_RECORD_COUNT(metric) PerfMonitor::instance().recordCount(metric)
#define PERF_PRINT_STATS() PerfMonitor::instance().printStats()
#define PERF_RESET() PerfMonitor::instance().reset()
