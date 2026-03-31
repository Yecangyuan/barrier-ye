/*
 * barrier -- mouse and keyboard sharing utility
 * Performance monitoring implementation
 */

#include "base/PerfMonitor.h"
#include "base/Log.h"

#include <algorithm>
#include <sstream>

PerfTimer::PerfTimer(const char* name)
    : m_name(name),
      m_start(std::chrono::high_resolution_clock::now()),
      m_stopped(false)
{
}

PerfTimer::~PerfTimer()
{
    if (!m_stopped) {
        stop();
    }
}

void PerfTimer::stop()
{
    if (m_stopped) return;
    
    auto end = std::chrono::high_resolution_clock::now();
    auto us = std::chrono::duration_cast<std::chrono::microseconds>(
        end - m_start).count();
    
    PerfMonitor::instance().recordLatency(m_name, us);
    m_stopped = true;
}

PerfMonitor& PerfMonitor::instance()
{
    static PerfMonitor instance;
    return instance;
}

void PerfMonitor::recordLatency(const char* operation, int64_t us)
{
    if (us < 0) return;
    
    std::lock_guard<std::mutex> lock(m_mutex);
    auto& stats = m_latencies[operation];
    
    stats.count++;
    stats.total += us;
    
    uint64_t current_min = stats.min.load();
    while (us < current_min && !stats.min.compare_exchange_weak(current_min, us)) {}
    
    uint64_t current_max = stats.max.load();
    while (us > current_max && !stats.max.compare_exchange_weak(current_max, us)) {}
}

void PerfMonitor::recordCount(const char* metric)
{
    m_counts[metric]++;
}

double PerfMonitor::getAverageLatency(const char* operation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_latencies.find(operation);
    if (it == m_latencies.end() || it->second.count == 0) {
        return 0.0;
    }
    return static_cast<double>(it->second.total.load()) / it->second.count.load();
}

uint64_t PerfMonitor::getCount(const char* metric)
{
    auto it = m_counts.find(metric);
    if (it == m_counts.end()) {
        return 0;
    }
    return it->second.load();
}

void PerfMonitor::printStats()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    
    LOG((CLOG_INFO "========== Performance Statistics =========="));
    
    if (!m_latencies.empty()) {
        LOG((CLOG_INFO "--- Latency (microseconds) ---"));
        for (const auto& kv : m_latencies) {
            const auto& name = kv.first;
            const auto& stats = kv.second;
            if (stats.count > 0) {
                double avg = static_cast<double>(stats.total.load()) / stats.count.load();
                LOG((CLOG_INFO "%s: count=%lu, avg=%.2f, min=%lu, max=%lu",
                     name.c_str(), stats.count.load(), avg, stats.min.load(), stats.max.load()));
            }
        }
    }
    
    if (!m_counts.empty()) {
        LOG((CLOG_INFO "--- Event Counts ---"));
        for (const auto& kv : m_counts) {
            LOG((CLOG_INFO "%s: %lu", kv.first.c_str(), kv.second.load()));
        }
    }
    
    LOG((CLOG_INFO "============================================"));
}

void PerfMonitor::reset()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_latencies.clear();
    m_counts.clear();
}
